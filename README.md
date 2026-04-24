# Local HashiCorp Vault (Docker Compose)

## Overview

This repository runs a local, non-dev-mode HashiCorp Vault using Docker Compose.

- Vault runs in server mode (not `-dev`), so you must initialize and unseal it.
- Data is persisted on a host-mounted volume (`./vault/data`) and survives container restarts.
- The container is configured to run as root (`user: "0:0"`) to avoid local bind-mount permission issues on some Linux hosts.
- This setup is for local development and testing only. TLS is disabled intentionally for local use.

## Prerequisites

- Docker Engine
- Docker Compose v2 (`docker compose`)

## Start Vault

```bash
docker compose up -d
docker compose ps
```

Vault listens on `http://127.0.0.1:8200`.

## Initialize and Unseal (Production-Like Flow)

1. Initialize Vault once:

```bash
docker compose exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault operator init'
```

2. Save the output securely. It contains:
- 5 unseal keys
- 1 initial root token

3. Unseal Vault with any 3 unique unseal keys:

```bash
docker compose exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal'
docker compose exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal'
docker compose exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal'
```

4. Login with the initial root token:

```bash
docker compose exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=<INITIAL_ROOT_TOKEN> vault vault token lookup
```

## Write and Read a Secret (KV v2)

1. Enable KV v2 at `secret/` (one time):

```bash
docker compose exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=<INITIAL_ROOT_TOKEN> vault vault secrets enable -path=secret kv-v2
```

2. Write a secret:

```bash
docker compose exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=<INITIAL_ROOT_TOKEN> vault vault kv put secret/demo username=alice password='correct-horse-battery-staple'
```

3. Read the secret:

```bash
docker compose exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=<INITIAL_ROOT_TOKEN> vault vault kv get secret/demo
```

## Verify Persistence Across Restarts

1. Stop and start Vault:

```bash
docker compose down
docker compose up -d
```

2. Confirm status (should be initialized but sealed):

```bash
docker compose exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault status'
```

3. Unseal again with 3 unseal keys, then read the same secret:

```bash
docker compose exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=<INITIAL_ROOT_TOKEN> vault vault kv get secret/demo
```

If the secret is still present, persistence is working.

## Temporary Dev Notes

- For convenience, local bootstrap artifacts can be kept under `.vault/` during development.
- `.vault/` is already ignored by git in this repository.
- In non-temporary environments, do not keep unseal keys or root tokens on disk.

## Troubleshooting

- If Vault restarts with `failed to open /vault/data/vault.db: permission denied`, ensure the compose service keeps `user: "0:0"` as configured in this repo.

## Stop

```bash
docker compose down
```
