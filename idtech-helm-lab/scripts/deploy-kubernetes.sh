#!/usr/bin/env bash

set -Eeuo pipefail

DEPLOYMENT_NODE="helm-lab"
KUBESPRAY_DIR="/opt/kubespray"
VENV_DIR="/opt/kubespray-venv"
REMOTE_INVENTORY_DIR="$KUBESPRAY_DIR/inventory/helm-cluster"
REMOTE_INVENTORY_FILE="$REMOTE_INVENTORY_DIR/inventory.ini"
REMOTE_LOG_FILE="/root/kubespray-cluster.log"

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
LOCAL_INVENTORY_FILE="$PROJECT_DIR/kubespray/inventory.ini"

log() {
    printf '[INFO] %s\n' "$1"
}

error() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

check_requirements() {
    command -v incus >/dev/null 2>&1 ||
        error "Incus is not installed."

    incus info >/dev/null 2>&1 ||
        error "Cannot connect to the Incus daemon."

    [[ -f "$LOCAL_INVENTORY_FILE" ]] ||
        error "Inventory file not found: $LOCAL_INVENTORY_FILE"

    local status
    status="$(incus list "$DEPLOYMENT_NODE" --format csv -c s)"

    [[ "$status" == "RUNNING" ]] ||
        error "VM '$DEPLOYMENT_NODE' is not running."
}

check_kubespray_installation() {
    incus exec "$DEPLOYMENT_NODE" -- \
        test -f "$KUBESPRAY_DIR/cluster.yml" ||
        error "Kubespray is not installed in $KUBESPRAY_DIR."

    incus exec "$DEPLOYMENT_NODE" -- \
        test -x "$VENV_DIR/bin/ansible-playbook" ||
        error "Kubespray virtual environment is not available in $VENV_DIR."
}

prepare_remote_inventory() {
    log "Preparing Kubespray inventory on $DEPLOYMENT_NODE"

    incus exec "$DEPLOYMENT_NODE" -- bash -c "
        set -Eeuo pipefail

        if [[ ! -d '$REMOTE_INVENTORY_DIR' ]]; then
            cp -rfp \
                '$KUBESPRAY_DIR/inventory/sample' \
                '$REMOTE_INVENTORY_DIR'
        fi
    "

    log "Copying repository inventory to $DEPLOYMENT_NODE"

    incus file push \
        "$LOCAL_INVENTORY_FILE" \
        "$DEPLOYMENT_NODE$REMOTE_INVENTORY_FILE"

    incus exec "$DEPLOYMENT_NODE" -- \
        chmod 600 "$REMOTE_INVENTORY_FILE"
}

verify_inventory() {
    log "Validating inventory and Ansible connectivity"

    incus exec "$DEPLOYMENT_NODE" -- bash -lc "
        set -Eeuo pipefail
        source '$VENV_DIR/bin/activate'
        cd '$KUBESPRAY_DIR'

        ansible-inventory \
            -i '$REMOTE_INVENTORY_FILE' \
            --graph

        ansible \
            -i '$REMOTE_INVENTORY_FILE' \
            all \
            -m ping
    "
}

deploy_cluster() {
    log "Running Kubespray cluster.yml on $DEPLOYMENT_NODE"
    log "Deployment log: $DEPLOYMENT_NODE:$REMOTE_LOG_FILE"

    incus exec "$DEPLOYMENT_NODE" -- bash -lc "
        set -Eeuo pipefail
        source '$VENV_DIR/bin/activate'
        cd '$KUBESPRAY_DIR'

        ansible-playbook \
            -i '$REMOTE_INVENTORY_FILE' \
            --become \
            cluster.yml \
            2>&1 | tee '$REMOTE_LOG_FILE'
    "
}

main() {
    check_requirements
    check_kubespray_installation
    prepare_remote_inventory
    verify_inventory
    deploy_cluster

    log "Kubernetes deployment completed successfully."
}

main "$@"
