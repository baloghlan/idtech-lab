#!/usr/bin/env bash

set -Eeuo pipefail

readonly IMAGE="images:ubuntu/22.04"
readonly NETWORK="incusbr0"
readonly STORAGE_POOL="default"

readonly VM_NAME="elk-lab"
readonly VM_CPU="4"
readonly VM_MEMORY="8GiB"
readonly VM_DISK="40GiB"
readonly VM_IP="192.168.56.50"

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

    [[ -e /dev/kvm ]] ||
        error "KVM is not available."

    incus network show "$NETWORK" >/dev/null 2>&1 ||
        error "Incus network '$NETWORK' does not exist."

    incus storage show "$STORAGE_POOL" >/dev/null 2>&1 ||
        error "Incus storage pool '$STORAGE_POOL' does not exist."
}

configure_root_disk() {
    if incus config device show "$VM_NAME" | grep -q '^root:'; then
        incus config device set "$VM_NAME" root "size=$VM_DISK"
    else
        incus config device override "$VM_NAME" root \
            "pool=$STORAGE_POOL" \
            "size=$VM_DISK"
    fi
}

configure_network() {
    if incus config device show "$VM_NAME" | grep -q '^eth0:'; then
        incus config device set "$VM_NAME" eth0 \
            "network=$NETWORK" \
            "ipv4.address=$VM_IP"
    else
        incus config device override "$VM_NAME" eth0 \
            "network=$NETWORK" \
            "ipv4.address=$VM_IP"
    fi
}

create_vm() {
    if incus info "$VM_NAME" >/dev/null 2>&1; then
        log "VM '$VM_NAME' already exists. Skipping creation."
    else
        log "Creating VM '$VM_NAME'."
        incus init "$IMAGE" "$VM_NAME" --vm
    fi

    log "Configuring VM resources."

    incus config set "$VM_NAME" \
        "limits.cpu=$VM_CPU" \
        "limits.memory=$VM_MEMORY"

    configure_root_disk
    configure_network
}

start_vm() {
    local status

    status="$(incus list "$VM_NAME" --format csv -c s)"

    if [[ "$status" == "RUNNING" ]]; then
        log "VM '$VM_NAME' is already running."
    else
        log "Starting VM '$VM_NAME'."
        incus start "$VM_NAME"
    fi
}

wait_for_vm() {
    log "Waiting for the VM agent."

    for _ in {1..60}; do
        if incus exec "$VM_NAME" -- true >/dev/null 2>&1; then
            log "VM '$VM_NAME' is ready."
            return
        fi

        sleep 2
    done

    error "VM agent did not become ready in time."
}

main() {
    check_requirements
    create_vm
    start_vm
    wait_for_vm

    log "ELK lab VM provisioning completed."
    log "VM IP address: $VM_IP"

    incus list "$VM_NAME"
}

main "$@"