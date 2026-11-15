#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

# shellcheck source=scripts/lib/common.sh
source "$PROJECT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/steps/01-provision-vms.sh
source "$PROJECT_DIR/scripts/steps/01-provision-vms.sh"
# shellcheck source=scripts/steps/02-configure-ssh.sh
source "$PROJECT_DIR/scripts/steps/02-configure-ssh.sh"
# shellcheck source=scripts/steps/03-install-kubespray.sh
source "$PROJECT_DIR/scripts/steps/03-install-kubespray.sh"
# shellcheck source=scripts/steps/04-deploy-kubernetes.sh
source "$PROJECT_DIR/scripts/steps/04-deploy-kubernetes.sh"
# shellcheck source=scripts/steps/05-configure-management.sh
source "$PROJECT_DIR/scripts/steps/05-configure-management.sh"
# shellcheck source=scripts/steps/06-install-argocd.sh
source "$PROJECT_DIR/scripts/steps/06-install-argocd.sh"

on_error() {
    local exit_code="$?"
    local line_number="$1"

    printf '[ERROR] Environment setup failed at line %s (exit code %s).\n' \
        "$line_number" "$exit_code" >&2
    exit "$exit_code"
}

trap 'on_error "$LINENO"' ERR

main() {
    log "Starting the IDTECH Argo CD lab environment setup"

    check_host_requirements
    provision_vms
    configure_ssh
    install_kubespray
    deploy_kubernetes
    configure_management_node
    install_argocd
    print_setup_summary
}

main "$@"
