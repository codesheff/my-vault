#!/usr/bin/env python3
import subprocess
import sys


def main() -> int:
    # Compatibility wrapper for split read/write scripts.
    subprocess.run([sys.executable, "examples/python/hvac_write_secret.py"], check=True)
    subprocess.run([sys.executable, "examples/python/hvac_read_secret.py"], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
