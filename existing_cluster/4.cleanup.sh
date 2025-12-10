#!/bin/bash

echo "Deteniendo procesos en segundo plano"
pkill -f "dev_dns_updater" >/dev/null 2>&1
