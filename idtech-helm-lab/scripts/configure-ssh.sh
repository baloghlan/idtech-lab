#!/usr/bin/env bash

set -Eeuo pipefail

DEPLOYMENT_NODE="helm-lab"

CLUSTER_NODES=(
    "helm-control01"
    "helm-worker01"
)

CLUSTER_IPS=(
    "192.168.56.43"
    "192.168.56.44"
)

log() {
    printf '[INFO] %s\n' "$1"
}

check_instances() {
    for node in "$DEPLOYMENT_NODE" "${CLUSTER_NODES[@]}"; do
        status="$(incus list "$node" --format csv -c s)"

        if [[ "$status" != "RUNNING" ]]; then
            printf '[ERROR] VM %s is not running.\n' "$node" >&2
            exit 1
        fi
    done
}

prepare_cluster_nodes() {
    for node in "${CLUSTER_NODES[@]}"; do
        log "Installing SSH and Python on $node"

        incus exec "$node" -- apt-get update
        incus exec "$node" -- apt-get install -y \
            openssh-server \
            python3 \
            sudo

        incus exec "$node" -- systemctl enable --now ssh
        incus exec "$node" -- install -d -m 700 /root/.ssh
    done
}

generate_ssh_key() {
    log "Generating SSH key on $DEPLOYMENT_NODE"

    incus exec "$DEPLOYMENT_NODE" -- bash -c '
        if [[ ! -f /root/.ssh/id_ed25519 ]]; then
            install -d -m 700 /root/.ssh
            ssh-keygen \
                -t ed25519 \
                -f /root/.ssh/id_ed25519 \
                -N "" \
                -C "kubespray@helm-lab"
        fi
    '
}

copy_ssh_key() {
    local temporary_key

    temporary_key="$(mktemp)"
    trap 'rm -f "$temporary_key"' EXIT

    incus file pull \
        "$DEPLOYMENT_NODE/root/.ssh/id_ed25519.pub" \
        "$temporary_key"

    for node in "${CLUSTER_NODES[@]}"; do
        log "Copying SSH key to $node"

        incus file push \
            "$temporary_key" \
            "$node/root/.ssh/authorized_keys"

        incus exec "$node" -- chmod 600 /root/.ssh/authorized_keys
    done
}

verify_ssh_access() {
    for index in "${!CLUSTER_IPS[@]}"; do
        node="${CLUSTER_NODES[$index]}"
        ip="${CLUSTER_IPS[$index]}"

        log "Testing SSH access to $node ($ip)"

        incus exec "$DEPLOYMENT_NODE" -- \
            ssh \
                -o BatchMode=yes \
                -o StrictHostKeyChecking=accept-new \
                "root@$ip" \
                hostname
    done
}

main() {
    check_instances
    prepare_cluster_nodes
    generate_ssh_key
    copy_ssh_key
    verify_ssh_access

    log "Passwordless SSH configuration completed."
}

main "$@"