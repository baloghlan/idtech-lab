#!/usr/bin/env bash

install_kubespray() {
    local remote_script="/root/install-kubespray.sh"

    log "Installing Kubespray $KUBESPRAY_VERSION on '$DEPLOYMENT_NODE'"

    incus file push \
        "$REMOTE_SCRIPTS_DIR/install-kubespray.sh" \
        "$DEPLOYMENT_NODE$remote_script"

    incus exec "$DEPLOYMENT_NODE" -- chmod 700 "$remote_script"
    incus exec "$DEPLOYMENT_NODE" -- \
        "$remote_script" "$KUBESPRAY_VERSION" "$KUBESPRAY_DIR" "$KUBESPRAY_VENV"
}
