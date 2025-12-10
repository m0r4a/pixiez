minikube start \
	--driver=kvm2 \
	--cpus=4 \
	--memory=8192 \
	--disk-size=20g \
	--kubernetes-version=stable \
	--addons=ingress \
	--addons=metrics-server
