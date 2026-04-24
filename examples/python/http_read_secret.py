#!/usr/bin/env python3
import requests

from common import get_vault_env, print_secret


def main() -> int:
    vault_addr, vault_token = get_vault_env()
    base_url = vault_addr.rstrip("/")
    url = f"{base_url}/v1/secret/data/demo"
    headers = {"X-Vault-Token": vault_token}

    read_resp = requests.get(url, headers=headers, timeout=10)
    read_resp.raise_for_status()

    data = read_resp.json()["data"]["data"]
    print_secret(data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
