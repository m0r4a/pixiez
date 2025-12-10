export PX_CLOUD_ADDR=dev.withpixie.dev
px auth login --manual

px deploy --dev_cloud_namespace plc \
	--deploy_olm=false \
	--pem_memory_limit=2Gi \
	--check=false
