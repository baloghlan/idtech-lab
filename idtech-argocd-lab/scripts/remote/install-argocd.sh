#!/usr/bin/env bash

set -Eeuo pipefail

ARGOCD_VERSION="${1:?Argo CD version is required}"
ARGOCD_NAMESPACE="${2:?Argo CD namespace is required}"
INSTALL_DIR="/opt/argocd"
MANIFEST_FILE="$INSTALL_DIR/install.yaml"
TEMPORARY_MANIFEST="$(mktemp)"
TEMPORARY_CLI="$(mktemp)"

cleanup() {
    rm -f "$TEMPORARY_MANIFEST" "$TEMPORARY_CLI"
}

trap cleanup EXIT

case "$(uname -m)" in
    x86_64)
        cli_arch="amd64"
        ;;
    aarch64 | arm64)
        cli_arch="arm64"
        ;;
    *)
        printf '[ERROR] Unsupported architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

install -d -m 755 "$INSTALL_DIR"

curl \
    --http1.1 \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 5 \
    --retry-all-errors \
    --connect-timeout 15 \
    --max-time 180 \
    --speed-limit 1024 \
    --speed-time 30 \
    "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml" \
    --output "$TEMPORARY_MANIFEST"

grep -q 'name: applicationsets.argoproj.io' "$TEMPORARY_MANIFEST"
grep -q 'name: argocd-server-network-policy' "$TEMPORARY_MANIFEST"

install -m 644 "$TEMPORARY_MANIFEST" "$MANIFEST_FILE"

kubectl create namespace "$ARGOCD_NAMESPACE" \
    --dry-run=client \
    --output yaml |
    kubectl apply -f -

kubectl apply \
    --server-side \
    --force-conflicts \
    --namespace "$ARGOCD_NAMESPACE" \
    --filename "$MANIFEST_FILE"

curl \
    --http1.1 \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 5 \
    --retry-all-errors \
    --connect-timeout 15 \
    --max-time 600 \
    --speed-limit 1024 \
    --speed-time 60 \
    "https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-$cli_arch" \
    --output "$TEMPORARY_CLI"

[[ -s "$TEMPORARY_CLI" ]]
install -m 755 "$TEMPORARY_CLI" /usr/local/bin/argocd

kubectl wait \
    --for=condition=Available \
    deployment \
    --all \
    --namespace "$ARGOCD_NAMESPACE" \
    --timeout 600s

kubectl rollout status \
    statefulset/argocd-application-controller \
    --namespace "$ARGOCD_NAMESPACE" \
    --timeout 600s

kubectl get secret argocd-initial-admin-secret \
    --namespace "$ARGOCD_NAMESPACE" \
    >/dev/null

argocd version --client
kubectl get pods --namespace "$ARGOCD_NAMESPACE" -o wide
