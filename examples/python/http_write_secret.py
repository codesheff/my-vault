#!/usr/bin/env python3
import requests

from common import SECRET_DATA, get_vault_env


def main() -> int:
    vault_addr, vault_token = get_vault_env()
    base_url = vault_addr.rstrip("/")
    url = f"{base_url}/v1/secret/data/demo"
    headers = {"X-Vault-Token": vault_token}

    write_resp = requests.post(
        url,
        headers=headers,
        json={"data": SECRET_DATA},
        timeout=10,
    )
    write_resp.raise_for_status()

    print("secret written: secret/demo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
