#!/usr/bin/env python3
import hvac

from common import SECRET_MOUNT, SECRET_PATH, get_vault_env, print_secret


def main() -> int:
    vault_addr, vault_token = get_vault_env()
    client = hvac.Client(url=vault_addr, token=vault_token)

    result = client.secrets.kv.v2.read_secret_version(
        path=SECRET_PATH,
        mount_point=SECRET_MOUNT,
        raise_on_deleted_version=True,
    )
    data = result["data"]["data"]
    print_secret(data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
