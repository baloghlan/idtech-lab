#!/usr/bin/env bash

configure_management_node() {
    local remote_script="/root/configure-management.sh"

    log "Configuring kubectl on '$DEPLOYMENT_NODE'"

    incus file push \
        "$REMOTE_SCRIPTS_DIR/configure-management.sh" \
        "$DEPLOYMENT_NODE$remote_script"

    incus exec "$DEPLOYMENT_NODE" -- chmod 700 "$remote_script"
    incus exec "$DEPLOYMENT_NODE" -- "$remote_script" "$CONTROL_IP"
}
