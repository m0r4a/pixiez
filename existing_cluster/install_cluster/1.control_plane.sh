#!/bin/bash
set -e

# Script de Configuración de Control Plane Kubernetes
# Instala containerd 1.6.24, kubeadm/kubelet/kubectl 1.28.2
# Configura requisitos del sistema e inicializa el plano de control

# Habilitar modo debug si se pasa -x como argumento
[[ "${1:-}" == "-x" ]] && set -x

readonly CONTAINERD_VERSION="1.6.24-1"
readonly K8S_VERSION="1.28.2-1.1"
readonly K8S_MINOR="v1.28"
readonly POD_CIDR="192.168.0.0/16"
readonly API_ENDPOINT="k8s-endpoint"
readonly CALICO_VERSION="v3.26.4"

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

# Agregar endpoint de API a hosts
if ! grep -q "${API_ENDPOINT}" /etc/hosts; then
echo "127.0.0.1 ${API_ENDPOINT}" >>/etc/hosts
log "Agregado ${API_ENDPOINT} a /etc/hosts"
fi

log "Configuración del sistema completada"
}

get_primary_ip() {
# Obtener primera IP no-loopback
local primary_ip
primary_ip=$(ip -4 addr show 2>/dev/null |
grep -oP '(?<=inet\s)\d+(\.\d+){3}' |
grep -v '127.0.0.1' |
head -n 1)

echo "${primary_ip}"
}

initialize_cluster() {
log "Inicializando cluster de Kubernetes"

if [[ -f /etc/kubernetes/admin.conf ]]; then
log "Cluster ya inicializado, omitiendo"
return 0
fi

local primary_ip
primary_ip=$(get_primary_ip)

if [[ -z "${primary_ip}" ]]; then
error "No se pudo determinar la dirección IP primaria"
fi
log "Usando dirección del servidor API: ${primary_ip}"

# Descargar imágenes necesarias
kubeadm config images pull

# Inicializar cluster
kubeadm init \
--apiserver-advertise-address="${primary_ip}" \
--pod-network-cidr="${POD_CIDR}" \
--control-plane-endpoint="${API_ENDPOINT}"

log "Cluster inicializado exitosamente"
}

setup_kubeconfig() {
log "Configurando acceso de kubectl"

export KUBECONFIG=/etc/kubernetes/admin.conf

# Esperar a que el servidor API esté listo
local retries=60
log "Esperando a que el API server esté disponible..."

while ! kubectl get --raw /healthz &>/dev/null; do
if [[ ${retries} -le 0 ]]; then
error "El servidor API no se volvió disponible después de 120 segundos"
fi

if [[ $((retries % 10)) -eq 0 ]]; then
log "Esperando API server... (${retries} intentos restantes)"
fi

sleep 2
((retries--))
done

log "Servidor API está listo"

# Verificar que podemos listar nodos
if kubectl get nodes &>/dev/null; then
log "Conexión con el cluster verificada"
else
error "No se pudo conectar con el cluster"
fi
}

install_calico() {
log "Instalando Calico CNI ${CALICO_VERSION}"

if kubectl get namespace tigera-operator &>/dev/null; then
log "Calico parece estar ya instalado, omitiendo"
return 0
fi

# Instalar operador de Tigera
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

# Descargar y modificar recursos personalizados
local manifest="/tmp/calico-custom-resources.yaml"
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" -o "${manifest}"

# Actualizar CIDR para que coincida con la red de pods
sed -i "s|cidr: 192.168.0.0/16|cidr: ${POD_CIDR}|" "${manifest}"

kubectl apply -f "${manifest}"
rm -f "${manifest}"

log "Instalación de Calico iniciada"
log "Monitorear con: kubectl get pods -n calico-system"
}

main() {
check_root
log "Iniciando configuración del cluster Kubernetes"

install_containerd
install_kubernetes
configure_system
initialize_cluster
setup_kubeconfig
install_calico

# Configurar kubeconfig permanente para root
if ! grep -q "KUBECONFIG=/etc/kubernetes/admin.conf" ~/.bashrc; then
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >>~/.bashrc
log "Kubeconfig configurado para usuario root"
fi

log "Configuración completada"
log ""
log "El cluster está listo. Ejecuta 'source ~/.bashrc' o inicia una nueva sesión."
log ""

# Generar comando de join para worker nodes
local join_command
join_command=$(kubeadm token create --print-join-command 2>/dev/null)

if [[ -n "${join_command}" ]]; then
local control_plane_ip
control_plane_ip=$(get_primary_ip)

log "=========================================="
log "COMANDO PARA WORKER NODES"
log "=========================================="
log ""
log "En cada worker node, ejecuta:"
log ""
log "  ./2_worker_node.sh ${control_plane_ip} \"${join_command}\""
log ""
log "=========================================="
fi

log ""
log "Para configurar acceso de usuario regular:"
log "  mkdir -p \$HOME/.kube"
log "  sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
log "  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
}

main "$@"
