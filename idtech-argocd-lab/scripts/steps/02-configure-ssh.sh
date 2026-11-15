#!/usr/bin/env bash

configure_ssh() {
    local nodes=("$DEPLOYMENT_NODE" "$CONTROL_NODE" "$WORKER_NODE")
    local cluster_nodes=("$CONTROL_NODE" "$WORKER_NODE")
    local cluster_ips=("$CONTROL_IP" "$WORKER_IP")
    local temporary_key

    log "Installing SSH and Python prerequisites"

    for node in "${nodes[@]}"; do
        incus exec "$node" -- env DEBIAN_FRONTEND=noninteractive \
            apt-get update

        incus exec "$node" -- env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y \
                ca-certificates \
                curl \
                openssh-client \
                openssh-server \
                python3 \
                sudo

        incus exec "$node" -- systemctl enable --now ssh
    done

    log "Generating the Kubespray SSH key on '$DEPLOYMENT_NODE'"

    incus exec "$DEPLOYMENT_NODE" -- bash -c '
        set -Eeuo pipefail
        install -d -m 700 /root/.ssh

        if [[ ! -f /root/.ssh/id_ed25519 ]]; then
            ssh-keygen \
                -t ed25519 \
                -f /root/.ssh/id_ed25519 \
                -N "" \
                -C "kubespray@argocd-lab"
        fi
    '

    temporary_key="$(mktemp)"
    incus file pull \
        "$DEPLOYMENT_NODE/root/.ssh/id_ed25519.pub" \
        "$temporary_key"

    for node in "${cluster_nodes[@]}"; do
        log "Authorizing the deployment key on '$node'"

        incus exec "$node" -- install -d -m 700 /root/.ssh
        incus file push "$temporary_key" "$node/tmp/argocd-lab.pub"

        incus exec "$node" -- bash -c '
            set -Eeuo pipefail
            touch /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys

            public_key="$(cat /tmp/argocd-lab.pub)"
            grep -qxF "$public_key" /root/.ssh/authorized_keys ||
                printf "%s\n" "$public_key" >> /root/.ssh/authorized_keys

            rm -f /tmp/argocd-lab.pub
        '
    done

    rm -f "$temporary_key"

    log "Verifying passwordless SSH connectivity"

    for index in "${!cluster_ips[@]}"; do
        incus exec "$DEPLOYMENT_NODE" -- \
            ssh \
                -o BatchMode=yes \
                -o StrictHostKeyChecking=accept-new \
                "root@${cluster_ips[$index]}" \
                hostname
    done
}
