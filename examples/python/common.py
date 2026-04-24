#!/usr/bin/env python3
import os
import sys
from typing import Tuple


SECRET_MOUNT = "secret"
SECRET_PATH = "demo"
SECRET_DATA = {
    "username": "alice",
    "password": "correct-horse-battery-staple",
}


def get_vault_env() -> Tuple[str, str]:
    vault_addr = os.environ.get("VAULT_ADDR")
    vault_token = os.environ.get("VAULT_TOKEN")

    if not vault_addr or not vault_token:
        print(
            "Set VAULT_ADDR and VAULT_TOKEN before running this script.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    return vault_addr, vault_token


def print_secret(data: dict) -> None:
    print(f"username={data['username']}")
    print(f"password={data['password']}")
