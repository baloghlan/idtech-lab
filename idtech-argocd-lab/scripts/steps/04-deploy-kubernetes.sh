#!/usr/bin/env bash

deploy_kubernetes() {
    local max_attempts="3"

    log "Preparing the Kubespray inventory on '$DEPLOYMENT_NODE'"

    incus exec "$DEPLOYMENT_NODE" -- bash -c "
        set -Eeuo pipefail

        if [[ ! -d '$REMOTE_INVENTORY_DIR' ]]; then
            cp -rfp \
                '$KUBESPRAY_DIR/inventory/sample' \
                '$REMOTE_INVENTORY_DIR'
        fi
    "

    incus file push \
        "$INVENTORY_FILE" \
        "$DEPLOYMENT_NODE$REMOTE_INVENTORY_FILE"

    incus exec "$DEPLOYMENT_NODE" -- chmod 600 "$REMOTE_INVENTORY_FILE"

    if kubernetes_cluster_is_ready; then
        log "Kubernetes cluster is already ready; skipping Kubespray deployment"
        return
    fi

    log "Validating Ansible connectivity"

    incus exec "$DEPLOYMENT_NODE" -- bash -lc "
        set -Eeuo pipefail
        source '$KUBESPRAY_VENV/bin/activate'
        cd '$KUBESPRAY_DIR'

        ansible-inventory -i '$REMOTE_INVENTORY_FILE' --graph
        ansible -i '$REMOTE_INVENTORY_FILE' all -m ping
    "

    log "Deploying Kubernetes with Kubespray"

    incus exec "$DEPLOYMENT_NODE" -- bash -lc "
        set -Eeuo pipefail
        source '$KUBESPRAY_VENV/bin/activate'
        cd '$KUBESPRAY_DIR'

        : > /root/kubespray-cluster.log

        for attempt in \$(seq 1 '$max_attempts'); do
            printf '[INFO] Kubespray deployment attempt %s/%s\n' \
                \"\$attempt\" '$max_attempts' |
                tee -a /root/kubespray-cluster.log

            if ansible-playbook \
                -i '$REMOTE_INVENTORY_FILE' \
                --become \
                --extra-vars 'download_retries=10' \
                --extra-vars 'unsafe_show_logs=true' \
                cluster.yml \
                2>&1 | tee -a /root/kubespray-cluster.log; then
                exit 0
            fi

            if [[ \"\$attempt\" -eq '$max_attempts' ]]; then
                printf '[ERROR] Kubespray failed after %s attempts.\n' \
                    '$max_attempts' |
                    tee -a /root/kubespray-cluster.log >&2
                exit 1
            fi

            printf '[WARN] Kubespray failed; retrying in 15 seconds.\n' |
                tee -a /root/kubespray-cluster.log
            sleep 15
        done
    "
}

kubernetes_cluster_is_ready() {
    incus exec "$DEPLOYMENT_NODE" -- bash -lc "
        set -Eeuo pipefail

        command -v kubectl >/dev/null 2>&1
        [[ -f /root/.kube/config ]]

        [[ \"\$(
            kubectl get node '$CONTROL_NODE' \
                --output jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'
        )\" == 'True' ]]

        [[ \"\$(
            kubectl get node '$WORKER_NODE' \
                --output jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'
        )\" == 'True' ]]
    " >/dev/null 2>&1
}
