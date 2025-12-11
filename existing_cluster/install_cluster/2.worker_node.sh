#!/bin/bash
set -e

# Script de Configuración de Worker Node Kubernetes
# Instala containerd 1.6.24, kubeadm/kubelet/kubectl 1.28.2
# Configura requisitos del sistema y une el nodo al cluster

# Habilitar modo debug si se pasa -x como argumento
[[ "${1}" == "-x" ]] && set -x && shift

readonly CONTAINERD_VERSION="1.6.24-1"
readonly K8S_VERSION="1.28.2-1.1"
readonly K8S_MINOR="v1.28"
readonly API_ENDPOINT="k8s-endpoint"

log() {
echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
echo "[ERROR] $*" >&2
exit 1
}

check_root() {
if [[ $EUID -ne 0 ]]; then
error "Este script debe ejecutarse como root"
fi
log "Verificación de permisos root: OK"
}

check_arguments() {
if [[ $# -lt 2 ]]; then
error "Uso: $0 <IP_CONTROL_PLANE> \"<COMANDO_JOIN>\""
fi

readonly CONTROL_PLANE_IP="$1"
readonly JOIN_COMMAND="$2"

log "Control Plane IP: ${CONTROL_PLANE_IP}"
}

install_containerd() {
log "Instalando containerd ${CONTAINERD_VERSION}"

if systemctl is-active --quiet containerd; then
log "containerd ya está ejecutándose, omitiendo instalación"
return 0
fi

apt-get update
apt-get install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Agregar clave GPG de Docker si no existe
if ! apt-key list | grep -q "Docker Release"; then
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
fi

# Agregar repositorio de Docker si no existe
if ! grep -q "download.docker.com" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
fi

apt-get update
apt-get install -y containerd.io="${CONTAINERD_VERSION}"

# Generar configuración por defecto
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml

# Habilitar driver de cgroup systemd
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# Configurar crictl para usar containerd
cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

log "containerd instalado y configurado"
}

install_kubernetes() {
log "Instalando Kubernetes ${K8S_VERSION}"

if command -v kubeadm &>/dev/null; then
log "Herramientas de Kubernetes ya instaladas, omitiendo"
return 0
fi

mkdir -p -m 755 /etc/apt/keyrings

# Agregar clave GPG de Kubernetes
if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" |
gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi

# Agregar repositorio de Kubernetes
if [[ ! -f /etc/apt/sources.list.d/kubernetes.list ]]; then
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" |
tee /etc/apt/sources.list.d/kubernetes.list
fi

apt-get update
apt-get install -y \
kubelet="${K8S_VERSION}" \
kubeadm="${K8S_VERSION}" \
kubectl="${K8S_VERSION}"

# Bloquear versiones para prevenir actualizaciones automáticas
apt-mark hold kubelet kubeadm kubectl
log "Herramientas de Kubernetes instaladas"
}

configure_system() {
log "Configurando requisitos del sistema"

# Deshabilitar swap
if swapon --show | grep -q .; then
swapoff -a
log "Swap deshabilitado"
fi

# Comentar entradas de swap en fstab
sed -i '/^\/swap/s/^/#/' /etc/fstab

# Cargar módulos del kernel
modprobe overlay
modprobe br_netfilter

# Hacer módulos persistentes
cat >/etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF

# Configurar parámetros de sysctl
cat >/etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system >/dev/null

log "Configuración del sistema completada"
}

configure_hosts() {
log "Configurando archivo hosts"

# Agregar o actualizar entrada del control plane
if grep -q "${API_ENDPOINT}" /etc/hosts; then
sed -i "/${API_ENDPOINT}/c\\${CONTROL_PLANE_IP} ${API_ENDPOINT}" /etc/hosts
log "Entrada ${API_ENDPOINT} actualizada en /etc/hosts"
else
echo "${CONTROL_PLANE_IP} ${API_ENDPOINT}" >>/etc/hosts
log "Entrada ${API_ENDPOINT} agregada a /etc/hosts"
fi
}

join_cluster() {
log "Uniéndose al cluster"

# Verificar si ya está unido al cluster
if systemctl is-active --quiet kubelet && [[ -f /etc/kubernetes/kubelet.conf ]]; then
log "Este nodo ya está unido al cluster"
return 0
fi

# Ejecutar comando de join
log "Ejecutando: ${JOIN_COMMAND}"
eval "${JOIN_COMMAND}"

# Esperar a que kubelet esté activo
local retries=30
while ! systemctl is-active --quiet kubelet; do
if [[ ${retries} -le 0 ]]; then
error "kubelet no se activó después de unirse al cluster"
fi

if [[ $((retries % 10)) -eq 0 ]]; then
log "Esperando a que kubelet esté activo... (${retries} intentos restantes)"
fi

sleep 2
((retries--))
done

log "Worker node unido al cluster exitosamente"
}

main() {
check_root
check_arguments "$@"
log "Iniciando configuración del worker node"

install_containerd
install_kubernetes
configure_system
configure_hosts
join_cluster

log "Configuración completada"
log ""
log "Este nodo ahora es parte del cluster Kubernetes"
log "Verifica el estado desde el control plane con:"
log "  kubectl get nodes"
}

main "$@"
