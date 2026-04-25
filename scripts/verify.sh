#!/usr/bin/env bash
# verify.sh — end-to-end smoke test for Vault on Kubernetes.
#
# Prerequisites:
#   VAULT_ADDR  must be set to the reachable Vault endpoint, e.g.:
#               http://<node-ip>:32200        (NodePort, from host)
#               http://127.0.0.1:8200         (after running scripts/port-forward.sh)
#               http://vault.vault.svc.cluster.local:8200  (from devpod)
#
#   .vault/init.json must exist with the JSON output from `vault operator init`.
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8200
#   ./scripts/verify.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

step() { echo "[STEP] $1"; }
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }

: "${VAULT_ADDR:?Set VAULT_ADDR to the Vault endpoint (e.g. http://127.0.0.1:8200)}"

step "Check Vault is reachable at ${VAULT_ADDR}"
curl -fsS "${VAULT_ADDR}/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200" >/dev/null \
  || fail "Cannot reach Vault at ${VAULT_ADDR}"
pass "Vault is reachable"

step "Ensure init metadata exists"
if [[ (! -f .vault/init.json || ! -s .vault/init.json) && -f .vault/init.txt ]]; then
  cp .vault/init.txt .vault/init.json
fi
[[ -f .vault/init.json ]] || fail "Missing .vault/init.json — run 'vault operator init' against ${VAULT_ADDR} and save the output there"

# Validate that init metadata is parseable and contains a token.
jq -e . .vault/init.json >/dev/null 2>&1 || fail ".vault/init.json is not valid JSON"
jq -e '(.root_token // "") | length > 0' .vault/init.json >/dev/null 2>&1 \
  || fail ".vault/init.json is missing root_token"
pass "Init metadata ready"

export VAULT_TOKEN="$(jq -r '.root_token' .vault/init.json)"

step "Ensure Vault is unsealed"
status_json="$(curl -fsS "${VAULT_ADDR}/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200" || echo '{}')"
sealed="$(curl -fsS "${VAULT_ADDR}/v1/sys/seal-status" | jq -r '.sealed')"

if [[ "$sealed" == "true" ]]; then
  # Support both init output formats:
  # - API init: keys_base64
  # - vault CLI init: unseal_keys_b64
  key_field="$(jq -r 'if (.keys_base64 // []) | length >= 3 then "keys_base64" elif (.unseal_keys_b64 // []) | length >= 3 then "unseal_keys_b64" else "" end' .vault/init.json)"
  [[ -n "$key_field" ]] || fail ".vault/init.json is missing unseal keys (expected keys_base64 or unseal_keys_b64)"

  k1="$(jq -r --arg f "$key_field" '.[$f][0]' .vault/init.json)"
  k2="$(jq -r --arg f "$key_field" '.[$f][1]' .vault/init.json)"
  k3="$(jq -r --arg f "$key_field" '.[$f][2]' .vault/init.json)"
  [[ -n "$k1" && -n "$k2" && -n "$k3" ]] || fail "Unseal keys are empty in .vault/init.json"

  for key in "$k1" "$k2" "$k3"; do
    curl -fsS -X PUT \
      -H "Content-Type: application/json" \
      -d "{\"key\": \"${key}\"}" \
      "${VAULT_ADDR}/v1/sys/unseal" >/dev/null
  done
fi
pass "Vault unsealed"

step "Ensure secret/ uses KV v2"
curl -sS \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/sys/mounts" | jq -e '."secret/".type == "kv" and ."secret/".options.version == "2"' >/dev/null || \
curl -sS -X POST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"type":"kv","options":{"version":"2"}}' \
  "${VAULT_ADDR}/v1/sys/mounts/secret" >/dev/null
pass "KV v2 ready"

step "Run host-based Bash write and read examples"
bash examples/bash/write_secret.sh >/dev/null
bash examples/bash/read_secret.sh >/dev/null
pass "Bash examples passed"

step "Prepare local uv virtual environment"
[[ -d .venv ]] || uv venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
uv pip install -r requirements.txt >/dev/null
pass "Python environment ready"

step "Run Python hvac write and read examples"
python examples/python/hvac_write_secret.py >/dev/null
python examples/python/hvac_read_secret.py >/dev/null
pass "Python hvac examples passed"

step "Run Python raw HTTP write and read examples"
python examples/python/http_write_secret.py >/dev/null
python examples/python/http_read_secret.py >/dev/null
pass "Python raw HTTP examples passed"

echo ""
echo "All checks passed."
echo ""
echo "To verify persistence across pod restarts:"
echo "  1. Delete the vault pod:  kubectl delete pod vault-0 -n vault"
echo "  2. Wait for it to restart: kubectl rollout status statefulset/vault -n vault"
echo "  3. Unseal:  ./scripts/verify.sh   (it will unseal automatically using .vault/init.json)"
echo "  4. Re-run read example:  bash examples/bash/read_secret.sh"
