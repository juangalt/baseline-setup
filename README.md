# baseline-setup

> **Category:** baseline (the generic layer every machine gets — shell + apps) — see `~/code/meta-ai-dev/decisions/0003-repo-taxonomy-by-type.md`.

**L1 of the fleet-setup layers** (see meta-ai-dev/decisions/0002...). Idempotent base env for interactive/coding machines.

## Quickstart
```bash
git clone github:juangalt/baseline-setup ~/code/baseline-setup
~/code/baseline-setup/bootstrap.sh --apps   # --dry-run available
```

Run order on a fresh machine: L0 `fleet` enroll → **L1 `baseline-setup/bootstrap.sh`** → L2 `meta-ai-dev/install.sh` → (dev-primaries only) L3 ...

## What's here (stub)
| File | Role |
| `bootstrap.sh` | Idempotent shell wiring (symlinks, rc blocks, zsh, chsh). `--apps`, `--dry-run`, `--help`. (Implement per baseline-shell/bootstrap.sh; migrate legacy blocks if any.) |
| `apps/baseline.sh` | (optional) General CLI baseline. |
| `role.sh` | Host detection → FLEET_ROLE / DEV_* (loose contract with L2 statusline). |
| `CLAUDE.md`, `README.md`, `decisions/` | Per 0003 + this template. |

## Design notes
- Host-varying by `$(hostname -s)`.
- Cross-layer contract: `role.sh` (L1) exports `FLEET_ROLE` etc.; L2 degrades gracefully.

See sibling `baseline-shell` for the full implementation of `bootstrap.sh`, `role.sh`, etc.
