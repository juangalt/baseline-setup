# baseline-setup

> **Category:** baseline (the generic layer every machine gets) — see `~/code/meta-ai-dev/decisions/0003-repo-taxonomy-by-type.md`.

**The single front door for bringing up a machine.** Orchestration only — this repo holds no
layer logic of its own; it runs the other layers in order.

> **Status: design recorded, orchestrator not yet built.** Today this repo carries the
> decomposition ADR and migration plan. The `baseline-setup.sh` script lands in Phase 6.
> Until then, bring-up still runs through `baseline-bluefin`, which remains fully functional.

## Why this exists

`baseline-bluefin` was a single-image monolith — shell dotfiles, CLI packages, GNOME dconf,
GitHub key, git identity, hostname and Tailscale sync in one repo scoped to one image on one
laptop. That blocked rebasing between Universal Blue siblings, and meant an LXC wanting only
shell + CLI tools couldn't consume it. It is being decomposed into single-responsibility
layers, with this repo as the orchestrator.

Full rationale: [`decisions/0001-baseline-layer-decomposition.md`](decisions/0001-baseline-layer-decomposition.md).
Executable how: [`plans/baseline-decomposition.md`](plans/baseline-decomposition.md).

## The layers it orchestrates

| Repo | Layer | Scope |
|---|---|---|
| `app-fleet-control` + `content-fleet-policy` | L0 | SSH policy, hostname + Tailscale sync, recovery key |
| `baseline-access` | L0.5 | **Public.** Zero-credential git-readiness |
| **`baseline-setup`** *(here)* | orchestrator | Runs the others in order |
| `baseline-shell` | L1 | Shell/dotfiles/tmux + **all CLI tooling** |
| `baseline-desktop` | L1 | Per-DE session state (GNOME dconf; KDE/Cosmic archives) |
| `baseline-apps` | L1 | **GUI apps only** — flatpak-primary, brew casks secondary |
| `meta-ai-dev` | L2 | Claude carry-down, skills, statusline |

## Planned front door

```bash
git clone <baseline-setup> && ./baseline-setup.sh
```

Phase order: `baseline-access` → clone private repos over SSH → `baseline-shell` →
`baseline-apps` → `baseline-desktop` → `meta-ai-dev`.

Two properties are load-bearing:

- **The security gate is structural, not cryptographic.** Phase 1 is public and needs no
  credentials; everything past it requires the Bitwarden-derived GitHub key. There is no
  encrypted payload — that was considered and rejected as buying nothing over a private repo.
- **Fleet control-node promotion is explicit opt-in, never a default.**
  `fleet control-node bootstrap` makes a machine privileged (all services, can deploy to
  others). Right for a personal laptop, wrong for an LXC or throwaway box — those are enrolled
  with `fleet host add` from an existing control node instead.

## Build / run / test

Nothing executable yet. When `baseline-setup.sh` lands it ships with a bats suite (mocking
`git`/`bw`) following `baseline-access`'s vendored-harness pattern.

## Notes

- **Currently private; goes public at Phase 6.** The design calls for this repo to be public
  so its one-liner is auditable on a pinned tag before being piped into a shell — the same
  property that makes `baseline-access` public. It stays private while it holds only the
  migration plan, which describes fleet internals with no offsetting benefit to publishing
  early.
- Once public, the discipline is the same as `baseline-access`: repo **names** only, never
  values.
