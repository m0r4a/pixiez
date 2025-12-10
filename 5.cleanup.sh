#!/bin/bash

echo "Deteniendo procesos en segundo plano"
pkill -f "minikube tunnel" >/dev/null 2>&1
pkill -f "dev_dns_updater" >/dev/null 2>&1

echo "Destruyendo cluster y configuraciones de Minikube..."
minikube stop >/dev/null 2>&1
minikube delete --all --purge >/dev/null 2>&1
