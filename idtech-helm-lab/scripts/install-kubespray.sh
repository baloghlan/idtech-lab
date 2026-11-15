#!/usr/bin/env bash

set -Eeuo pipefail

KUBESPRAY_VERSION="v2.28.1"
KUBESPRAY_DIR="/opt/kubespray"
VENV_DIR="/opt/kubespray-venv"

log() {
    printf '[INFO] %s\n' "$1"
}

if [[ "$(id -u)" -ne 0 ]]; then
    printf '[ERROR] This script must be run as root.\n' >&2
    exit 1
fi

log "Installing system dependencies"

apt-get update

apt-get install -y \
    git \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    libffi-dev \
    libssl-dev \
    rsync \
    sshpass \
    ca-certificates \
    curl

if [[ ! -d "$KUBESPRAY_DIR/.git" ]]; then
    log "Cloning Kubespray $KUBESPRAY_VERSION"

    git clone \
        --branch "$KUBESPRAY_VERSION" \
        --depth 1 \
        https://github.com/kubernetes-sigs/kubespray.git \
        "$KUBESPRAY_DIR"
else
    log "Kubespray repository already exists"

    current_version="$(
        git -C "$KUBESPRAY_DIR" describe --tags --exact-match 2>/dev/null ||
            true
    )"

    if [[ "$current_version" != "$KUBESPRAY_VERSION" ]]; then
        printf '[ERROR] Expected Kubespray %s, found %s.\n' \
            "$KUBESPRAY_VERSION" \
            "${current_version:-unknown}" >&2
        exit 1
    fi
fi

log "Creating Python virtual environment"

python3 -m venv "$VENV_DIR"

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

log "Updating pip"

python -m pip install --upgrade pip setuptools wheel

log "Installing Kubespray Python requirements"

python -m pip install \
    --requirement "$KUBESPRAY_DIR/requirements.txt"

log "Verifying installation"

printf '\n'
python --version
ansible --version
ansible-playbook --version
printf '\nKubespray version: '
git -C "$KUBESPRAY_DIR" describe --tags --exact-match

log "Kubespray installation completed."