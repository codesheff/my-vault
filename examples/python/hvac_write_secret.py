#!/usr/bin/env python3
import hvac

from common import SECRET_DATA, SECRET_MOUNT, SECRET_PATH, get_vault_env


def main() -> int:
    vault_addr, vault_token = get_vault_env()
    client = hvac.Client(url=vault_addr, token=vault_token)

    client.secrets.kv.v2.create_or_update_secret(
        path=SECRET_PATH,
        secret=SECRET_DATA,
        mount_point=SECRET_MOUNT,
    )

    print("secret written: secret/demo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
