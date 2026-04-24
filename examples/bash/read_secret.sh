#!/usr/bin/env bash
set -euo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR, e.g. http://127.0.0.1:8200}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN to a token with secret/* access}"

path="secret/data/demo"

# Read the KV v2 secret back from secret/demo.
resp="$(curl -fsS \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/${path}")"

if command -v jq >/dev/null 2>&1; then
  user="$(printf '%s' "$resp" | jq -r '.data.data.username')"
  pass="$(printf '%s' "$resp" | jq -r '.data.data.password')"
else
  echo "jq is required to parse the response for this example" >&2
  exit 1
fi

echo "username=${user}"
echo "password=${pass}"