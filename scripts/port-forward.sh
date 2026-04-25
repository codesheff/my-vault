#!/usr/bin/env bash
# port-forward.sh — forward Vault's port 8200 to localhost:8200.
# Use this on clusters where NodePort is not directly reachable from the host
# (e.g., kind, minikube with no node IP route).
#
# Usage:
#   ./scripts/port-forward.sh
#
# After running, set:
#   export VAULT_ADDR=http://127.0.0.1:8200
set -euo pipefail

NAMESPACE=vault
SERVICE=vault

echo "Forwarding ${NAMESPACE}/${SERVICE}:8200 → localhost:8200"
echo "Press Ctrl-C to stop."

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  "service/${SERVICE}" \
  8200:8200
