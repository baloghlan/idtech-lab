#!/usr/bin/env bash

install_argocd() {
    local remote_script="/root/install-argocd.sh"

    log "Installing Argo CD $ARGOCD_VERSION"

    incus file push \
        "$REMOTE_SCRIPTS_DIR/install-argocd.sh" \
        "$DEPLOYMENT_NODE$remote_script"

    incus exec "$DEPLOYMENT_NODE" -- chmod 700 "$remote_script"
    incus exec "$DEPLOYMENT_NODE" -- \
        "$remote_script" "$ARGOCD_VERSION" "$ARGOCD_NAMESPACE"
}
