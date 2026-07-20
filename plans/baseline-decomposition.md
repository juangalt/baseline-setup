# Plan — decompose `baseline-bluefin` into the layered `baseline-*` family

> **Why:** [`../decisions/0001-baseline-layer-decomposition.md`](../decisions/0001-baseline-layer-decomposition.md)
> (the decomposition) and [`../decisions/0002-multi-distro-multi-de.md`](../decisions/0002-multi-distro-multi-de.md)
> (multi-distro/multi-DE + the platform contract). Stage-by-stage guide:
> [`../ARCHITECTURE.md`](../ARCHITECTURE.md).
> This file is the executable *how*: per-repo diffs, phase order, and the deletion gate.
>
> **Not loop-tracked.** Deliberately kept out of every `BACKLOG.md` — the operator drives
> these phases by hand. Four of the repos involved (`meta-ai-dev`, `workspace-homelab`,
> `app-fleet-control`, `baseline-shell`) are in the backlog-loop allowlist, so backlog
> items here would be claimable by an autonomous leg; that is not wanted for this work.

## Status

- Design complete 2026-07-20. Q1 resolved (same key — see below); Q2–Q9 resolved in ADR 0001.
- Scope broadened the same day by ADR 0002: **every layer is multi-distro and multi-DE**, and
  Q5's "duplicate the detection probe" answer is **reversed** in favour of a shared
  `platform.sh` contract owned by `baseline-shell`. Phases 2/3/4/6 below reflect this.
- **No phase has been executed yet.** `baseline-bluefin` is untouched and fully functional.

## Resolved: the Bitwarden item-name question

The GitHub service key appeared under two names — `ssh-access service key: github`
(`baseline-github`, `baseline-bluefin`) and `fleet-policy:keys/service/github`
(`content-fleet-policy/policy.yaml`, deployed to hosts as `~/.ssh/svc-github`).
Fingerprint comparison on 2026-07-20: **the same key.**

→ Standardize on `fleet-policy:keys/service/github`. Fleet's schema *requires* the
`fleet-policy:` prefix on every reference, so it is the only name that can win. One-line
change in `baseline-access` plus its bats fixture; lands in Phase 1. Item names are not
secrets (the repo is public and already carries one), but the change is deliberate.

## Decomposition map

Confirmed against the live trees, not just the design sketch.

| `baseline-bluefin` artifact | New home | Notes |
|---|---|---|
| `gnome/*.ini` + `DCONF_MAP` + selective dconf engine (`install_dconf`, `push_dconf`, `classify_dconf_drift`, `_generate_updated_dconf_ini`) | `baseline-desktop` | The **engine** moves, not just the inis |
| `home/dot_gitconfig` | `baseline-shell` | Becomes idempotent `git config --global` calls, not a tracked file. Hardcoded `/home/linuxbrew/...` path becomes `command -v gh` |
| `home/dot_bashrc.d/hermes-agent`, `private_fish/conf.d/hermes-agent.fish` | `baseline-shell` | New `hermes-aliases.sh`, sourced from `bashrc.sh`/`zshrc.sh`; fish parity optional |
| `home/dot_{bash,zsh}*`, `starship.toml`, stock fish config | **DROP** | `baseline-shell`'s marker-block + symlink wiring already covers these; its `starship.toml` is the host-aware superset of bluefin's static copy (verified by diff) |
| `home/private_dot_claude/*` | **DROP** | L2 territory; `meta-ai-dev/install.sh` already owns statusline/settings |
| `autostart/com.seafile.Client.desktop` | `baseline-desktop` `autostart/` | DE-neutral XDG autostart, applied by its install command |
| `install github-key` + git identity | **DELETE** | `baseline-access` already implements a richer version (known_hosts, identity, verify) |
| `recovery-key` | **DELETE** | `fleet control-node fetch-recovery-key` already exists |
| `set-hostname` + Tailscale live-sync (bluefin ADR 0004) | `app-fleet-control` | New subcommand + pytest |
| `Brewfile` | Split three ways | CLI formulae → `baseline-shell/apps/Brewfile.cli`; flatpak/cask/vscode → `baseline-apps` profiles; `uv "fleet-control"`, `chezmoi`, `bitwarden-cli` → dropped (owned by fleet bootstrap / baseline-access) |
| `DISPLAYLINK.md`, `BLUEFIN-USB-INSTALL.md` | `workspace-homelab/machines/` laptop spoke | Docs, not code — the workspace drift guard does not trip |
| `tests/` (bats, vendored `bats.d/`) | Per-target rewrites — see table below | |
| `decisions/0001–0004` | Stay in the archived repo | Successors written where responsibilities land, each with a provenance line |

