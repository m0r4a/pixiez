#!/bin/bash

source "$(dirname "$0")/utils.sh"

CUSTOM_DEPLOYMENTS=("java-problematic-client" "java17-service" "service-a" "traffic-generator")
MISSING_DEPLOY=0

if ! validate_commands "${REQUIRED_TOOLS[@]}"; then
	echo "Faltan dependencias críticas. Abortando."
	exit 1
fi

for deploy in "${CUSTOM_DEPLOYMENTS[@]}"; do
	if ! kubectl get deployment "$deploy" >/dev/null 2>&1; then
		MISSING_DEPLOY=1
		break
	fi
done

if [ "$MISSING_DEPLOY" -eq 1 ]; then
	echo "Iniciando los pods personalizados..."
	kubectl apply -f ./manifests/

	echo "Esperando a que los deployments estén listos..."
	kubectl wait --for=condition=available --timeout=60s deployment/service-a >/dev/null 2>&1
else
	echo "Los pods personalizados ya están desplegados."
fi

echo "Iniciando configuración de Pixie Cloud..."
echo ""

# Gestión del Repositorio
if [ ! -d ./pixie ]; then
	echo "Clonando el repositorio..."
	git clone https://github.com/pixie-io/pixie.git
else
	echo "Repositorio detectado."
fi

cd ./pixie || exit 1

git fetch --tags >/dev/null 2>&1

echo "Calculando versión más reciente..."
LATEST_CLOUD_RELEASE=$(git tag | perl -ne 'print $1 if /release\/cloud\/v([^\-]*)$/' | sort -t '.' -k1,1nr -k2,2nr -k3,3nr | head -n 1)
export LATEST_CLOUD_RELEASE
TARGET_TAG="release/cloud/v${LATEST_CLOUD_RELEASE}"
FILE_TO_PATCH="k8s/cloud/public/kustomization.yaml"

# Verificación idempotente de versión y parche
CURRENT_HEAD=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$CURRENT_HEAD" == "HEAD" ]; then CURRENT_HEAD=$(git name-rev --name-only HEAD); fi

if [[ "$CURRENT_HEAD" != *"$TARGET_TAG"* ]] || ! grep -q "\"${LATEST_CLOUD_RELEASE}\"" "$FILE_TO_PATCH"; then
	echo "Actualizando a la versión ${TARGET_TAG}..."
	git checkout . >/dev/null 2>&1
	git checkout "$TARGET_TAG" >/dev/null 2>&1
	perl -pi -e "s|newTag: latest|newTag: \"${LATEST_CLOUD_RELEASE}\"|g" "$FILE_TO_PATCH"
else
	echo "Repositorio ya actualizado a ${TARGET_TAG}"
fi

# Certificados y Namespace
echo "Verificando certificado..."
mkcert -install >/dev/null 2>&1

echo "Verificando namespace..."
kubectl get namespace plc >/dev/null 2>&1 || kubectl create namespace plc

# Secretos
echo "Verificando secretos..."

# Cuenta secretos que no sean el default-token
SECRET_COUNT=$(kubectl get secrets -n plc --no-headers 2>/dev/null | grep -v 'default-token' | wc -l)
if [ "$SECRET_COUNT" -eq 0 ]; then
	echo "Creando secretos..."
	./scripts/create_cloud_secrets.sh
else
	echo "Secretos ya existentes en namespace plc."
fi

# Despliegues
echo "Verificando estado de los despliegues..."

# Elastic Operator
if ! kubectl get statefulset -n plc elastic-operator >/dev/null 2>&1; then
	echo "Desplegando Elastic Operator..."
	kustomize build k8s/cloud_deps/base/elastic/operator | kubectl apply -f -
else
	echo "Elastic Operator ya está desplegado."
fi

# Cloud Dependencies
if ! kubectl get statefulset -n plc pl-nats >/dev/null 2>&1; then
	echo "Desplegando dependencias públicas (NATS/Elastic)..."
	kustomize build k8s/cloud_deps/public | kubectl apply -f -
else
	echo "Dependencias de Cloud ya están desplegadas."
fi

# Pixie Cloud
if ! kubectl get deployment -n plc cloud-proxy >/dev/null 2>&1; then
	echo "Desplegando Pixie Cloud..."
	kustomize build k8s/cloud/public/ | kubectl apply -f -
else
	echo "Pixie Cloud ya está desplegado."
fi

echo ""
echo "========================================"
echo " Configuración de Cloud completada."
echo " Siguientes pasos (en terminales separadas):"
echo " 1. sudo minikube tunnel"
echo " 2. ./3.dns.sh"
echo "========================================"
