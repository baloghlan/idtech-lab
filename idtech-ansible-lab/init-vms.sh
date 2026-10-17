#!/usr/bin/env bash

set -euo pipefail

IMAGE="images:ubuntu/jammy"
NETWORK="incusbr0"
CPU="2"
MEMORY="2GiB"
DISK="10GiB"

declare -A VMS=(
    [control01]="192.168.56.11"
    [app01]="192.168.56.12"
)

if ! command -v incus &>/dev/null; then
    echo "ERROR: Incus is not installed."
    exit 1
fi

if ! incus network show "$NETWORK" &>/dev/null; then
    echo "ERROR: Network $NETWORK not found."
    exit 1
fi

create_vm() {
    local name="$1"
    local ip="$2"

    echo "================================="
    echo "Configuring VM: $name"
    echo "IP: $ip"
    echo "================================="

    if incus info "$name" &>/dev/null; then
        echo "VM $name already exists. Skipping."
        return
    fi

    incus init "$IMAGE" "$name" --vm \
        -c limits.cpu="$CPU" \
        -c limits.memory="$MEMORY"

    incus config device override "$name" root \
        size="$DISK"

    incus config device add "$name" eth0 nic \
        network="$NETWORK" \
        name=eth0 \
        ipv4.address="$ip"

    incus start "$name"

    echo "VM $name started."
}

create_vm control01 "${VMS[control01]}"
create_vm app01 "${VMS[app01]}"

echo
echo "========== VM STATUS =========="
incus list