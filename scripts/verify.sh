#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

step() {
  echo "[STEP] $1"
}

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1"
  exit 1
}

step "Start Vault"
docker compose up -d >/dev/null
pass "Vault container running"

step "Ensure init metadata exists"
if [[ ! -f .vault/init.json && -f .vault/init.txt ]]; then
  cp .vault/init.txt .vault/init.json
fi
[[ -f .vault/init.json ]] || fail "Missing .vault/init.json (initialize Vault first)"
pass "Init metadata ready"

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN="$(jq -r '.root_token' .vault/init.json)"

step "Ensure Vault is unsealed"
status_json="$(docker compose exec -T vault sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault status -format=json' 2>/dev/null || true)"
sealed="true"
if [[ -n "$status_json" ]]; then
  sealed="$(printf '%s' "$status_json" | jq -r '.sealed')"
fi

if [[ "$sealed" == "true" ]]; then
  k1="$(jq -r '.unseal_keys_b64[0]' .vault/init.json)"
  k2="$(jq -r '.unseal_keys_b64[1]' .vault/init.json)"
  k3="$(jq -r '.unseal_keys_b64[2]' .vault/init.json)"
  docker compose exec -T vault sh -lc "export VAULT_ADDR=http://127.0.0.1:8200; vault operator unseal '$k1' >/dev/null; vault operator unseal '$k2' >/dev/null; vault operator unseal '$k3' >/dev/null"
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

step "Restart Vault"
docker compose down >/dev/null
docker compose up -d >/dev/null
pass "Vault restarted"

step "Verify Vault is initialized and sealed after restart"
post_restart_status="$(docker compose exec -T vault sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault status -format=json' 2>/dev/null || true)"
printf '%s' "$post_restart_status" | jq -e '.initialized == true and .sealed == true' >/dev/null || fail "Expected initialized=true and sealed=true"
pass "Restart state verified"

step "Unseal after restart"
k1="$(jq -r '.unseal_keys_b64[0]' .vault/init.json)"
k2="$(jq -r '.unseal_keys_b64[1]' .vault/init.json)"
k3="$(jq -r '.unseal_keys_b64[2]' .vault/init.json)"
docker compose exec -T vault sh -lc "export VAULT_ADDR=http://127.0.0.1:8200; vault operator unseal '$k1' >/dev/null; vault operator unseal '$k2' >/dev/null; vault operator unseal '$k3' >/dev/null"
pass "Unseal after restart complete"

step "Verify secret persistence with host-based Bash example"
export VAULT_TOKEN="$(jq -r '.root_token' .vault/init.json)"
bash examples/bash/read_secret.sh >/dev/null
pass "Secret persists across restart"

echo ""
echo "All checks passed."
