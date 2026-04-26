# Vault Operations Guide

This document explains the end-to-end operational flow for this Vault environment: from first-time setup through daily use, host reboots, and integration into batch processes.

---

## Background: Sealed vs Unsealed

Vault always starts in a **sealed** state after its process starts. A sealed Vault rejects every API call except seal-status and unseal. You must unseal it before any secret reads or writes will work.

Sealing is a security feature, not an error. The unseal keys are held separately from the encrypted data, so even if someone gains access to the Vault pod's storage, they cannot read secrets without the keys.

**When to unseal:** Any time the Vault pod has restarted (host reboot, pod eviction, rolling update, manual delete).

**When to (re)seal manually:** If you suspect the node is compromised, or before planned maintenance where you want to guarantee no reads can occur. Run:

```bash
curl -fsS -X PUT \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/sys/seal"
```

In normal day-to-day use you do not need to seal Vault manually.

---

## 1. Initial Setup (Run Once)

This section is a one-time procedure. After it is complete, unseal keys and the root token are stored in `.vault/init.json` and never need to be regenerated.

### 1.1 Deploy Vault to Kubernetes

```bash
./scripts/deploy.sh
```

This applies all Kubernetes manifests, waits for the pod to be ready, starts a port-forward (if needed), initializes Vault, and runs the end-to-end smoke test.

To also deploy the devpod development container at the same time:

```bash
./scripts/deploy.sh --with-devpod
```

After this command completes successfully, Vault is initialized, unsealed, and verified.

### 1.2 What deploy.sh did internally

1. Applied `k8s/vault/` manifests — namespace, configmap, PVC, StatefulSet, services.
2. Waited for `vault-0` pod to reach Running state.
3. Established a port-forward (`localhost:8200 → vault pod:8200`) or determined the NodePort address.
4. Called `POST /v1/sys/init` with 5 shares / threshold 3 and saved the response to `.vault/init.json`.
5. Called `PUT /v1/sys/unseal` three times using the first three base64 unseal keys.
6. Enabled the KV v2 secrets engine at `secret/`.
7. Ran `scripts/verify.sh` — wrote and read a demo secret using Bash and Python.

### 1.3 Keep .vault/init.json safe

`.vault/init.json` contains the unseal keys and root token. It is git-ignored. Back it up somewhere secure (e.g. a password manager). Without it, you cannot unseal Vault after a restart and cannot recover secrets.

### 1.4 Set environment variables for the current shell

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)
```

You must set these in every new terminal session where you want to interact with Vault.

---

## 2. Restart After Host Reboot

When your machine (or Kubernetes node) reboots:

1. The Kubernetes cluster restarts (minikube/kind/k3s may start automatically, or you may need to start it manually).
2. The `vault-0` pod restarts because it is managed by a StatefulSet.
3. Vault starts in **sealed** state — this is expected.
4. The PVC retains all previously written secrets.

### 2.1 Verify the cluster and pod are up

```bash
kubectl get pods -n vault
```

Expected output:

```
NAME      READY   STATUS    RESTARTS   AGE
vault-0   1/1     Running   0          ...
```

`READY 1/1` is shown because the readiness probe accepts sealed pods. The pod is running but Vault is sealed.

### 2.2 Re-establish host access

**If using port-forward** (always works):

```bash
# In a dedicated terminal — leave it running
./scripts/port-forward.sh --kube-context docker-desktop
```

If you only have one relevant kube context, you can omit `--kube-context`:

```bash
./scripts/port-forward.sh
```

`port-forward.sh` will otherwise reuse the last successful deploy context from `.vault/deploy.defaults` when available, or fall back to the current kubectl context.

Then in your working terminal:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
```

Check the current seal state before deciding whether you need to unseal:

```bash
curl -fsS "${VAULT_ADDR}/v1/sys/seal-status" | jq
```

Look at the `sealed` field:

- `true` means Vault must be unsealed before reads and writes will work.
- `false` means Vault is already unsealed and you can skip directly to the secret read check.

