#!/usr/bin/env bash

set -Eeuo pipefail

CONTROL_IP="${1:?Control-plane IP address is required}"

scp "root@$CONTROL_IP:/usr/local/bin/kubectl" /usr/local/bin/kubectl
chmod 755 /usr/local/bin/kubectl

install -d -m 700 /root/.kube
scp "root@$CONTROL_IP:/etc/kubernetes/admin.conf" /root/.kube/config
chmod 600 /root/.kube/config

sed -i \
    "s#server: .*#server: https://$CONTROL_IP:6443#" \
    /root/.kube/config

kubectl cluster-info
kubectl get nodes -o wide