## Test migration

| bluefin test | Disposition |
|---|---|
| `test_github`, `test_login` | **Delete** — `baseline-access`'s richer suite already covers the delegated behavior |
| `test_recovery_key` | **Delete** — fleet owns the behavior and its own pytest suite |
| `test_set_hostname` | Reimplement as pytest in `app-fleet-control/tests/` beside the new subcommand |
| `test_install_dconf`, `test_push_dconf` | Port to `baseline-desktop/tests/` (bats; harness copied from `baseline-github` — vendored `bats.d/`, `helpers/mocks.bash`, `tests/run`, **no submodules**) |
| `test_packages`, `test_push_packages` | Split: brew/CLI cases → `baseline-shell`; flatpak cases → `baseline-apps` |
| `test_dotfiles`, `test_push_dotfiles` | **Delete** with chezmoi; `baseline-shell` keeps `bootstrap.sh --dry-run` + existing tests |
| `test_status`, `test_commands` | Each target repo gets its own status/integration test |

Real work — the mocks assume bluefin's function names. Budget it inside each phase, not as
a trailing cleanup.

## Phases

Each phase is one PR-shaped unit and passes `/code-review` before merge, per workspace
convention.

### Phase 1 — rename `baseline-github` → `baseline-access`

Follow `meta-ai-dev/references/repo-rename-procedure.md` exactly (clean tree, discovery grep,
`gh repo rename`, remote set-url, path-keyed Claude cache). **Behavior unchanged.** Tag
`v0.2.0`; update its own CLAUDE/README titles and the meta repo's repo lists.

**Immediately verify** the new HTTPS clone URL *and* that GitHub's redirect keeps the old
`v0.1.0` raw-URL one-liner alive — this is the only public entry point, and the
unbootstrappable-window risk lives here and nowhere else.

Also lands: the Bitwarden item-name standardization (above). Keep `print_next_step`'s
bluefin pointer until Phase 6.

### Phase 2 — `baseline-shell` absorb

- `git config --global` wiring in `bootstrap.sh`: identity guard, gh credential helper via
  `command -v gh`, `github:` insteadOf.
- `hermes-aliases.sh`, sourced from both rc entrypoints.
- **`platform.sh`** — the shared detection contract (`PLATFORM_FAMILY`, `PLATFORM_PKG`,
  `PLATFORM_ATOMIC`, `PLATFORM_GUI`, `PLATFORM_DE`) per
  [`../decisions/0002-multi-distro-multi-de.md`](../decisions/0002-multi-distro-multi-de.md).
  **Lands first in this phase** — Phases 3, 4 and 6 all consume it.
