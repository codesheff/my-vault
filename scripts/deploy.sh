#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NAMESPACE="vault"
VAULT_SERVICE="vault"
LOCAL_PORT="8200"
REMOTE_PORT="8200"
VAULT_ADDR_DEFAULT="http://127.0.0.1:8200"
WITH_DEVPOD="0"
WAIT_DEVPOD="0"
CURRENT_STEP="startup"
KUBE_CONTEXT=""
USER_KUBE_CONTEXT=""
SAVED_KUBE_CONTEXT=""
DEPLOY_DEFAULTS_FILE=".vault/deploy.defaults"

step() {
  CURRENT_STEP="$1"
  echo "[STEP] $1"
}

pass() { echo "[PASS] $1"; }

print_debug_context() {
  echo "[DEBUG] locked-context: ${KUBE_CONTEXT:-unset}"
  echo "[DEBUG] current-context: $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "[DEBUG] api-server: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo unknown)"
}

fail() {
  local message="$1"
  echo "[FAIL] step=${CURRENT_STEP} reason=${message}"
  print_debug_context
  exit 1
}

kubectl_with_timeout() {
  timeout -k 5s 20s kubectl --context "$KUBE_CONTEXT" "$@"
}

kubectl_with_timeout_ctx() {
  local ctx="$1"
  shift
  timeout -k 5s 20s kubectl --context "$ctx" "$@"
}

kubectl_locked() {
  kubectl --context "$KUBE_CONTEXT" "$@"
}

load_saved_defaults() {
  if [[ -f "$DEPLOY_DEFAULTS_FILE" ]]; then
    SAVED_KUBE_CONTEXT="$(grep -E '^KUBE_CONTEXT=' "$DEPLOY_DEFAULTS_FILE" | tail -n1 | cut -d'=' -f2- || true)"
  fi
}

save_defaults() {
  mkdir -p .vault
  printf 'KUBE_CONTEXT=%s\n' "$KUBE_CONTEXT" > "$DEPLOY_DEFAULTS_FILE"
}

retry_cmd() {
  local tries="$1"
  shift
  local delay="$1"
  shift

  local i
  for ((i = 1; i <= tries; i++)); do
    if "$@"; then
      return 0
    fi
    if [[ "$i" -lt "$tries" ]]; then
      sleep "$delay"
    fi
  done
  return 1
}

vault_health_ok() {
  local url="$1"
  curl --silent --show-error --fail \
    "${url}/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200" >/dev/null
}