**If using NodePort** (cluster node IP is directly reachable):

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
export VAULT_ADDR=http://${NODE_IP}:32200
```

### 2.3 Unseal Vault

If the previous `seal-status` check returned `"sealed": false`, skip this section and go directly to section 2.4.

The fastest way — `verify.sh` detects the sealed state and unseals automatically:

```bash
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)
./scripts/verify.sh
```

To unseal without running the full smoke test, submit the keys directly:

```bash
KEY_FIELD=$(jq -r 'if (.keys_base64 // []) | length >= 3 then "keys_base64" else "unseal_keys_b64" end' .vault/init.json)

for i in 0 1 2; do
  curl -fsS -X PUT \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"$(jq -r --argjson i $i ".[$KEY_FIELD][$i]" .vault/init.json)\"}" \
    "${VAULT_ADDR}/v1/sys/unseal"
done
```

After three successful unseal calls the response will include `"sealed": false`. Vault is now ready.

### 2.4 Confirm secrets persisted

```bash
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)
bash examples/bash/read_secret.sh
```

Expected output:

```
username=alice
password=correct-horse-battery-staple
```

---

## 3. Using Vault in a Batch Process

A batch process (scheduled job, CI pipeline, automation script) needs to:

1. Reach Vault without human interaction.
2. Authenticate and obtain a token.
3. Read (and optionally write) secrets.
4. Use a least-privilege token — not the root token.

### 3.1 Create a policy for the batch process

Policies restrict what a token can do. Create a read-only policy for `secret/demo`:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)

curl -fsS -X PUT \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"policy": "path \"secret/data/demo\" { capabilities = [\"read\"] }"}' \
  "${VAULT_ADDR}/v1/sys/policies/acl/batch-read-demo"
```

### 3.2 Create a batch token

Generate a token with a limited TTL tied to the policy above:

```bash
BATCH_TOKEN=$(curl -fsS -X POST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"policies": ["batch-read-demo"], "ttl": "1h", "renewable": false}' \
  "${VAULT_ADDR}/v1/auth/token/create" | jq -r '.auth.client_token')

echo "Batch token: ${BATCH_TOKEN}"
```

Store `BATCH_TOKEN` in your CI/CD secrets store or Kubernetes Secret — not in source code.

### 3.3 Read a secret from the batch process

Using the batch token (no root token needed):

**Bash:**

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=${BATCH_TOKEN}   # injected by CI or Kubernetes

curl -fsS \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/demo" | jq -r '.data.data'
```

**Python (using the existing examples):**

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=${BATCH_TOKEN}

source .venv/bin/activate
python examples/python/http_read_secret.py
```

### 3.4 Ensure Vault is unsealed before the batch process runs

A batch process cannot unseal Vault by itself unless you deliberately provide unseal keys to it — which defeats the purpose of sealing. The recommended approach for this environment is:

- Unseal Vault once after each host/pod restart (manually or via an operator script).
- Have the batch process verify Vault is unsealed before starting:

```bash
SEALED=$(curl -fsS "${VAULT_ADDR}/v1/sys/seal-status" | jq -r '.sealed')
if [[ "$SEALED" == "true" ]]; then
  echo "ERROR: Vault is sealed. Unseal it before running this job."
  exit 1
fi
```

- If fully automated restart recovery is required, store unseal keys in a separate secrets manager (AWS Secrets Manager, Azure Key Vault, etc.) and retrieve them in a startup operator job — this is outside the scope of this demo environment.

### 3.5 Token lifecycle in a batch process

| Action | When |
|---|---|
| Create batch token | Once per job invocation (or once per day with a long TTL) |
| Read secret | During the job |
| Revoke token | Immediately after the job finishes (optional but good practice) |

To revoke a token when done:

```bash
curl -fsS -X POST \
  -H "X-Vault-Token: ${BATCH_TOKEN}" \
  "${VAULT_ADDR}/v1/auth/token/revoke-self"
```

---

## Summary: Unseal / Seal Decision Table

| Situation | Action |
|---|---|
| First-time deploy | `deploy.sh` handles init + unseal automatically |
| Host/node reboot | Unseal via `verify.sh` or manual API calls |
| Pod deleted and recreated | Unseal — storage persists, seal state resets |
| Suspected compromise | Seal immediately; rotate root token; investigate |
| Planned maintenance | Seal before; unseal after |
| Normal working session | No action needed — stays unsealed until pod restarts |
| Batch process starts | Check seal status; fail fast if sealed |
