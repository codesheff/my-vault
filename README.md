# Local HashiCorp Vault (Docker Compose)

## Overview

This repository runs local HashiCorp Vault in non-dev mode using Docker Compose.

- Vault runs in server mode (not `-dev`), so you must initialize and unseal it.
- Data is persisted on `./vault/data` and survives container restarts.
- The container runs as `user: "0:0"` to avoid common bind-mount permission issues on Linux hosts.
- Secret write/read examples in this guide are host-based and do not use `docker exec`.

## Prerequisites

- Docker Engine
- Docker Compose v2 (`docker compose`)
- `curl` and `jq` (for Bash example)
- `uv` (for Python examples)

## Start Vault

```bash
docker compose up -d
docker compose ps
```

Vault endpoint: `http://127.0.0.1:8200`

## Initialize and Unseal (One-Time Init)

1. Initialize Vault (one time):

```bash
docker compose exec vault sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault operator init -format=json'
```

2. Save the JSON output securely (contains unseal keys and root token).

3. Unseal with any 3 unique unseal keys:

```bash
docker compose exec vault sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault operator unseal <UNSEAL_KEY_1>'
docker compose exec vault sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault operator unseal <UNSEAL_KEY_2>'
docker compose exec vault sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault operator unseal <UNSEAL_KEY_3>'
```

4. Export host-side auth variables for all examples:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=<INITIAL_ROOT_TOKEN>
```

5. Ensure KV v2 is enabled at `secret/`:

```bash
curl -sS \
	-H "X-Vault-Token: ${VAULT_TOKEN}" \
	"${VAULT_ADDR}/v1/sys/mounts" | jq -e '."secret/".type == "kv" and ."secret/".options.version == "2"' \
	|| curl -sS -X POST \
		-H "X-Vault-Token: ${VAULT_TOKEN}" \
		-H "Content-Type: application/json" \
		-d '{"type":"kv","options":{"version":"2"}}' \
		"${VAULT_ADDR}/v1/sys/mounts/secret"
```

## Bash Example (Host-Based)

Write secret:

```bash
bash examples/bash/write_secret.sh
```

Read secret:

```bash
bash examples/bash/read_secret.sh
```

Expected output:

```text
username=alice
password=correct-horse-battery-staple
```

## Python Setup with uv (Required)

```bash
[ -d .venv ] || uv venv .venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

## Python Example 1: hvac Client

Write secret:

```bash
python examples/python/hvac_write_secret.py
```

Read secret:

```bash
python examples/python/hvac_read_secret.py
```

Expected output:

```text
username=alice
password=correct-horse-battery-staple
```

## Python Example 2: Raw HTTP API

Write secret:

```bash
python examples/python/http_write_secret.py
```

Read secret:

```bash
python examples/python/http_read_secret.py
```

Expected output:

```text
username=alice
password=correct-horse-battery-staple
```

## Verify Persistence Across Restarts

1. Restart Vault:

```bash
docker compose down
docker compose up -d
```

2. Confirm Vault is initialized and sealed after restart:

```bash
docker compose exec vault sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200; vault status'
```

3. Unseal again with 3 keys.

4. Re-run any host-based read example (Bash or Python). If secret values are still returned, persistence is confirmed.

## Temporary Dev Notes

- Local bootstrap artifacts can be kept in `.vault/` for this temporary environment.
- `.vault/` is git-ignored in this repository.
- For non-temporary environments, do not keep unseal keys or root tokens on disk.

## Troubleshooting

- If Vault fails with `failed to open /vault/data/vault.db: permission denied`, keep `user: "0:0"` in `docker-compose.yml`.

## Stop

```bash
docker compose down
```
