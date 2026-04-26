# HashiCorp Vault on Kubernetes

## Overview

This repository runs HashiCorp Vault as a StatefulSet on Kubernetes with persistent raft storage.
Secret write/read examples work from both the host machine and from a UBI-based dev container (`devpod`).

For a detailed description of components, networking, and file layout, see [ARCHITECTURE.md](ARCHITECTURE.md).

- Vault runs in server mode (not `-dev`); you must initialize and unseal it once.
- Data is persisted in a PVC and survives pod restarts.
- Secret write/read examples do not use `docker exec` or `kubectl exec`.

## Prerequisites

- A running Kubernetes cluster (minikube, kind, k3s, or similar)
- `kubectl` configured to reach the cluster
- `curl` and `jq` (for Bash examples and verify script)
- `uv` (for Python examples)
- `vault` CLI (optional; only needed for `vault operator init/unseal` commands)

## One-Command Deploy + Verify

The fastest way to deploy Vault and run end-to-end verification is:

```bash
./scripts/deploy.sh
```

What this does:
- applies Kubernetes manifests for Vault
- waits for Vault rollout
- starts local port-forward (when using default `VAULT_ADDR`)
- initializes Vault if needed
- runs [scripts/verify.sh](scripts/verify.sh)

Useful options:

```bash
# use an explicit reachable Vault address (for example from WSL)
./scripts/deploy.sh --vault-addr http://<host-or-node>:<port>

# pin the Kubernetes context used by deploy.sh
./scripts/deploy.sh --kube-context docker-desktop

# include devpod deployment
./scripts/deploy.sh --with-devpod

# include devpod and wait until it is ready
./scripts/deploy.sh --wait-devpod
```

`deploy.sh` remembers the last successful Kubernetes context in `.vault/deploy.defaults`.
Use `--kube-context` to override it for the current run.

If you prefer manual operator steps, continue with the sections below.

## Deploy Vault

```bash
kubectl apply -f k8s/vault/namespace.yaml
kubectl apply -f k8s/vault/
```

Wait for the pod to be ready:

```bash
kubectl rollout status statefulset/vault -n vault
```

## Access Vault from the Host

### Option A — NodePort (if your cluster node IP is reachable)

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
export VAULT_ADDR=http://${NODE_IP}:32200
```

### Option B — Port-forward (always works, including minikube/kind)

In a separate terminal:

```bash
./scripts/port-forward.sh --kube-context docker-desktop
```

If you only have one relevant kube context, you can omit `--kube-context`:

```bash
./scripts/port-forward.sh
```

Then in your working terminal:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
```

## Initialize and Unseal (One-Time)

1. Initialize Vault (run once; save the output securely):

```bash
curl -fsS -X PUT \
  -H "Content-Type: application/json" \
  -d '{"secret_shares":5,"secret_threshold":3}' \
  "${VAULT_ADDR}/v1/sys/init" | tee .vault/init.json
```

> `.vault/` is git-ignored. Keep this file secure; it contains unseal keys and the root token.

2. Unseal with any 3 of the 5 unseal keys from `.vault/init.json`:

```bash
for key in \
    "$(jq -r '.keys_base64[0]' .vault/init.json)" \
    "$(jq -r '.keys_base64[1]' .vault/init.json)" \
    "$(jq -r '.keys_base64[2]' .vault/init.json)"; do
  curl -fsS -X PUT \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"${key}\"}" \
    "${VAULT_ADDR}/v1/sys/unseal"
done
```

3. Export the root token:

```bash
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)
```

4. Enable KV v2 at `secret/`:

```bash
curl -fsS -X POST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"type":"kv","options":{"version":"2"}}' \
  "${VAULT_ADDR}/v1/sys/mounts/secret"
```

## Bash Examples (Host)

Write secret:

```bash
bash examples/bash/write_secret.sh
```

Read secret:

```bash
bash examples/bash/read_secret.sh
```

Expected output:

```
username=alice
password=correct-horse-battery-staple
```

## Python Setup with uv

```bash
[ -d .venv ] || uv venv .venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

## Python Example 1: hvac Client

```bash
python examples/python/hvac_write_secret.py
python examples/python/hvac_read_secret.py
```

## Python Example 2: Raw HTTP API

```bash
python examples/python/http_write_secret.py
python examples/python/http_read_secret.py
```

## End-to-End Smoke Test

Runs init/unseal (if needed), write/read for all examples:

```bash
export VAULT_ADDR=http://127.0.0.1:8200   # adjust as needed
./scripts/verify.sh
```

## Seal / Unseal Vault

`scripts/vault-seal.sh` provides a single command for seal, unseal, and status checks.
The `unseal` subcommand reads keys automatically from `.vault/init.json`.

```bash
export VAULT_ADDR=http://127.0.0.1:8200

# Check current seal state
./scripts/vault-seal.sh status

# Unseal (reads keys from .vault/init.json automatically)
./scripts/vault-seal.sh unseal

# Seal (requires a token with sys/seal capability)
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)
./scripts/vault-seal.sh seal
```

## Vault CLI Quick Reference

Use the Vault CLI for interactive admin and troubleshooting tasks.

### Install Vault CLI on host (Linux)

If `vault` is not found on your host shell, install it and verify:

```bash
# install via your distro package manager or from HashiCorp release binaries
vault version
```

Inside `devpod`, the Vault CLI is already installed.

### Configure CLI environment (host)

```bash
# run in a separate terminal if needed
./scripts/port-forward.sh