- `apps/Brewfile.cli` brew branch in `apps/baseline.sh`, dispatched on `PLATFORM_ATOMIC` /
  `PLATFORM_PKG`: atomic → brew (ublue images ship it), formulae only (the current apt roster
  equivalents plus bluefin's dev formulae: atuin, bat, eza, fd, gh, uv, terraform, oci-cli, …);
  else the existing apt/dnf/pacman path, extended to `zypper`.
- Document the **guaranteed roster** and assert it on **every** package-manager branch — not
  just the two, or the roster stops being a guarantee.
- Tests, including a **headless** path (a Debian LXC is the representative fleet target, not
  the laptop) and a `PLATFORM_FAMILY=unknown` degrade-cleanly case.

Nothing here touches `baseline-bluefin` yet.

### Phase 3 — `baseline-desktop`

Port the dconf engine + `gnome/*.ini` + `DCONF_MAP` into a new `baseline-desktop.sh` CLI
(`status` / `install` / `push`, GNOME branch). Add `autostart/` handling. Write
`decisions/0001` (ownership matrix + restore order). Rewrite `CLAUDE.md`/`README.md` for
the mixed data classification and add the rebase runbook. Port the two dconf bats files +
harness. Gate the whole layer on `PLATFORM_GUI` / `PLATFORM_DE` — headless or
untracked-DE targets **skip and report**, never error.

### Phase 4 — `baseline-apps`

Scaffold via the `new-repo` skill (`--category baseline`). Profiles
(`common` / `laptop` / `handheld` stub); explicit `--profile <name>` persisted to
`~/.config/baseline-apps/profile`. Flatpak install/status/push, diffing against the
selected profile only. Per-family **native residue** check (`rpm-ostree status --json`,
`apt-mark showmanual`, `pacman -Qe`, …) warning on drift both ways — the reconstruction gap
is not rpm-ostree-specific. Structural no-formula lint. Gate on `PLATFORM_GUI`. Tests.

### Phase 5 — fleet

`set-hostname` + Tailscale live-sync as a small `app-fleet-control` subcommand (semantics
from bluefin ADR 0004: `hostnamectl` then `tailscale set --hostname`, non-fatal
degradation) + pytest. Update the fleet skill's `SKILL.md` command table.

### Phase 6 — `baseline-setup`

One orchestrator script, phase order per ADR 0001, no layer logic of its own; the
private-clone step is the structural security gate. Sources `baseline-shell/platform.sh` to
decide which stages apply (headless targets skip L1b/L1c). Bats tests (mock git/bw). Update
`baseline-access`'s `print_next_step` to point here.

**Flip this repo to public** (`gh repo edit juangalt/baseline-setup --visibility public`) as
part of this phase — it is private today because it carries only the migration plan. Once
public, the discipline is `baseline-access`'s: repo *names* only, never values.

### Phase 7 — laptop cutover validation *(the gate for deletion)*

On the Bluefin laptop: run `baseline-setup` end-to-end, then the parity checklist — every
`baseline-bluefin.sh` command maps to a green equivalent:

| bluefin command | Replacement |
|---|---|
| `status` | per-repo statuses |
| `install github-key` | `baseline-access` |
| `install packages` | `baseline-shell` CLI branch + `baseline-apps` profile |
| `install dconf` | `baseline-desktop` |
| `push *` | the new homes |
| `set-hostname` | fleet |
| `recovery-key` | fleet |

**Only when all pass** does Phase 8 proceed.

### Phase 8 — tombstone + doc sweep

- `baseline-bluefin`: README/CLAUDE replaced by a pointer table to the new homes (the
  `service-claude-oauth-refresh` tombstone precedent); `gh repo archive`; drop from the
  arrakis `~/code` mirror at leisure.
- Doc sweep: `meta-ai-dev` (`decisions/0003` current-repos table, `references/layered-bringup.md`,
  any repo lists), `workspace-homelab` (new laptop machine spoke absorbing
  DISPLAYLINK/USB-install), supersedes-with-pointer notes on bluefin's four ADRs.
- Devlog entry. Devlogs are never rewritten.

## Risks

1. **Breaking the only zero-credential entry point during the rename** → do Phase 1 in one
   sitting; verify old-URL redirects (clone + raw) immediately; retag.
2. **SaveDesktop import clobbering curated GNOME dconf** → GNOME gets no archive by
   default; blob-first/code-last restore order documented in `baseline-desktop/decisions/0001`.
3. **CLI/GUI package drift** (a script assumes `rg`, the host got its packages via the other
   path) → single guaranteed roster asserted on both install branches; profile format
   structurally excludes formulae.
4. **Secrets in SaveDesktop tars in git history** → private repo + mandatory `tar -tzf`
   review step retained; skip GOA/keyring categories.
5. **Laptop unbootstrappable mid-migration** → bluefin stays live and untouched until the
   Phase 7 checklist passes; all moves are additive.

## Verification

Per phase: repo test suite green (`tests/run` bats / pytest / `bootstrap.sh --dry-run`);
rename regression grep (only `*/devlog/*` may still match old names). After Phase 8, a
workspace-wide `rg baseline-bluefin ~/code` returns only devlogs, the tombstone, and
historical ADR text.

**Final proof of the whole point:** rebase the laptop to Aurora, run `baseline-desktop`
restore + `baseline-apps --profile laptop`, confirm the shell/dev environment is intact and
the KDE session restored; rebase back, `install gnome` restores the curated dconf state.
