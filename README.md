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

**Start here:** [`ARCHITECTURE.md`](ARCHITECTURE.md) — what each stage does, in order, with the
skip rules and invariants.

| Document | Answers |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | What each stage does and why the boundaries sit where they do |
| [`decisions/0001`](decisions/0001-baseline-layer-decomposition.md) | Why decompose the monolith at all |
| [`decisions/0002`](decisions/0002-multi-distro-multi-de.md) | Multi-distro/multi-DE; the platform-detection contract |
| [`decisions/0003`](decisions/0003-component-tui-and-manifest-contract.md) | The component picker (gum TUI) + per-layer manifest contract |
| [`plans/baseline-decomposition.md`](plans/baseline-decomposition.md) | The migration sequence and its deletion gate |

## The layers it orchestrates

| Repo | Layer | Scope |
|---|---|---|
| `app-fleet-control` + `content-fleet-policy` | L0 | SSH policy, hostname + Tailscale sync, recovery key |
| `baseline-access` | L0.5 | **Public.** Zero-credential git-readiness |
| **`baseline-setup`** *(here)* | orchestrator | Runs the others in order |
| `baseline-shell` | L1a | Shell/dotfiles/tmux + **all CLI tooling** + `platform.sh` |
| `baseline-apps` | L1b | **GUI apps only** — flatpak-primary. Skips itself when headless |
| `baseline-desktop` | L1c | Per-DE session state (GNOME dconf; KDE/Cosmic archives). Skips itself when headless |
| `meta-ai-dev` | L2 | Claude carry-down, skills, statusline |

## Planned front door

```bash
git clone <baseline-setup> && ./baseline-setup.sh          # gum picker → choose components → install
./baseline-setup.sh --profile laptop --yes                # headless/fleet: replay a saved selection
```

Bare run launches a **gum** checklist of the components each layer *declares* in its own
`manifest.toml` (grouped by layer, GUI components auto-hidden when headless). Your picks are
written to a selection file and handed to a single apply engine that runs the stages in order:
`baseline-access` → clone private repos over SSH → `baseline-shell` → `baseline-apps` →
`baseline-desktop` → `meta-ai-dev`. The `--profile … --yes` path feeds the *same* engine with no
TUI, so interactive and automated installs can't drift. `baseline-setup` never hardcodes what a
layer contains — it renders manifests ([`decisions/0003`](decisions/0003-component-tui-and-manifest-contract.md)).

**Every layer is multi-distro and multi-DE.** Debian, Fedora, Arch, SUSE, and atomic/ostree
variants; GNOME, KDE, and Cosmic as peers — and **no desktop at all** as the most common case,
since most of the fleet is headless LXCs. Graphical layers detect and skip rather than fail.

Three properties are load-bearing:

- **The security gate is structural, not cryptographic.** Phase 1 is public and needs no
  credentials; everything past it requires the Bitwarden-derived GitHub key. There is no
  encrypted payload — that was considered and rejected as buying nothing over a private repo.
- **Fleet control-node promotion is explicit opt-in, never a default.**
  `fleet control-node bootstrap` makes a machine privileged (all services, can deploy to
  others). Right for a personal laptop, wrong for an LXC or throwaway box — those are enrolled
  with `fleet host add` from an existing control node instead.
- **Headless targets skip the graphical stages by detection, not by error.** A bring-up that
  dies partway through a flatpak call on a container is a bug, not a limitation.

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
