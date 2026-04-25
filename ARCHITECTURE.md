# Architecture

## Overview

This repository deploys HashiCorp Vault on Kubernetes and provides a UBI 9 development container (`devpod`) that can reach Vault over in-cluster DNS. Secret write/read examples are driven entirely by environment variables and work identically from the host machine or from inside `devpod`.

## Component Diagram

```
Host machine
  │
  │  NodePort :32200  OR  kubectl port-forward :8200
  ▼
┌──────────────────────────────────────────────────────────────────┐
│ Kubernetes cluster  (namespace: vault)                           │
│                                                                  │
│  ┌──────────────────────────────────┐                            │
│  │  StatefulSet: vault              │                            │
│  │  Pod: vault-0                    │                            │
│  │  Image: hashicorp/vault:1.18     │                            │
│  │                                  │                            │
│  │  /vault/config/vault.hcl ◄── ConfigMap: vault-config         │
│  │  /vault/data             ◄── PVC: vault-data (1Gi)           │
│  │                                  │                            │
│  │  :8200 (API)                     │                            │
│  │  :8201 (cluster)                 │                            │
│  └──────────┬───────────────────────┘                            │
│             │                                                    │
│  ┌──────────▼───────────────────────┐                            │
│  │  Service: vault  (NodePort)      │ ← host access              │
│  │  port 8200 → nodePort 32200      │                            │
│  └──────────────────────────────────┘                            │
│  ┌──────────────────────────────────┐                            │
│  │  Service: vault-headless         │ ← stable pod DNS           │
│  │  vault-0.vault-headless.vault    │   (used by raft)           │
│  │  .svc.cluster.local              │                            │
│  └──────────────────────────────────┘                            │
│                                                                  │
│  ┌──────────────────────────────────┐                            │
│  │  Deployment: devpod              │                            │
│  │  Image: devpod:latest (UBI 9)    │                            │
│  │  User: z4701038-779 (uid 7401038)│                            │
│  │                                  │                            │
│  │  VAULT_ADDR=http://vault.vault   │                            │
│  │  .svc.cluster.local:8200         │                            │
│  │                                  │                            │
│  │  Tools: python3, uv, vault CLI,  │                            │
│  │         VS Code CLI (code)       │                            │
│  └──────────────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────┘
```

## Key Components

### Vault StatefulSet

| Property | Value |
|---|---|
| Image | `hashicorp/vault:1.18` |
| Storage backend | Raft (integrated) |
| Data path | `/vault/data` (mounted from PVC) |
| Config path | `/vault/config/vault.hcl` (mounted from ConfigMap) |
| API port | 8200 |
| Cluster port | 8201 |
| Run as | uid 0 (root) on local clusters to avoid PVC permission issues |

### Vault Service

Two services are created:

| Service | Type | Purpose |
|---|---|---|
| `vault` | NodePort (32200) | Accessible from the host machine |
| `vault-headless` | ClusterIP/None | Stable pod DNS for raft; in-cluster clients |

In-cluster DNS for API access: `http://vault.vault.svc.cluster.local:8200`

### PVC (vault-data)

- `ReadWriteOnce`, 1 Gi
- Bound to the StatefulSet; survives pod deletion and restart
- Vault must be unsealed after each pod restart (raft data is intact; seal is in-memory)

### devpod

| Property | Value |
|---|---|
| Base image | `registry.access.redhat.com/ubi9/ubi:latest` |
| Default user | `z4701038-779` (uid 7401038) |
| Python | Latest available via UBI 9 AppStream |
| Package manager | `uv` (installed to `/usr/local/bin`) |
| VS Code remote | `code` CLI — supports `code tunnel` for remote VS Code sessions |
| Vault CLI | Installed for running examples inside the pod |
| Entrypoint | `sleep infinity` — keeps pod alive for VS Code attachment |

## Vault Storage: Raft

Vault uses its integrated Raft storage backend (no external Consul required). Raft data lives in a PVC so it persists across pod restarts. Vault always starts **sealed** after a restart; the operator must unseal it using the unseal keys before secrets are accessible.

## Authentication

All examples authenticate with the Vault root token stored in `.vault/init.json` (git-ignored). The token is passed via the `VAULT_TOKEN` environment variable; no `docker exec` or `kubectl exec` is used for secret operations.

## Secret Path

All examples write and read from the KV v2 path `secret/demo` (full API path: `secret/data/demo`).

## Host Access Options

| Method | When to use |
|---|---|
| NodePort `:32200` | Cluster node IP is directly reachable from the host (bare metal, k3s) |
| `scripts/port-forward.sh` | Node IP not reachable (minikube, kind); forwards `localhost:8200 → vault:8200` |

## File Layout

```
k8s/
  vault/
    namespace.yaml      # vault namespace
    configmap.yaml      # vault.hcl embedded as ConfigMap
    pvc.yaml            # 1Gi PVC for raft data
    statefulset.yaml    # single-replica StatefulSet
    service.yaml        # NodePort :32200 + headless service
  devpod/
    Dockerfile          # UBI 9 + python + uv + vault CLI + VS Code CLI
    deployment.yaml     # single-replica Deployment, user z4701038-779
    service.yaml        # headless service for pod DNS
examples/
  bash/
    write_secret.sh     # curl-based; reads VAULT_ADDR + VAULT_TOKEN
    read_secret.sh
    write_read_secret.sh
  python/
    common.py           # shared env-var helpers
    hvac_write_secret.py
    hvac_read_secret.py
    hvac_write_read.py
    http_write_secret.py
    http_read_secret.py
    http_write_read.py
scripts/
  port-forward.sh       # kubectl port-forward vault:8200 → localhost:8200
  verify.sh             # end-to-end smoke test (unseal + write + read)
```
