#!/usr/bin/env bash
# vault-seal.sh — seal or unseal a Vault instance.
#
# Usage:
#   ./scripts/vault-seal.sh seal
#   ./scripts/vault-seal.sh unseal
#   ./scripts/vault-seal.sh status
#
# Prerequisites:
#   VAULT_ADDR   must be set (e.g. http://127.0.0.1:8200)
#   VAULT_TOKEN  must be set for 'seal' (root or token with sys/seal capability)
#                Not required for 'unseal' or 'status' — keys are read from .vault/init.json
#
# The 'unseal' subcommand reads unseal keys from .vault/init.json automatically.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INIT_JSON=".vault/init.json"

info() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 <subcommand>

Subcommands:
  status    Show current seal state
  seal      Seal Vault  (requires VAULT_TOKEN with sys/seal capability)
  unseal    Unseal Vault using keys from ${INIT_JSON}

Environment variables:
  VAULT_ADDR    Vault endpoint  (e.g. http://127.0.0.1:8200)
  VAULT_TOKEN   Required for 'seal'; not required for 'unseal' / 'status'
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage
SUBCOMMAND="$1"

: "${VAULT_ADDR:?Set VAULT_ADDR to the Vault endpoint (e.g. http://127.0.0.1:8200)}"

# ── helpers ──────────────────────────────────────────────────────────────────

get_seal_status() {
  curl -fsS "${VAULT_ADDR}/v1/sys/seal-status" | jq -r '.sealed'
}

print_status() {
  local status_json
  status_json=$(curl -fsS "${VAULT_ADDR}/v1/sys/seal-status")
  local sealed
  sealed=$(echo "$status_json" | jq -r '.sealed')
  local progress
  progress=$(echo "$status_json" | jq -r '.progress // 0')
  local threshold
  threshold=$(echo "$status_json" | jq -r '.t // 0')

  echo ""
  echo "  Vault address : ${VAULT_ADDR}"
  if [[ "$sealed" == "true" ]]; then
    echo "  Seal state    : SEALED  (unseal progress: ${progress}/${threshold})"
  else
    echo "  Seal state    : UNSEALED"
  fi
  echo ""
}

do_seal() {
  : "${VAULT_TOKEN:?Set VAULT_TOKEN (root or token with sys/seal capability)}"

  local sealed
  sealed=$(get_seal_status)
  if [[ "$sealed" == "true" ]]; then
    info "Vault is already sealed — nothing to do"
    print_status
    exit 0
  fi

  info "Sealing Vault at ${VAULT_ADDR}..."
  curl -fsS -X PUT \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/sys/seal" > /dev/null

  sealed=$(get_seal_status)
  [[ "$sealed" == "true" ]] && pass "Vault is now SEALED" || fail "Seal request sent but Vault reports sealed=false"
  print_status
}

do_unseal() {
  local sealed
  sealed=$(get_seal_status)
  if [[ "$sealed" == "false" ]]; then
    info "Vault is already unsealed — nothing to do"
    print_status
    exit 0
  fi

  [[ -f "$INIT_JSON" ]] || fail "Missing ${INIT_JSON} — cannot read unseal keys"
  jq -e . "$INIT_JSON" > /dev/null 2>&1 || fail "${INIT_JSON} is not valid JSON"

  # Support both init output formats: keys_base64 (API) and unseal_keys_b64 (vault CLI)
  KEY_FIELD=$(jq -r '
    if (.keys_base64 // []) | length >= 3 then "keys_base64"
    elif (.unseal_keys_b64 // []) | length >= 3 then "unseal_keys_b64"
    else ""
    end' "$INIT_JSON")
  [[ -n "$KEY_FIELD" ]] || fail "${INIT_JSON} is missing unseal keys (expected keys_base64 or unseal_keys_b64 with >= 3 entries)"

  info "Unsealing Vault at ${VAULT_ADDR} using keys from ${INIT_JSON}..."

  for i in 0 1 2; do
    KEY=$(jq -r --arg f "$KEY_FIELD" --argjson i "$i" '.[$f][$i]' "$INIT_JSON")
    [[ -n "$KEY" && "$KEY" != "null" ]] || fail "Unseal key index ${i} is empty in ${INIT_JSON}"

    RESPONSE=$(curl -fsS -X PUT \
      -H "Content-Type: application/json" \
      -d "{\"key\": \"${KEY}\"}" \
      "${VAULT_ADDR}/v1/sys/unseal")

    SEALED_NOW=$(echo "$RESPONSE" | jq -r '.sealed')
    PROGRESS=$(echo "$RESPONSE"   | jq -r '.progress // 0')
    THRESHOLD=$(echo "$RESPONSE"  | jq -r '.t // 0')

    if [[ "$SEALED_NOW" == "false" ]]; then
      pass "Vault is now UNSEALED (submitted $((i+1)) key(s))"
      print_status
      exit 0
    fi
    info "Key $((i+1)) accepted — progress: ${PROGRESS}/${THRESHOLD}"
  done

  # Recheck after all three keys
  sealed=$(get_seal_status)
  if [[ "$sealed" == "false" ]]; then
    pass "Vault is now UNSEALED"
  else
    fail "All three keys submitted but Vault is still sealed — check keys in ${INIT_JSON}"
  fi
  print_status
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$SUBCOMMAND" in
  status)  print_status ;;
  seal)    do_seal ;;
  unseal)  do_unseal ;;
  *)       echo "Unknown subcommand: ${SUBCOMMAND}"; usage ;;
esac
