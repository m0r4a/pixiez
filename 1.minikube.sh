minikube start \
	--driver=kvm2 \
	--cpus=4 \
	--memory=8192 \
	--disk-size=40g \
	--kubernetes-version=stable \
	--addons=ingress \
	--addons=metrics-server \
	--extra-config=kubelet.cgroup-driver=systemd
