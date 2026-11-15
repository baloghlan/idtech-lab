#!/usr/bin/env bash

readonly IMAGE="images:ubuntu/22.04"
readonly NETWORK="incusbr0"
readonly STORAGE_POOL="default"

readonly DEPLOYMENT_NODE="argocd-lab"
readonly CONTROL_NODE="argocd-control01"
readonly WORKER_NODE="argocd-worker01"

readonly DEPLOYMENT_IP="192.168.56.42"
readonly CONTROL_IP="192.168.56.43"
readonly WORKER_IP="192.168.56.44"

readonly KUBESPRAY_VERSION="v2.28.1"
readonly KUBESPRAY_DIR="/opt/kubespray"
readonly KUBESPRAY_VENV="/opt/kubespray-venv"
readonly REMOTE_INVENTORY_DIR="$KUBESPRAY_DIR/inventory/argocd-cluster"
readonly REMOTE_INVENTORY_FILE="$REMOTE_INVENTORY_DIR/inventory.ini"

readonly ARGOCD_VERSION="v3.6.1"
readonly ARGOCD_NAMESPACE="argocd"

readonly INVENTORY_FILE="$PROJECT_DIR/kubespray/inventory.ini"
readonly REMOTE_SCRIPTS_DIR="$PROJECT_DIR/scripts/remote"

log() {
    printf '[INFO] %s\n' "$1"
}

error() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

instance_status() {
    incus list "$1" --format csv -c s
}

check_host_requirements() {
    command -v incus >/dev/null 2>&1 ||
        error "Incus is not installed."

    incus info >/dev/null 2>&1 ||
        error "Cannot connect to the Incus daemon."

    [[ -e /dev/kvm ]] ||
        error "KVM is not available at /dev/kvm."

    incus network show "$NETWORK" >/dev/null 2>&1 ||
        error "Incus network '$NETWORK' does not exist."

    incus storage show "$STORAGE_POOL" >/dev/null 2>&1 ||
        error "Incus storage pool '$STORAGE_POOL' does not exist."

    [[ -f "$INVENTORY_FILE" ]] ||
        error "Kubespray inventory not found: $INVENTORY_FILE"
}

print_setup_summary() {
    printf '\n'
    log "IDTECH Argo CD lab environment is ready."

    incus list

    printf '\nKubernetes nodes:\n'
    incus exec "$DEPLOYMENT_NODE" -- kubectl get nodes -o wide

    printf '\nArgo CD workloads:\n'
    incus exec "$DEPLOYMENT_NODE" -- \
        kubectl get pods -n "$ARGOCD_NAMESPACE" -o wide

    cat <<SUMMARY

Argo CD admin password:
  incus exec $DEPLOYMENT_NODE -- bash -lc \
    "kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NAMESPACE -o jsonpath='{.data.password}' | base64 --decode; echo"

Start the Argo CD UI port-forward in a separate terminal:
  incus exec $DEPLOYMENT_NODE -- kubectl port-forward \
    --address 0.0.0.0 -n $ARGOCD_NAMESPACE svc/argocd-server 8080:443

Open the UI:
  https://$DEPLOYMENT_IP:8080

Username:
  admin
SUMMARY
}
