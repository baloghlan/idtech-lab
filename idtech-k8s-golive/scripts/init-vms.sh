
#!/usr/bin/env bash
set -Eeuo pipefail

# IDTECH Kubernetes Midterm Lab
# Infrastructure: Incus + Ubuntu 22.04
# Cluster: 1 control-plane + 2 workers

IMAGE="images:ubuntu/22.04"
NETWORK="incusbr0"

VM_NAMES=("master" "worker1" "worker2")
VM_CPUS=("2" "2" "3")
VM_MEMORY=("3GiB" "3GiB" "5GiB")
VM_DISKS=("25GiB" "20GiB" "30GiB")
VM_IPS=("192.168.56.10" "192.168.56.11" "192.168.56.12")

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
        error "Cannot connect to Incus daemon."

    [[ -e /dev/kvm ]] ||
        error "KVM is not available."

    incus network show "$NETWORK" >/dev/null 2>&1 ||
        error "Network $NETWORK does not exist."

    incus storage show default >/dev/null 2>&1 ||
        error "Storage pool 'default' does not exist."
}

create_vm() {
    local name="$1"
    local cpu="$2"
    local memory="$3"
    local disk="$4"
    local ip="$5"

    if incus info "$name" >/dev/null 2>&1; then
        log "VM $name already exists. Skipping creation."
    else
        log "Creating VM: $name"
        incus init "$IMAGE" "$name" --vm
    fi

    log "Configuring resources for $name"

    incus config set "$name" \
        "limits.cpu=$cpu" \
        "limits.memory=$memory"

    # Override inherited profile devices only once.
    if ! incus config device show "$name" |
        grep -q '^root:'; then
        incus config device override "$name" root \
            "size=$disk"
    else
        incus config device set "$name" root \
            "size=$disk"
    fi

    if ! incus config device show "$name" |
        grep -q '^eth0:'; then
        incus config device override "$name" eth0 \
            "network=$NETWORK" \
            "ipv4.address=$ip"
    else
        incus config device set "$name" eth0 \
            "network=$NETWORK" \
            "ipv4.address=$ip"
    fi

    local status
    status=$(incus list "$name" --format csv -c s)

    if [[ "$status" == "RUNNING" ]]; then
        log "VM $name is already running."
    else
        log "Starting VM: $name"
        incus start "$name"
    fi
}

main() {
    log "Starting IDTECH Kubernetes VM provisioning"

    check_requirements

    for i in "${!VM_NAMES[@]}"; do
        create_vm \
            "${VM_NAMES[$i]}" \
            "${VM_CPUS[$i]}" \
            "${VM_MEMORY[$i]}" \
            "${VM_DISKS[$i]}" \
            "${VM_IPS[$i]}"
    done

    log "VM provisioning completed."
    incus list
}

main "$@"
