export PX_CLOUD_ADDR=dev.withpixie.dev

if kubectl get pods -n pl --no-headers 2>/dev/null | grep -q "Running"; then
	echo "Pixie ya está desplegado y operativo. Saltando instalación."
else
	echo "Iniciando despliegue de Pixie..."

	px auth login --manual

	px deploy --dev_cloud_namespace plc \
		--deploy_olm=false \
		--pem_memory_limit=2Gi \
		--check=false
fi
