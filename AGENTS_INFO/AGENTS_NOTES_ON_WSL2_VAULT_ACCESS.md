# WSL2 / kubectl.exe — Vault Access Notes

## Background

On Windows with Docker Desktop, `kubectl` inside WSL2 is a shell function that delegates to
`kubectl.exe` on the Windows side:

```
kubectl ()
{
    command kubectl.exe "$@"
}
```

This means `kubectl port-forward` binds the local port **on the Windows loopback**, not inside
WSL2.  Attempts to curl `http://127.0.0.1:<port>` from WSL2 will fail with connection refused,
even when the port-forward process appears to be running.

## How to reach Vault from WSL2

Use the WSL2 default-gateway IP (the Windows host) instead of `127.0.0.1`:

```bash
WIN_GW=$(ip route show default | awk '{print $3}')
export VAULT_ADDR=http://${WIN_GW}:8200
```

Then start the port-forward **with `--address 0.0.0.0`** so Windows binds on all interfaces
(making it reachable from WSL2):

```bash
kubectl.exe port-forward service/vault -n vault 8200:8200 --address=0.0.0.0 &
```

## Running verify.sh

```bash
export VAULT_ADDR=http://$(ip route show default | awk '{print $3}'):8200
./scripts/verify.sh
```

## What does NOT work on WSL2 + Docker Desktop kubectl

| Approach | Why it fails |
|---|---|
| `kubectl port-forward … & curl http://127.0.0.1:8200` | Port is bound on Windows loopback, not WSL2 loopback |
| `kubectl port-forward … 18200:8200` (alternate port) | Same issue — Windows holds both standard and alternate ports |
| Direct node/pod IP (`172.18.x.x`, `10.244.x.x`) | Kind/Docker network not routed to WSL2 eth0 |
| `nameserver` IP from `/etc/resolv.conf` | Not the Windows loopback — this is a WSL2 DNS proxy |

## Verified working combination (April 2026)

- Docker Desktop with kind cluster (`docker-desktop` context)
- `kubectl.exe port-forward service/vault -n vault 8200:8200 --address=0.0.0.0`
- `VAULT_ADDR=http://172.23.16.1:8200` (Windows gateway IP; may differ per machine)
- `./scripts/verify.sh` — all checks passed
