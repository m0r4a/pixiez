minikube start \
	--driver=docker \
	--cpus=4 \
	--memory=8192 \
	--disk-size=40g \
	--kubernetes-version=stable \
	--addons=ingress \
	--addons=metrics-server
