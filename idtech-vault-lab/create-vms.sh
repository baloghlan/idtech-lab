#!/usr/bin/env bash

set -euo pipefail

IMAGE="images:ubuntu/jammy"

declare -A NODES=(
  ["vault-1"]="192.168.56.11"
  ["vault-2"]="192.168.56.12"
  ["vault-3"]="192.168.56.13"
)

echo "Creating Vault lab nodes..."

for NODE in vault-1 vault-2 vault-3; do
    IP="${NODES[$NODE]}"

    echo "========================================"
    echo "Creating $NODE ($IP)"
    echo "========================================"

    # Create Ubuntu 22.04 VM
    incus init "$IMAGE" "$NODE" --vm

    # Resources
    incus config set "$NODE" limits.cpu=2
    incus config set "$NODE" limits.memory=2GiB

    # Root disk
    incus config device override "$NODE" root size=10GiB

    # Static IPv4 assignment on the Incus managed network.
    # The guest still uses DHCP, but Incus always leases this IP
    # to this VM.
    incus config device override "$NODE" eth0 \
        ipv4.address="$IP"

    echo "$NODE created."
done

echo
echo "Starting Vault nodes..."

for NODE in vault-1 vault-2 vault-3; do
    incus start "$NODE"
done

echo
echo "Waiting for instances..."
sleep 10

incus list