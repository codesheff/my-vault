#!/usr/bin/env bash
# port-forward.sh — forward Vault's port 8200 to localhost:8200.
# Use this on clusters where NodePort is not directly reachable from the host
# (e.g., kind, minikube with no node IP route).
#
# Usage:
#   ./scripts/port-forward.sh
#   ./scripts/port-forward.sh --kube-context docker-desktop
#
# After running, set:
#   export VAULT_ADDR=http://127.0.0.1:8200
set -euo pipefail

NAMESPACE=vault
SERVICE=vault
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DEFAULTS_FILE="${ROOT_DIR}/.vault/deploy.defaults"
KUBE_CONTEXT=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/port-forward.sh [--kube-context <context>]

Options:
  --kube-context <context>  Kubernetes context to use.

If --kube-context is omitted, the script will use the last successful context
saved by deploy.sh in .vault/deploy.defaults when available, otherwise the
current kubectl context.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kube-context)
      [[ $# -ge 2 ]] || { echo "--kube-context requires a value" >&2; exit 1; }
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$KUBE_CONTEXT" && -f "$DEPLOY_DEFAULTS_FILE" ]]; then
  KUBE_CONTEXT="$(grep -E '^KUBE_CONTEXT=' "$DEPLOY_DEFAULTS_FILE" | tail -n1 | cut -d'=' -f2- || true)"
fi

if [[ -z "$KUBE_CONTEXT" ]]; then
  KUBE_CONTEXT="$(kubectl config current-context)"
fi

echo "Forwarding ${NAMESPACE}/${SERVICE}:8200 → localhost:8200"
echo "Using kubectl context: ${KUBE_CONTEXT}"
echo "Press Ctrl-C to stop."

kubectl --context "${KUBE_CONTEXT}" port-forward \
  --namespace "${NAMESPACE}" \
  "service/${SERVICE}" \
  8200:8200
