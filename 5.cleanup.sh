#!/bin/bash

echo "Deteniendo procesos en segundo plano"
pkill -f "minikube tunnel" >/dev/null 2>&1
pkill -f "dev_dns_updater" >/dev/null 2>&1

echo "Destruyendo cluster y configuraciones de Minikube..."
minikube stop >/dev/null 2>&1
minikube delete --all --purge >/dev/null 2>&1

echo ""
echo "Iniciando nuevo cluster"

minikube start \
	--driver=docker \
	--cpus=4 \
	--memory=8192 \
	--disk-size=40g \
	--kubernetes-version=stable \
	--addons=ingress \
	--addons=metrics-server

echo ""
echo "Cluster listo y limpio."
