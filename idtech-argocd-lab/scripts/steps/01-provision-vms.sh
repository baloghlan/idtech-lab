#!/usr/bin/env bash

provision_vms() {
    local names=("$DEPLOYMENT_NODE" "$CONTROL_NODE" "$WORKER_NODE")
    local cpus=("2" "2" "4")
    local memory=("3GiB" "4GiB" "6GiB")
    local disks=("25GiB" "30GiB" "40GiB")
    local ips=("$DEPLOYMENT_IP" "$CONTROL_IP" "$WORKER_IP")

    log "Provisioning Incus virtual machines"

    for index in "${!names[@]}"; do
        provision_vm \
            "${names[$index]}" \
            "${cpus[$index]}" \
            "${memory[$index]}" \
            "${disks[$index]}" \
            "${ips[$index]}"
    done

    for name in "${names[@]}"; do
        start_vm "$name"
    done

    for name in "${names[@]}"; do
        wait_for_vm "$name"
    done
}

provision_vm() {
    local name="$1"
    local cpu_count="$2"
    local memory_size="$3"
    local disk_size="$4"
    local ip_address="$5"

    if incus info "$name" >/dev/null 2>&1; then
        log "VM '$name' already exists; reusing it"
    else
        log "Creating VM '$name'"
        incus init "$IMAGE" "$name" --vm
    fi

    incus config set "$name" \
        "limits.cpu=$cpu_count" \
        "limits.memory=$memory_size"

    if incus config device show "$name" | grep -q '^root:'; then
        incus config device set "$name" root "size=$disk_size"
    else
        incus config device override "$name" root "size=$disk_size"
    fi

    if incus config device show "$name" | grep -q '^eth0:'; then
        incus config device set "$name" eth0 "ipv4.address=$ip_address"
    else
        incus config device override "$name" eth0 \
            "network=$NETWORK" \
            "ipv4.address=$ip_address"
    fi
}

start_vm() {
    local name="$1"

    if [[ "$(instance_status "$name")" == "RUNNING" ]]; then
        log "VM '$name' is already running"
    else
        log "Starting VM '$name'"
        incus start "$name"
    fi
}

wait_for_vm() {
    local name="$1"

    log "Waiting for the Incus agent on '$name'"

    for _ in {1..90}; do
        if incus exec "$name" -- true >/dev/null 2>&1; then
            log "VM '$name' is ready"
            return
        fi

        sleep 2
    done

    error "Incus agent on '$name' did not become ready."
}