# in your working terminal
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)
```

### Core commands

```bash
# health / auth checks
vault status
vault token lookup

# seal/unseal
vault operator seal
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>
```

### KV v2 read/write

For CLI `kv` commands, use the logical mount path (`secret/...`) rather than API path (`secret/data/...`).

```bash
vault kv put secret/chg-automation/live username=alice password=example
vault kv get secret/chg-automation/live
```

### Policy and token examples

Create `policy.hcl`:

```hcl
path "secret/data/chg-automation/live" {
  capabilities = ["read"]
}
```

Apply policy and create token:

```bash
vault policy write chg-automation-live-read policy.hcl
vault token create -policy=chg-automation-live-read -ttl=1h
```

For scripted policy+token generation, use `./scripts/create-token.sh`.

## devpod — UBI 9 Development Container

`devpod` is a UBI 9 container with Python, uv, the Vault CLI, and the VS Code remote server.
It runs as user `z4701038-779` and can reach Vault via in-cluster DNS.

### Build the devpod image

```bash
docker build -t devpod:latest k8s/devpod/
```

For a cluster that cannot pull from a local daemon (e.g., kind), load the image:

```bash
kind load docker-image devpod:latest
```

Or push to a registry, update the image field in `k8s/devpod/deployment.yaml`, and change `imagePullPolicy` from `Never` to `IfNotPresent`.

### Deploy devpod

```bash
kubectl apply -f k8s/devpod/deployment.yaml
kubectl apply -f k8s/devpod/service.yaml
kubectl rollout status deployment/devpod -n vault
```

### Connect VS Code to devpod

1. Install the **Dev Containers** or **Remote – Tunnels** extension in VS Code.
2. Start a tunnel from inside the pod:

```bash
kubectl exec -n vault deploy/devpod -- code tunnel --accept-server-license-terms
```

3. Follow the printed URL to authenticate, then connect from VS Code.

Alternatively, use **Remote – Kubernetes** or attach directly via `kubectl exec`.

### Run Examples from devpod

Open a shell inside the pod:

```bash
kubectl exec -it -n vault deploy/devpod -- bash
```

Clone the repo into the workspace (the workspace volume is ephemeral; do this once per pod lifetime):

```bash
cd ~/workspace
git clone <your-repo-url> my-vault
cd my-vault
```

Inside the pod, `VAULT_ADDR` is pre-set to `http://vault.vault.svc.cluster.local:8200`.
Set your token and run the same examples:

```bash
export VAULT_TOKEN=<your-root-token>
bash examples/bash/write_secret.sh
bash examples/bash/read_secret.sh
```

For Python, create a venv:

```bash
uv venv .venv && source .venv/bin/activate
uv pip install -r requirements.txt
python examples/python/hvac_write_read.py
```

## Verify Persistence Across Pod Restarts

1. Delete the pod (the StatefulSet will recreate it):

```bash
kubectl delete pod vault-0 -n vault
kubectl rollout status statefulset/vault -n vault
```

2. Re-run `./scripts/verify.sh` — it will unseal automatically using `.vault/init.json` and re-run all examples.

## Security Notes

- `.vault/init.json` contains unseal keys and the root token. **Do not commit it.**
- For non-demo use, rotate the root token and configure appropriate Vault policies.
- The StatefulSet runs as root (`runAsUser: 0`) to avoid raft data permission issues on local clusters. For production, use an init container to `chown /vault/data` to uid 100 and remove the root override.

## Token and Policy Management

`scripts/create-token.sh` creates a scoped Vault token for any path and access level.
It automatically creates the required policy if it does not already exist.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' .vault/init.json)

# Read-only token for a path
./scripts/create-token.sh \
  --path secret/data/chg-automation/live \
  --access read

# Write (create/update + read) token for a path
./scripts/create-token.sh \
  --path secret/data/chg-automation/live \
  --access write

# Full read-write-delete token for a path
./scripts/create-token.sh \
  --path secret/data/chg-automation/live \
  --access readwrite

# Custom TTL (default is 24h)
./scripts/create-token.sh \
  --path secret/data/chg-automation/live \
  --access read \
  --ttl 8h
```

The script prints the token, its policy name, and revocation instructions.
The policy is reused on subsequent calls with the same path and access level.

The same command works from inside **devpod** — `VAULT_ADDR` is already set there
to `http://vault.vault.svc.cluster.local:8200`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `failed to open /vault/data/vault.db: permission denied` | Ensure `runAsUser: 0` is set in the StatefulSet, or add an init container to chown the PVC |
| `connection refused` on `VAULT_ADDR` | Check NodePort with `kubectl get svc -n vault`; or run `./scripts/port-forward.sh` |
| Vault sealed after pod restart | Expected — run `./scripts/verify.sh` to unseal via API |
| devpod `code tunnel` not found | Rebuild the devpod image; ensure the VS Code CLI download succeeded during `docker build` |
| devpod workspace empty after pod restart | The workspace volume is `emptyDir` — re-clone the repo into `~/workspace` after each pod restart |

