#!/usr/bin/env bash
set -euo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR, e.g. http://127.0.0.1:8200}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN to a token with secret/* access}"

path="secret/data/demo"

# Write a KV v2 secret to secret/demo.
curl -fsS \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"data":{"username":"alice","password":"correct-horse-battery-staple"}}' \
  "${VAULT_ADDR}/v1/${path}" >/dev/null

echo "secret written: path=${path}"