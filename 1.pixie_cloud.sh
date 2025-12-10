#!/bin/bash

source "$(dirname "$0")/utils.sh"

if ! validate_commands "${REQUIRED_TOOLS[@]}"; then
	echo "Faltan dependencias"
	exit 1
fi

echo "Iniciando ejecución principal..."
echo ""

if [ ! -d ./pixie ]; then
	echo "Clonando el repositorio"
	git clone https://github.com/pixie-io/pixie.git
else
	echo "Repositorio ya clonado"
fi

cd ./pixie || exit 1
git checkout . >/dev/null 2>&1

echo ""
echo "Exportando variables..."
export LATEST_CLOUD_RELEASE=$(git tag | perl -ne 'print $1 if /release\/cloud\/v([^\-]*)$/' | sort -t '.' -k1,1nr -k2,2nr -k3,3nr | head -n 1)

echo ""
git checkout "release/cloud/v${LATEST_CLOUD_RELEASE}"
perl -pi -e "s|newTag: latest|newTag: \"${LATEST_CLOUD_RELEASE}\"|g" k8s/cloud/public/kustomization.yaml

echo "Creando el certificado"
mkcert -install >/dev/null 2>&1

echo "Creando el namespace"
kubectl get namespace plc >/dev/null 2>&1 || kubectl create namespace plc

echo "Ejecutando ./scripts/create_cloud_secrets.sh"
if [ "$(kubectl get secrets -n plc --no-headers 2>/dev/null | wc -l)" -le 1 ]; then
	./scripts/create_cloud_secrets.sh
else
	echo "Secretos ya existentes en el namespace plc"
fi

echo "Deployeando pixie cloud"
kustomize build k8s/cloud_deps/base/elastic/operator | kubectl apply -f -
kustomize build k8s/cloud_deps/public | kubectl apply -f -
kustomize build k8s/cloud/public/ | kubectl apply -f -

echo 'Ahora ejecuta "minikube tunnel" y el script "2.dns" en una terminal aparte'
