#!/usr/bin/env bash
# create-token.sh — create a scoped Vault token for a given path and access level.
#
# The script derives a policy name from the path and access level, creates the
# policy if it does not already exist, then creates and prints a token bound to
# that policy.
#
# Usage:
#   ./scripts/create-token.sh --path secret/data/chg-automation/live --access read
#   ./scripts/create-token.sh --path secret/data/chg-automation/live --access write
#   ./scripts/create-token.sh --path secret/data/chg-automation/live --access readwrite
#   ./scripts/create-token.sh --path secret/data/chg-automation/live --access read --ttl 8h
#   ./scripts/create-token.sh --path secret/data/chg-automation/live --access write --policy-name my-custom-policy
#
# Prerequisites:
#   VAULT_ADDR   must be set (e.g. http://127.0.0.1:8200 from host, or
#                              http://vault.vault.svc.cluster.local:8200 from devpod)
#   VAULT_TOKEN  must be set to a root token or a token with permission to create
#                policies (sys/policies/acl/*) and tokens (auth/token/create).
#
# Access levels:
#   read       → capabilities: read, list
#   write      → capabilities: create, update, read, list
#   readwrite  → capabilities: create, update, read, list, delete

set -euo pipefail

PATH_ARG=""
ACCESS=""
TTL="24h"
POLICY_NAME_OVERRIDE=""

# ── helpers ──────────────────────────────────────────────────────────────────

info() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 --path <vault-path> --access <read|write|readwrite> [OPTIONS]

Required:
  --path    <vault-path>   Vault secret path to grant access to.
                           For KV v2 the path includes the 'data' segment, e.g.:
                             secret/data/chg-automation/live
                             secret/data/demo
  --access  <level>        Access level: read | write | readwrite

Optional:
  --ttl     <duration>     Token TTL (default: 24h). Examples: 1h, 48h, 720h
  --policy-name <name>     Override the auto-derived policy name
  -h, --help               Show this help

Environment variables required:
  VAULT_ADDR    Vault endpoint  (e.g. http://127.0.0.1:8200)
  VAULT_TOKEN   Admin token with policy and token creation rights
EOF
  exit 1
}

# ── argument parsing ─────────────────────────────────────────────────────────

[[ $# -gt 0 ]] || usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)         PATH_ARG="$2";              shift 2 ;;
    --access)       ACCESS="$2";                shift 2 ;;
    --ttl)          TTL="$2";                   shift 2 ;;
    --policy-name)  POLICY_NAME_OVERRIDE="$2";  shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[[ -n "$PATH_ARG" ]] || { echo "ERROR: --path is required"; usage; }
[[ -n "$ACCESS" ]]   || { echo "ERROR: --access is required"; usage; }
[[ "$ACCESS" =~ ^(read|write|readwrite)$ ]] \
  || { echo "ERROR: --access must be one of: read, write, readwrite"; usage; }

: "${VAULT_ADDR:?Set VAULT_ADDR to the Vault endpoint (e.g. http://127.0.0.1:8200)}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN to a root or admin token}"

# ── derive policy name ────────────────────────────────────────────────────────

if [[ -n "$POLICY_NAME_OVERRIDE" ]]; then
  POLICY_NAME="$POLICY_NAME_OVERRIDE"
else
  # Replace '/' and '.' with '-', strip leading/trailing dashes, append access level
  POLICY_NAME="$(echo "${PATH_ARG}" | tr '/.' '-' | sed 's/^-*//;s/-*$//')-${ACCESS}"
fi

# ── capabilities for each access level ───────────────────────────────────────

case "$ACCESS" in
  read)      CAPS='["read","list"]' ;;
  write)     CAPS='["create","update","read","list"]' ;;
  readwrite) CAPS='["create","update","read","list","delete"]' ;;
esac

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "  Vault address : ${VAULT_ADDR}"
echo "  Path          : ${PATH_ARG}"
echo "  Access        : ${ACCESS}  →  capabilities ${CAPS}"
echo "  Policy name   : ${POLICY_NAME}"
echo "  Token TTL     : ${TTL}"
echo ""

# ── create policy (idempotent) ────────────────────────────────────────────────

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/sys/policies/acl/${POLICY_NAME}")

if [[ "$HTTP_STATUS" == "200" ]]; then
  info "Policy '${POLICY_NAME}' already exists — reusing it"
else
  info "Policy '${POLICY_NAME}' not found (HTTP ${HTTP_STATUS}) — creating it..."
  POLICY_HCL="path \"${PATH_ARG}\" { capabilities = ${CAPS} }"
  POLICY_JSON=$(jq -n --arg p "$POLICY_HCL" '{"policy": $p}')

  curl -fsS -X PUT \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$POLICY_JSON" \
    "${VAULT_ADDR}/v1/sys/policies/acl/${POLICY_NAME}" \
    > /dev/null
  pass "Policy '${POLICY_NAME}' created"
fi

# ── create token ─────────────────────────────────────────────────────────────

info "Creating token..."
TOKEN_RESPONSE=$(curl -fsS -X POST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"policies\": [\"${POLICY_NAME}\"], \"ttl\": \"${TTL}\", \"renewable\": true}" \
  "${VAULT_ADDR}/v1/auth/token/create")

NEW_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.auth.client_token')
ACCESSOR=$(echo "$TOKEN_RESPONSE"  | jq -r '.auth.accessor')
ACTUAL_TTL=$(echo "$TOKEN_RESPONSE" | jq -r '.auth.lease_duration')

# ── output ────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Token created successfully"
echo "========================================================"
echo "  Token    : ${NEW_TOKEN}"
echo "  Accessor : ${ACCESSOR}"
echo "  Policy   : ${POLICY_NAME}"
echo "  Path     : ${PATH_ARG}"
echo "  Access   : ${ACCESS}"
echo "  TTL      : ${ACTUAL_TTL}s"
echo "========================================================"
echo ""
echo "To use this token:"
echo "  export VAULT_TOKEN=${NEW_TOKEN}"
echo ""
echo "To revoke this token when done:"
echo "  curl -fsS -X POST -H \"X-Vault-Token: \${VAULT_TOKEN}\" ${VAULT_ADDR}/v1/auth/token/revoke-self"
echo ""
