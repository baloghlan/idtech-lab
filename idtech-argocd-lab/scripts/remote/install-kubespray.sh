#!/usr/bin/env bash

set -Eeuo pipefail

KUBESPRAY_VERSION="${1:?Kubespray version is required}"
KUBESPRAY_DIR="${2:?Kubespray directory is required}"
VENV_DIR="${3:?Virtual environment directory is required}"

if [[ "$(id -u)" -ne 0 ]]; then
    printf '[ERROR] This script must run as root.\n' >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    libffi-dev \
    libssl-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    rsync \
    sshpass

if [[ ! -d "$KUBESPRAY_DIR/.git" ]]; then
    git clone \
        --branch "$KUBESPRAY_VERSION" \
        --depth 1 \
        https://github.com/kubernetes-sigs/kubespray.git \
        "$KUBESPRAY_DIR"
else
    current_version="$(
        git -C "$KUBESPRAY_DIR" describe --tags --exact-match 2>/dev/null ||
            true
    )"

    if [[ "$current_version" != "$KUBESPRAY_VERSION" ]]; then
        printf '[ERROR] Expected Kubespray %s, found %s.\n' \
            "$KUBESPRAY_VERSION" "${current_version:-unknown}" >&2
        exit 1
    fi
fi

python3 -m venv "$VENV_DIR"

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip setuptools wheel
python -m pip install --requirement "$KUBESPRAY_DIR/requirements.txt"

python --version
ansible --version
git -C "$KUBESPRAY_DIR" describe --tags --exact-match