resolve_nodeport_vault_addr() {
  local node_port
  local node_ip

  node_port="$(kubectl_with_timeout -n "$NAMESPACE" get service "$VAULT_SERVICE" -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}' 2>/dev/null || true)"
  node_ip="$(kubectl_with_timeout get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"

  if [[ -n "$node_port" && -n "$node_ip" ]]; then
    echo "http://${node_ip}:${node_port}"
    return 0
  fi

  return 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy.sh [options]

Deploy Vault on Kubernetes and run end-to-end verification.

Options:
  --with-devpod        Deploy k8s/devpod resources as part of deployment.
  --wait-devpod        Wait for devpod rollout (implies --with-devpod).
  --vault-addr <url>   Vault URL used by verify.sh (default: http://127.0.0.1:8200).
  --kube-context <ctx> Kubernetes context to use (overrides saved/default context).
  -h, --help           Show this help.
EOF
}

VAULT_ADDR="$VAULT_ADDR_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-devpod)
      WITH_DEVPOD="1"
      shift
      ;;
    --wait-devpod)
      WITH_DEVPOD="1"
      WAIT_DEVPOD="1"
      shift
      ;;
    --vault-addr)
      [[ $# -ge 2 ]] || fail "--vault-addr requires a value"
      VAULT_ADDR="$2"
      shift 2
      ;;
    --kube-context)
      [[ $# -ge 2 ]] || fail "--kube-context requires a value"
      USER_KUBE_CONTEXT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

for cmd in kubectl curl jq timeout; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
done

load_saved_defaults

if [[ -n "$USER_KUBE_CONTEXT" ]]; then
  KUBE_CONTEXT="$USER_KUBE_CONTEXT"
elif [[ -n "$SAVED_KUBE_CONTEXT" ]]; then
  KUBE_CONTEXT="$SAVED_KUBE_CONTEXT"
  echo "[INFO] Using saved Kubernetes context: $KUBE_CONTEXT"
else
  KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
fi
[[ -n "$KUBE_CONTEXT" ]] || fail "Unable to determine kubectl current context"

echo "[INFO] Using Kubernetes context: $KUBE_CONTEXT"

step "Check Kubernetes API connectivity"
if ! retry_cmd 5 3 kubectl_with_timeout get --raw=/version >/dev/null 2>&1; then
  if [[ "$KUBE_CONTEXT" != "docker-desktop" ]] && kubectl config get-contexts -o name | grep -qx "docker-desktop"; then
    echo "[DEBUG] Falling back to Kubernetes context: docker-desktop"
    if retry_cmd 3 2 kubectl_with_timeout_ctx "docker-desktop" get --raw=/version >/dev/null 2>&1; then
      KUBE_CONTEXT="docker-desktop"
      echo "[INFO] Switched Kubernetes context to: $KUBE_CONTEXT"
    else
      fail "Kubernetes API did not respond on context '$KUBE_CONTEXT' or docker-desktop"
    fi
  else
    fail "Kubernetes API did not respond after 5 attempts (20s timeout per attempt)"
  fi
fi
pass "Kubernetes API reachable"
save_defaults

step "Deploy Vault manifests"
kubectl_locked apply -f k8s/vault/namespace.yaml >/dev/null
kubectl_locked apply -f k8s/vault/ >/dev/null
pass "Vault manifests applied"

step "Wait for Vault StatefulSet rollout"
kubectl_locked rollout status statefulset/vault -n "$NAMESPACE" --timeout=300s >/dev/null
pass "Vault StatefulSet ready"

if [[ "$WITH_DEVPOD" == "1" ]]; then
  step "Deploy devpod manifests"
  kubectl_locked apply -f k8s/devpod/deployment.yaml >/dev/null
  kubectl_locked apply -f k8s/devpod/service.yaml >/dev/null
  pass "devpod manifests applied"

  if [[ "$WAIT_DEVPOD" == "1" ]]; then
    step "Wait for devpod rollout"
    kubectl_locked rollout status deployment/devpod -n "$NAMESPACE" --timeout=300s >/dev/null
    pass "devpod deployment ready"
  fi
fi

mkdir -p .vault
PF_LOG=".vault/port-forward-deploy.log"

cleanup() {
  if [[ -n "${PF_PID:-}" ]] && kill -0 "$PF_PID" >/dev/null 2>&1; then
    kill "$PF_PID" >/dev/null 2>&1 || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "$VAULT_ADDR" == "$VAULT_ADDR_DEFAULT" ]]; then
  step "Start local port-forward to Vault"
  : > "$PF_LOG"
  kubectl_locked port-forward --namespace "$NAMESPACE" "service/$VAULT_SERVICE" "$LOCAL_PORT:$REMOTE_PORT" >"$PF_LOG" 2>&1 &
  PF_PID=$!

  if ! kill -0 "$PF_PID" >/dev/null 2>&1; then
    tail -n 40 "$PF_LOG" >&2 || true
    fail "port-forward process exited immediately"
  fi

  if retry_cmd 20 1 vault_health_ok "$VAULT_ADDR"; then
    pass "Port-forward active and Vault reachable at $VAULT_ADDR"
  else
    echo "[DEBUG] local Vault health check failed via port-forward, trying NodePort fallback"
    tail -n 40 "$PF_LOG" >&2 || true

    nodeport_addr="$(resolve_nodeport_vault_addr || true)"
    if [[ -n "${nodeport_addr:-}" ]] && retry_cmd 10 1 vault_health_ok "$nodeport_addr"; then
      VAULT_ADDR="$nodeport_addr"
      pass "Vault reachable via NodePort fallback at $VAULT_ADDR"
    else
      fail "Vault not reachable via localhost port-forward or NodePort fallback"
    fi
  fi
fi

step "Ensure Vault initialization metadata exists"
init_state="$(curl -fsS "$VAULT_ADDR/v1/sys/init" | jq -r '.initialized')"

if [[ "$init_state" == "false" ]]; then
  curl -fsS -X PUT \
    -H "Content-Type: application/json" \
    -d '{"secret_shares":5,"secret_threshold":3}' \
    "$VAULT_ADDR/v1/sys/init" > .vault/init.json.tmp

  jq -e . .vault/init.json.tmp >/dev/null 2>&1 || fail "Initialization output is not valid JSON"
  mv .vault/init.json.tmp .vault/init.json
  cp .vault/init.json .vault/init.txt
  pass "Vault initialized and init metadata saved to .vault/init.json"
else
  if [[ (! -f .vault/init.json || ! -s .vault/init.json) && -f .vault/init.txt ]]; then
    cp .vault/init.txt .vault/init.json
  fi

  [[ -s .vault/init.json ]] || fail "Vault is already initialized, but .vault/init.json is missing. Restore it to allow automated unseal."
  jq -e . .vault/init.json >/dev/null 2>&1 || fail ".vault/init.json is invalid JSON"
  pass "Existing init metadata is available"
fi

step "Run full verification"
VAULT_ADDR="$VAULT_ADDR" ./scripts/verify.sh
pass "Deployment and verification completed"

echo
echo "Done."
echo "VAULT_ADDR=$VAULT_ADDR"
if [[ -f "$PF_LOG" ]]; then
  echo "Port-forward log: $PF_LOG"
fi
