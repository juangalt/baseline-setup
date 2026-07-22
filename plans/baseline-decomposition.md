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
- ADR 0003 (same day) makes `baseline-setup` a **component picker over per-layer manifests**
  with one apply engine; the five interfaces this needs are specified in the **appendix**, and
  each phase carries a **Done when** acceptance line.
- Contract gaps closed by ADR 0004 (2026-07-20, from a pre-implementation review): TOML+python3,
  GNOME-first, install-only+toggle semantics, Hermes dropped, L2 pseudo-component, static layer
  roster, `de=` predicate, empty-selection, `--selection` rename. C1–C5 and the phases below reflect
  it.
- **Phase 1 shipped 2026-07-20** (`baseline-access` rename, tagged `v0.2.0`; Bitwarden item
  standardized to `fleet-policy:keys/service/github`, old item retained per D3).
- **Phase 2 shipped 2026-07-21** (`baseline-shell`
  [#15](https://github.com/juangalt/baseline-shell/pull/15), merged): `platform.sh` (C1),
  `manifest.toml` + `bootstrap.sh --components` (C2/C3, `zsh-default`/`tmux-starship`), git
  identity/credential wiring absorbed from `baseline-bluefin`, guaranteed-roster unconditional +
  zypper/brew branches in `apps/baseline.sh`. Mocked tests green; `--apps` kept as a no-op alias.
- **Phase 3 shipped 2026-07-21** (`baseline-desktop`
  [#4](https://github.com/juangalt/baseline-desktop/pull/4), merged): `baseline-desktop.sh`
  (`status`/`install`/`push`) ports the GNOME dconf engine + a new `gnome-autostart` component,
  `manifest.toml` (C2), `install --components` (C3), gated on `platform.sh`'s `PLATFORM_GUI`/
  `PLATFORM_DE`. `decisions/0001`, `CLAUDE.md`, `README.md` rewritten for the mixed
  recreate-from-code (GNOME)/restore-from-backup (KDE/Cosmic SaveDesktop) classification. 34/34
  tests green.
- **Phase 4 shipped 2026-07-21** (`baseline-apps`, a new repo,
  [#1](https://github.com/juangalt/baseline-apps/pull/1), merged): `baseline-apps.sh`
  (`status`/`install`/`push`), flatpak-primary, gated on `PLATFORM_GUI`. `manifest.toml` (C2):
  `profile-common`, `profile-laptop` (`needs profile-common`), `profile-handheld` (stub),
  `app-obsidian`; all install-only (ADR 0004 D4). Native residue check (per-family, both
  directions, starts empty) and a structural no-formula lint. `decisions/0001` records deferred
  scope (casks, VS Code extensions — assigned to this repo by the decomposition map but not in
  this phase's "Done when" line). 35/35 tests green. (Note: `new-repo --category baseline
  baseline-apps` doubled the prefix to `baseline-baseline-apps` — caught and renamed before the
  PR landed; pass just the base name after `--category`, not the already-prefixed one.)
- **Phase 5 shipped 2026-07-21** (`app-fleet-control`
  [#36](https://github.com/juangalt/app-fleet-control/pull/36), merged
  `d5002b8`; `meta-ai-dev` [#112](https://github.com/juangalt/meta-ai-dev/pull/112), merged
  `20d742a`): `fleet set-hostname <name>` as a plain top-level command (not nested under
  `control-node` — it's a local-machine op, not a policy mutation). `hostnamectl set-hostname` is
  the only mandatory step; Tailscale device-name sync (`tailscale set --hostname`) is best-effort
  and degrades to a warning — missing binary, daemon not running, or the `set` call failing all
  leave exit 0 — matching `baseline-bluefin`'s ADR 0004 semantics. A pre-merge code-review pass
  found two real gaps and both were fixed before merge: a missing `hostnamectl` binary raised an
  unhandled `FileNotFoundError` instead of degrading cleanly (now caught, exit 1, matching this
  file's own convention elsewhere); the Tailscale sync used a bare `sudo`, which can hang forever
  on an interactive password prompt when passwordless sudo isn't configured — switched to `sudo
  -n` + a timeout so it fails fast into the existing "run manually" warning instead. 12 tests
  (the original 8 plus 4 the review added: FileNotFoundError path, empty-stderr message branch,
  probe OSError arm, non-interactive-sudo argv); full suite 1335/1335 green; `ruff` clean.
  `meta-ai-dev`'s fleet `SKILL.md` command table updated.
- **Phase 6 shipped 2026-07-22** (`baseline-setup`
  [#14](https://github.com/juangalt/baseline-setup/pull/14), merged `dced154`): `baseline-setup.sh`
  + `lib/{manifest,apply,gum-bootstrap,picker}.sh` — the picker + apply engine over every layer's
  `manifest.toml`, per ADR 0003. `lib/manifest.sh` is the first generic implementation anywhere in
  the family of the `requires = {gui,atomic,family,de}` predicate (every sibling repo hand-codes
  its own per-component gate checks instead) — parameterized by path, since `baseline-setup` is the
  first consumer that reads *other* repos' manifests. `lib/apply.sh`'s `LAYER_ROSTER` is
  repo:script pairs only, never a component id (ADR 0004 D6), enforced by a grep-based test
  (invariant 2). `lib/gum-bootstrap.sh` pins a `gum` version + sha256 per Linux x86_64/arm64 asset
  and refuses anything unverified. `profiles/laptop.toml` is a real example committed selection.
  60 bats tests (vendored `bats.d/`, mocked `git` + every layer's installer, no network); `shellcheck`
  clean.
  **Two code-review passes before merge, both catching real bugs** (the second specifically
  verifying the first round's fixes didn't regress anything — worth doing given the size of this
  phase): round 1 found `--dry-run` threading through to the real apply engine, which needs cloned
  repos — on a fresh box it just reported "not cloned" for every layer and exited 1 instead of
  previewing; fixed by making `--selection … --dry-run` call the pure, clone-free `apply_plan()`
  and return before any bootstrap/clone/install (the interactive path still clones+picks, since
  rendering the checklist needs live manifests, but stops before invoking any installer). Round 1
  also added `validate_components` to `apply_layer` (an unknown/typo'd id now fails clearly
  instead of being silently swallowed as "not applicable on this platform") and type-safety on
  `requires.family`/`requires.de` (a bare string instead of a list no longer silently
  substring-matches). Round 2 found the yes/confirm gate was still checked *before* the new
  dry-run short-circuit (a pure preview could die "requires --yes" or prompt "Apply…? [y/N]"
  despite applying nothing) — reordered — and caught a test that had gone vacuous under round 1's
  redesign (asserted "already-cloned repo untouched" via `--dry-run`, which after round 1 no
  longer reaches the clone code at all) — rewritten against the real, non-dry path so it actually
  exercises what it claims to.
  `baseline-access` [#1](https://github.com/juangalt/baseline-access/pull/1), merged `72f25b2`:
  `print_next_step` now points most machines at `baseline-setup` (the Bluefin laptop still calls
  out `baseline-bluefin` explicitly, since it remains the validated path there until Phase 7).
  **`baseline-setup` stays private for now** — the plan calls for flipping it public once Phase 6's
  code lands, but that's deliberately being done as a separate follow-up rather than bundled into
  this phase, so a repo-visibility change doesn't ride along with a large, freshly-merged diff.
- **Phases 7–8 not started.** `baseline-bluefin` is untouched and fully functional. Cross-repo doc
  reconciliation (`meta-ai-dev`'s `layered-bringup.md`) is deliberately deferred to the phase that
  ships each change — rewriting it now would document a state that does not exist yet. Phase 8 is
  the catch-all sweep.
- **Next: Phase 7, laptop cutover validation** — the gate for Phase 8's deletion. Run
  `baseline-setup` end-to-end on the Bluefin laptop (this is also the first real exercise of the
  interactive gum picker path, which has no automated test coverage — see `lib/picker.sh`'s header
  comment), then the parity checklist against every `baseline-bluefin.sh` command. Flip
  `baseline-setup` to public before or during this phase (see above) — auditability matters most
  right when it's about to become the thing a laptop actually bootstraps from.

## Resolved: the Bitwarden item-name question

The GitHub service key appeared under two names — `ssh-access service key: github`
(`baseline-github`, `baseline-bluefin`) and `fleet-policy:keys/service/github`
(`content-fleet-policy/policy.yaml`, deployed to hosts as `~/.ssh/svc-github`).
Fingerprint comparison on 2026-07-20: **the same key.**

→ Standardize on `fleet-policy:keys/service/github`. Fleet's schema *requires* the
`fleet-policy:` prefix on every reference, so it is the only name that can win. One-line
change in `baseline-access` plus its bats fixture; lands in Phase 1. Item names are not
secrets (the repo is public and already carries one), but the change is deliberate.

**Lifecycle (ADR 0004 D3):** the *old* vault item `ssh-access service key: github` is **retained
until the Phase 8 tombstone**, then deleted — `baseline-bluefin` and the pinned `v0.1.0` one-liner
both still fetch the old name and stay live until then, so removing it early would break the live
zero-credential path. The script file is renamed `baseline-github.sh` → `baseline-access.sh` at
`v0.2.0`; `v0.1.0`'s raw path is immutable, so the bluefin-era one-liner keeps resolving.

## Decomposition map

Confirmed against the live trees, not just the design sketch.

| `baseline-bluefin` artifact | New home | Notes |
|---|---|---|
| `gnome/*.ini` + `DCONF_MAP` + selective dconf engine (`install_dconf`, `push_dconf`, `classify_dconf_drift`, `_generate_updated_dconf_ini`) | `baseline-desktop` | The **engine** moves, not just the inis |
| `home/dot_gitconfig` | `baseline-shell` | Becomes idempotent `git config --global` calls, not a tracked file. Hardcoded `/home/linuxbrew/...` path becomes `command -v gh` |
| `home/dot_bashrc.d/hermes-agent`, `private_fish/conf.d/hermes-agent.fish` | **DROP** (ADR 0004 D4a) | Hermes is a service/agent concern (agent hosts via `service-friday`), not baseline shell tooling — not carried by every machine |
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

Also lands (ADR 0004 D3): the Bitwarden item-name standardization to `fleet-policy:keys/service/github`
(the old item is **kept**, deleted only at Phase 8); rename the script `baseline-github.sh` →
`baseline-access.sh`; re-pin the README one-liner to `v0.2.0`. Keep `print_next_step`'s bluefin
pointer until Phase 6.

**Done when:** `git clone` of the new name works over HTTPS and SSH; **the pinned `v0.1.0`
one-liner still provisions a scratch box end-to-end** (redirect + old vault item both live), not just
resolves; `baseline-access` tests green; a workspace grep for `baseline-github` returns only devlogs,
archived plans, and deliberate "renamed from" historical mentions (`meta-ai-dev/BACKLOG.md` and the
b62 plans are in the rewrite worklist alongside the repo lists).

### Phase 2 — `baseline-shell` absorb

- `git config --global` wiring in `bootstrap.sh`: identity guard, gh credential helper via
  `command -v gh`, `github:` insteadOf.
- **`platform.sh`** — the shared detection contract (`PLATFORM_FAMILY`, `PLATFORM_PKG`,
  `PLATFORM_ATOMIC`, `PLATFORM_GUI`, `PLATFORM_DE`) per
  [`../decisions/0002-multi-distro-multi-de.md`](../decisions/0002-multi-distro-multi-de.md).
  **Lands first in this phase** — Phases 3, 4 and 6 all consume it.
- `apps/Brewfile.cli` brew branch in `apps/baseline.sh`, dispatched on `PLATFORM_ATOMIC` /
  `PLATFORM_PKG`: atomic → brew (ublue images ship it), formulae only (the current apt roster
  equivalents plus bluefin's dev formulae: atuin, bat, eza, fd, gh, uv, terraform, oci-cli, …);
  else the existing apt/dnf/pacman path, extended to `zypper`.
- Document the **guaranteed roster**, assert it on **every** package-manager branch, and mark it
  **non-selectable** (always installed — a component you could untick would void the guarantee; ADR
  0004 D4). Note `apps/baseline.sh` today `exit 1`s on an unknown package manager — the degrade-clean
  requirement is a deliberate **behavior change**, not a preserved one.
- Keep `--apps` as a working **alias** through Phase 8 (fleet bring-up, `layered-bringup.md`, and the
  provision handoff all call it today); gate this phase on a real headless `bootstrap.sh --dry-run` on
  a Debian LXC.
- Tests, including a **headless** path (a Debian LXC is the representative fleet target, not
  the laptop) and a `PLATFORM_FAMILY=unknown` degrade-cleanly case.
- **`manifest.toml`** declaring this layer's selectable components (zsh-default, tmux+starship,
  optional shell integrations, extra CLI tiers, …; the guaranteed roster is non-selectable) and
  **`bootstrap.sh --components <ids>`** consuming
  them, per contract **C2**/**C3** in the appendix.

Nothing here touches `baseline-bluefin` yet.

**Done when:** `source platform.sh` on a Debian LXC, an atomic desktop, and a
`PLATFORM_FAMILY=unknown` stub each exports a sane 5-var set (C1); `bootstrap.sh --components
zsh-default,tmux-starship` installs exactly those and nothing else; `bootstrap.sh` with no
`--components` still installs the `default = true` set; the guaranteed roster is asserted on
every package-manager branch; headless + unknown-family tests green.

### Phase 3 — `baseline-desktop`

Clone the existing `baseline-desktop` repo into `~/code` (already scaffolded on GitHub — private).
Port the dconf engine + `gnome/*.ini` + `DCONF_MAP` into a new `baseline-desktop.sh` CLI
(`status` / `install` / `push`, GNOME branch). Add `autostart/` handling. Write
`decisions/0001` (ownership matrix + restore order). Rewrite `CLAUDE.md`/`README.md` for
the mixed data classification and add the rebase runbook. Port the two dconf bats files +
harness. Gate the whole layer on `PLATFORM_GUI` / `PLATFORM_DE` — headless or
untracked-DE targets **skip and report**, never error. Ship `manifest.toml` (per-DE restore,
autostart entries; all `requires = { gui = true }`) + `--components`, per contract C2/C3.

**Done when:** `baseline-desktop.sh install --components gnome-dconf` reproduces the curated
keys on a GNOME box; the same on a headless LXC exits 0 with a "skipped: no GUI" line and
changes nothing; ported dconf bats green; `CLAUDE.md`/`README.md` state the mixed
classification.

### Phase 4 — `baseline-apps`

Scaffold via the `new-repo` skill (`--category baseline`). Named app-sets
(`common` / `laptop` / `handheld` stub) expressed as manifest components — the selected set lives in
`selected.toml`, **not** a separate `~/.config/baseline-apps/profile` file (ADR 0004 D9). Flatpak
install/status/push, diffing against the selected components only. Per-family **native residue** check (`rpm-ostree status --json`,
`apt-mark showmanual`, `pacman -Qe`, …) warning on drift both ways — the reconstruction gap
is not rpm-ostree-specific. Structural no-formula lint. Gate on `PLATFORM_GUI`. Ship
`manifest.toml` (profiles + notable individual apps as components, all `requires = { gui = true }`)
+ `--components`, per contract C2/C3. Tests.

**Done when:** the laptop app-set installs its flatpaks and no formulae (lint proves it); the
native-residue check reports drift both ways on at least two package managers (mocked pm output); a
headless run is a clean no-op. The app-set lives only as components in `selected.toml` — no separate
`~/.config/baseline-apps/profile` file (ADR 0004 D9).

### Phase 5 — fleet

`set-hostname` + Tailscale live-sync as a small `app-fleet-control` subcommand (semantics
from bluefin ADR 0004: `hostnamectl` then `tailscale set --hostname`, non-fatal
degradation) + pytest. Update the fleet skill's `SKILL.md` command table.

**Done when:** the subcommand sets hostname + Tailscale name idempotently, degrades non-fatally
when Tailscale is absent, and its pytest is green; `SKILL.md` documents it.

### Phase 6 — `baseline-setup` (the picker + apply engine)

Per ADR 0003, `baseline-setup` becomes a component picker over per-layer manifests, not a
bare sequencer. No hardcoded layer knowledge; the private-clone step is the structural
security gate. Sources `baseline-shell/platform.sh` to gate stages and components (headless
skips L1b/L1c and hides `requires.gui` components). Build, in order:

- **Bootstrap prefix** — print the L0 setup guidance (both paths; no enrolment), ensure `python3`
  is present (parser dep, ADR 0004 D1), `git clone` the public `baseline-access` repo and **run its
  script**, then clone the private repos into `~/code/<repo>` (clone-if-absent; leave an existing
  checkout untouched — no `git pull` against a possibly-dirty dev tree — and report which path was
  taken). All mandatory prerequisites, not components.
- **Manifest reader** — parse each layer's `manifest.toml`, filter components through
  `platform.sh`.
- **Apply engine** — invoke each layer's installer with `--components <ids>` in stage order.
  The single install path; both front-ends below feed it.
- **gum picker** — checklist grouped by layer, seeded from `default` + any existing
  selection; writes `~/.config/baseline-setup/selected.toml` (or a named `--selection`). gum
  fetched checksum-verified, interactive path only.
- **Non-interactive front-end** — `--selection <name> --yes` runs the apply engine with no gum,
  no TTY (flag renamed from `--profile`, ADR 0004 D9). No TTY and no `--selection` → clear error.
- **L2 handling** — `meta-ai-dev` is one opt-in pseudo-component (ADR 0004 D5): default-on for
  interactive/coding hosts, invoked as a bare `install.sh`, recorded in `selected.toml`, exempt from
  the `--components` contract.
- Bats tests: mock manifests, `--selection --yes` golden run, empty-selection skip, headless
  auto-hide, non-TTY
  guard, and git/bw mocks for the clone step. Update `baseline-access`'s `print_next_step` to
  point here.

Build against contracts **C2–C5** and the runtime sequence in the appendix.

**Done when:** on a fresh box, bare `baseline-setup` clones the private repos, shows a picker with
GUI components hidden on headless, and applies the selection in stage order; the *same* selection
replayed via `--selection … --yes` produces an **identical apply plan** (the engine's ordered
installer+components invocation list compares equal) with no gum and no TTY; a non-TTY run with no
`--selection` errors with the `--selection` hint instead of hanging; a fully-deselected layer is
skipped (not defaulted); a component id grepped for in `baseline-setup`'s own source **outside
`profiles/` and `tests/fixtures/`** returns nothing (invariant 2 — the layer roster legitimately
lives here, ADR 0004 D6).

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
| `install dotfiles` | `baseline-shell/bootstrap.sh` (rc blocks + `git config` wiring) |
| `install dconf` | `baseline-desktop` |
| `push packages` / `push dconf` | the new homes (shell/apps · desktop) |
| `push dotfiles` | **retired** — dropped with chezmoi, no new home |
| `set-hostname` | fleet |
| `recovery-key` | fleet |

**Only when all pass** does Phase 8 proceed.

### Known deferred items (carried into Phase 8)

Gaps documented in-repo during Phases 2–4, listed here once so Phase 8's sweep doesn't have to
rediscover them by re-reading three repos' `decisions/`/`devlog/`. None block Phase 5/6/7 — each
is either a real host-image edge case not yet hit, or explicitly out of the phase that shipped it.

- **`baseline-apps`:** no cask support (fonts, wallpapers — needs a brew-primary path parallel to
  `baseline-shell/apps/Brewfile.cli`'s atomic branch) and no VS Code extension install; both were
  in the original decomposition map's `flatpak/cask/vscode → baseline-apps` row but not in Phase
  4's "Done when" line (`decisions/0001`). zypper/SUSE native-residue check unimplemented (reports
  "not yet implemented," never guesses).
- **`baseline-shell`:** no supported install path for `starship` on non-brew platforms (apt/dnf/
  pacman/zypper) — the `tmux-starship` component symlinks `starship.toml` but only the atomic/brew
  branch's `Brewfile.cli` actually installs the binary.
- **`baseline-desktop`:** KDE/Cosmic SaveDesktop automation stays deferred per ADR 0004 D2 —
  `verify.sh` is still the only check for those archives; no `konsave`/`kwriteconfig`/RON-file
  backend built yet (design exists in `decisions/0001` "Extending to other DEs", build doesn't).

Sweep these into real work items (or explicitly drop them) at Phase 8, not silently — a documented
gap left undecided past the tombstone is the implicit-gap failure mode this repo's own design
principle warns against.

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
6. **Dual ownership of the laptop's dotfiles during the migration window** (ADR 0004 D4 context) →
   "additive" holds for repos, not for the shared `~/.bashrc`/`starship.toml` that *both* bluefin's
   chezmoi and the new `baseline-shell` manage on the one laptop. Interlock: once Phase 7 begins,
   freeze bluefin's `install dotfiles` / `push *` (state it in the plan and in bluefin's README
   banner at Phase 7 start).
7. **`baseline-shell` is live fleet infrastructure** → its `bootstrap.sh --apps` is the L1 step every
   LXC bring-up runs today, and the repo is backlog-loop-allowlisted. Keep `--apps` as a working alias
   through Phase 8; gate Phase 2 on a real headless `--dry-run`; accept (or pause) the loop-collision
   exposure on `baseline-shell` during Phase 2.

## Verification

Per phase: repo test suite green (`tests/run` bats / pytest / `bootstrap.sh --dry-run`);
rename regression grep (only `*/devlog/*` may still match old names). After Phase 8, a
workspace-wide `rg baseline-bluefin ~/code` returns only devlogs, the tombstone, and
historical ADR text.

**Final proof of the whole point (GNOME, per ADR 0004 D2):** rebase the laptop away from and back
to Bluefin/GNOME, run the shell + apps components, and confirm the shell/dev environment is intact and
`baseline-desktop install --components gnome-dconf` restores the curated dconf state. KDE/Cosmic
SaveDesktop restore is a **post-migration follow-up**, not part of this proof.

---

## Appendix — implementation contracts

Five contracts an implementer builds against. The *rationale* lives in the ADRs; this is the
concrete *shape*. They are stable interfaces — changing one is a breaking change to every
consumer named beside it.

### C1 — `platform.sh` (ADR 0002)

- **Home:** `baseline-shell` repo root. **Sourced, never executed;** sourcing has no side
  effects and is idempotent.
- **Exports:** `PLATFORM_FAMILY` (`debian`·`fedora`·`arch`·`suse`·`unknown`), `PLATFORM_PKG`
  (`apt`·`dnf`·`pacman`·`zypper`·`brew`·`none`), `PLATFORM_ATOMIC` (`1`/`0`), `PLATFORM_GUI`
  (`1`/`0`), `PLATFORM_DE` (`gnome`·`kde`·`cosmic`·`other`·`none`).
- **Degradation:** an unrecognized host sets `FAMILY=unknown`, `PKG=none`, and never errors —
  callers branch on the values, they don't assume detection succeeded.
- **Consumers:** `baseline-shell` (install branch), `baseline-apps`, `baseline-desktop`,
  `baseline-setup` (component gating).
- **Sourcing idiom (validated identically in Phases 2–4; `baseline-setup` should follow it too):**
  a consumer repo has no clone of `baseline-shell` of its own, so it sources the sibling repo's
  copy by the fleet's fixed `~/code/<repo>` layout — `PLATFORM_SH="${BASELINE_SHELL_PLATFORM_SH:-
  $HOME/code/baseline-shell/platform.sh}"` — overridable for tests/non-standard layouts. **All
  five vars are defaulted headless-safe *before* the conditional `[ -r "$PLATFORM_SH" ]` source**,
  not only in the "file missing" branch, and the source itself is guarded (`. "$PLATFORM_SH" ||
  warn …`) — a present-but-partial or failing `platform.sh` must degrade to headless rather than
  leaving a var unbound downstream under `set -u`, or aborting under `set -e`. A code-review pass
  caught exactly this gap in `baseline-apps.sh` before merge (PR #1) after `baseline-desktop.sh`
  (PR #4) had already established the pattern — worth getting right the first time in
  `baseline-setup` itself.

### C2 — `manifest.toml` (ADR 0003)

- **Home:** each consumable layer's repo root. **Metadata only — no install logic.**
- **Schema:** an array of `[[component]]` tables:

  | Field | Req | Meaning |
  |---|---|---|
  | `id` | ✓ | Stable key, unique within the layer, passed to the installer via C3 |
  | `label` | ✓ | Picker display text |
  | `desc` | | One-line help |
  | `default` | | `true` → ticked on first run (default `false`) |
  | `requires` | | Inline table of `platform.sh` predicates: `gui = true`, `atomic = true`, `family = ["debian","fedora"]`, **`de = ["gnome"]`** (ADR 0004 D7). All must hold or the component is **hidden**. Applying a saved selection whose component is hidden here = **skip-and-report**, never error |
  | `class` | | `toggle` (files-we-own; undone on deselect) or `install-only` (system-installed; never auto-removed). Default `install-only`. ADR 0004 D4 |
  | `needs` / `conflicts` | | Lists of other `id`s. Picker auto-ticks `needs` transitively, refuses a selection with an active `conflict` (named-ids error); a `needs` on a `requires`-hidden component is a selection error. Standalone runs are best-effort, exempt |

- **Consumer:** `baseline-setup` reads all manifests; nothing else needs to.

### C3 — installer `--components` contract

Every consumable layer's entry script honors:

- `--components <csv>` — install exactly these ids (this layer's namespace only). An **empty** value
  → do nothing, exit 0 (the engine skips a fully-deselected layer; ADR 0004 D8).
- **omitted** — install the `default = true` set. *Standalone path only* (a human running the installer
  directly); the engine always passes `--components`, never omits it.
- **unknown id** — exit non-zero listing the valid ids; never silently skip.
- **removal** — `toggle`-class undone when absent from a re-run's selection; `install-only` never
  auto-removed (ADR 0004 D4).
- `--dry-run` — print the plan, change nothing. Idempotent under every combination. Reads its own
  manifest via `python3` for the `default` set (never a duplicated in-code list).
- **One item's install failure doesn't abort the batch.** A component can list many individually
  installable things (`baseline-apps`'s `profile-laptop` is ~40 flatpak ids); an upstream rename/
  removal of one must not block every other item in that component *and every later component*
  from installing. Warn and continue, accumulate failures, exit non-zero at the end if any failed.
  Fixed in `baseline-apps.sh` per a code-review finding (PR #1, `flatpak install` was `die`-on-
  first-failure) — apply the same shape to any future multi-item installer, including the apply
  engine's own component-by-component loop in Phase 6.

### C4 — selection file `selected.toml`

- **Home:** `~/.config/baseline-setup/selected.toml` (the active machine's record), or a named
  `profiles/<name>.toml` (in the `baseline-setup` checkout) addressed by `--selection <name>` (error
  if absent; a `--selection` run copies it to `selected.toml` before applying). A **missing layer
  table means skip, never defaults** (ADR 0004 D8).
- **Format:** one table per layer, each with a `components` array of selected ids:

  ```toml
  [baseline-shell]
  components = ["zsh-default", "tmux-starship"]

  [baseline-apps]
  components = ["profile-laptop"]
  ```

- **Reproducibility:** the picker *writes* this file; the apply engine *reads* it. Every install —
  interactive or `--selection` — leaves one. It records the last *applied selection* = intent: for
  `toggle` components tick-state equals actual state; for `install-only`, intent not a presence
  guarantee (ADR 0004 D4). Satisfies `meta-ai-dev/decisions/0007`.

### C5 — `baseline-setup` layout & runtime sequence

```
baseline-setup.sh        # entry: arg parse + dispatch
lib/
  manifest.sh            # read + validate C2 manifests, resolve needs/conflicts
  picker.sh              # gum rendering → writes C4 selection
  apply.sh               # the apply engine (single install path)
  gum-bootstrap.sh       # checksum-verified gum fetch, interactive path only
profiles/                # optional committed named C4 selections
tests/{bats.d,fixtures}/ # vendored bats + mock manifests + platform stubs
```

**Runtime sequence (load-bearing ordering).** `platform.sh` lives in `baseline-shell`, which
is not on disk until the clone step — so the picker cannot run first:

0. **Print L0 guidance** — the concise control-node / fleet-host setup instructions
   (ARCHITECTURE § L0). Informational and non-blocking; `baseline-setup` performs **no**
   enrolment.
1. **Access** — ensure `python3` present; `git clone` the *public* `baseline-access` repo and **run
   its script** → GitHub key on disk, git-over-SSH works. Mandatory prerequisite, not a component.
2. **Clone** the private repos (`baseline-shell`, `-apps`, `-desktop`, `meta-ai-dev`) into
   `~/code/<repo>` — clone-if-absent, leave an existing checkout untouched (no `git pull`), report
   which. Mandatory, not a component.
3. **Source** `baseline-shell/platform.sh` (now present) — C1.
4. **Read** every manifest (via `python3`), filter each component through `platform.sh` — C2.
5. **Bootstrap gum** (checksum-verified, per-arch) — interactive path only; on fetch/checksum
   failure, hard error naming the `--selection … --yes` escape hatch. Skipped entirely when
   `--selection` is given.
6. **Select** — gum picker (writes C4) **or** load `--selection` (reads C4).
7. **Apply** — the engine invokes each layer's installer with its slice via C3, in the fixed
   `L1a → L1b → L1c → L2` stage order (L2 = the bare `install.sh` pseudo-component, D5).

L0 guidance, access, and clone are prerequisites, never selectable components — only L1+ layers
expose components. The picker changes *what* runs within a stage, never the stage sequence.
