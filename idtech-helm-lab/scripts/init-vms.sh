#!/usr/bin/env bash

set -Eeuo pipefail

IMAGE="images:ubuntu/22.04"
NETWORK="incusbr0"

VM_NAMES=(
    "helm-lab"
    "helm-control01"
    "helm-worker01"
)

VM_CPUS=(
    "2"
    "2"
    "2"
)

VM_MEMORY=(
    "2GiB"
    "3GiB"
    "6GiB"
)

VM_DISKS=(
    "25GiB"
    "30GiB"
    "40GiB"
)

VM_IPS=(
    "192.168.56.42"
    "192.168.56.43"
    "192.168.56.44"
)

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

    incus storage show default >/dev/null 2>&1 ||
        error "Incus storage pool 'default' does not exist."
}

configure_root_disk() {
    local name="$1"
    local disk_size="$2"

    if incus config device show "$name" | grep -q '^root:'; then
        incus config device set "$name" root "size=$disk_size"
    else
        incus config device override "$name" root "size=$disk_size"
    fi
}

configure_network() {
    local name="$1"
    local ip_address="$2"

    if incus config device show "$name" | grep -q '^eth0:'; then
        incus config device set "$name" eth0 \
            "ipv4.address=$ip_address"
    else
        incus config device override "$name" eth0 \
            "network=$NETWORK" \
            "ipv4.address=$ip_address"
    fi
}

create_vm() {
    local name="$1"
    local cpu_count="$2"
    local memory_size="$3"
    local disk_size="$4"
    local ip_address="$5"

    if incus info "$name" >/dev/null 2>&1; then
        log "VM '$name' already exists. Skipping creation."
    else
        log "Creating VM '$name'"
        incus init "$IMAGE" "$name" --vm
    fi

    log "Configuring resources for '$name'"

    incus config set "$name" \
        "limits.cpu=$cpu_count" \
        "limits.memory=$memory_size"

    configure_root_disk "$name" "$disk_size"
    configure_network "$name" "$ip_address"
}

start_vm() {
    local name="$1"
    local status

    status="$(incus list "$name" --format csv -c s)"

    if [[ "$status" == "RUNNING" ]]; then
        log "VM '$name' is already running."
    else
        log "Starting VM '$name'"
        incus start "$name"
    fi
}

wait_for_vm() {
    local name="$1"

    log "Waiting for VM agent on '$name'"

    for _ in {1..60}; do
        if incus exec "$name" -- true >/dev/null 2>&1; then
            log "VM agent on '$name' is ready."
            return
        fi

        sleep 2
    done

    error "VM agent on '$name' did not become ready."
}

main() {
    check_requirements

    for index in "${!VM_NAMES[@]}"; do
        create_vm \
            "${VM_NAMES[$index]}" \
            "${VM_CPUS[$index]}" \
            "${VM_MEMORY[$index]}" \
            "${VM_DISKS[$index]}" \
            "${VM_IPS[$index]}"
    done

    for name in "${VM_NAMES[@]}"; do
        start_vm "$name"
    done

    for name in "${VM_NAMES[@]}"; do
        wait_for_vm "$name"
    done

    log "All Kubespray lab VMs are ready."

    incus list \
        helm-lab \
        helm-control01 \
        helm-worker01 \
        helm-worker02
}

main "$@"