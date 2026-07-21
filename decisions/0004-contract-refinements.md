# 0004 — contract refinements from the pre-implementation plan review

- **Status:** accepted
- **Date:** 2026-07-20
- **Refines:** [`0003`](0003-component-tui-and-manifest-contract.md) (the C1–C5 contracts) and the
  plan's [`../plans/baseline-decomposition.md`](../plans/baseline-decomposition.md) appendix. Does
  not overturn any 0001–0003 decision; it closes gaps they left open.
- **Prompted by:** an adversarial quality/precision review of the plan (2026-07-20) that found the
  contract layer read as complete but left the highest-frequency runtime questions unanswered.

## Context

The plan was reviewed against the ADRs and the live repo trees before any code was written. The
factual claims held up, but the review surfaced ~a dozen decisions a Phase-6 implementer would
otherwise make ad hoc and bake into a "stable interface" that is expensive to change later. This ADR
records the resolutions so they are decided *once*, in the open, with their rejected alternatives.

## Decisions

### D1 — Manifest/selection format stays TOML; `python3` is the parser dependency

`manifest.toml` and `selected.toml` remain TOML, parsed with `python3` (`tomllib`, or `tomli` on
<3.11). `python3` joins the bootstrap prerequisites.

- **Rejected — a flat, shell-native format parsed by a vendored helper.** Zero new dependency and it
  satisfied the "no deps beyond git" line, but it trades a one-line stdlib call for a hand-maintained
  parser and a bespoke format. `python3` is present on effectively every fleet host (the workspace
  already leans on it — `inventory.py`, `backlog.py`).
- **Rejected — bootstrap `yq`.** Reuses the gum pattern, but the *standalone installer* path (an
  operator running `bootstrap.sh` directly) would not have it unless every layer bootstraps it too.
- **Consequence:** `CLAUDE.md`'s "no runtime deps beyond git" is amended to "git + python3". The one
  edge — a truly minimal LXC without `python3` — is handled by the provision path ensuring it, and is
  noted as manual residue. Each layer's installer reads its own manifest for its `default` set via the
  same `python3` dependency (the `default` flags are the single source; installers never duplicate the
  list in code).

### D2 — GNOME first; KDE/Cosmic SaveDesktop deferred

Phase 3 builds only the GNOME dconf branch. The KDE/Cosmic SaveDesktop save/restore wiring becomes an
explicit **post-migration follow-up**, not a migration phase.

- **Rejected — build SaveDesktop now.** The operator runs GNOME today; KDE/Cosmic are hypothetical
  future rebases, and SaveDesktop is a GUI flatpak whose CLI is weak — building its automation
  speculatively risks throwaway work.
- **Rejected — drop SaveDesktop entirely.** Contradicts `baseline-desktop/decisions/0001`, which
  deliberately reasoned KDE/Cosmic into SaveDesktop; the ownership matrix stays valid — deferring the
  *build* does not invalidate the *design*.
- **Consequence:** the plan's "final proof" is a GNOME dconf round-trip (rebase away and back to
  Bluefin/GNOME), which proves the core value on its own. Interim KDE story is the scaffold's manual
  `tar -tzf` + `verify.sh` via the SaveDesktop GUI. Risk-4's "retained review step" is reworded to
  "when SaveDesktop lands."

### D3 — The old Bitwarden item is retained through Phase 8

The GitHub key stays reachable under its old name (`ssh-access service key: github`) until the Phase 8
tombstone, then is deleted. `baseline-access` uses `fleet-policy:keys/service/github`.

- **Rejected — delete the old item at Phase 1.** Would force re-pinning the public one-liner *and*
  touching `baseline-bluefin` simultaneously, breaking the "bluefin stays live and untouched"
  invariant the whole additive-migration safety story rests on.
- **Consequence:** a harmless temporary duplicate (same key value, two BWS entries). The script is
  renamed `baseline-github.sh` → `baseline-access.sh` at `v0.2.0`; `v0.1.0`'s raw path is immutable,
  so the bluefin-era one-liner keeps resolving until tombstone; Phase 1 re-pins the README one-liner to
  `v0.2.0` and its Done-when runs the pinned *old* one-liner end-to-end, not just a URL check.

### D4 — Selection is install-only, with two-way toggles for the files-we-own class

The apply engine **never auto-removes system state**. A component's removal behavior is set by which
class it is in:

| Class | Examples | On deselect |
|---|---|---|
| **Files we own**, on/off is an operator preference | shell-default (`chsh`), autostart `.desktop`, config symlinks | **Removed** — the installer un-does it (marker/conditional-source it owns) |
| **System-installed / captured** | CLI packages, flatpaks, dconf keys | **Left in place** — never auto-removed |

The picker marks install-only components so unticking one *after* it is installed warns "won't be
removed" rather than silently misleading.

- **Rejected — pure add-only (no removal anywhere).** Simplest and safest, but a checklist that can
  never uncheck anything is a UX lie for the cheap, safe, baseline-owned toggles.
- **Rejected — full reconcile (machine matches ticks exactly, incl. uninstalling packages/resetting
  dconf).** The most "honest" reproducibility but the largest and most dangerous surface — it can nuke
  hand-installed things and "reset a dconf key" is not even well-defined.
- **Boundary rationale:** the cut is the recreate-from-code vs system-state line the workspace already
  draws (`meta-ai-dev/decisions/0007`); it is not arbitrary.
- **Refinement (currently unused):** a file-we-own whose desirability is determined by *another
  installed tool* rather than an operator preference should **self-guard on that tool's presence**
  instead of being a toggle. This is guidance for future components; the instance that raised it
  (Hermes) is dropped — see D4a.
- **Consequence:** `selected.toml` records the last *applied* selection = intent. For toggle
  components tick-state equals actual state; for install-only components it records intent, not a
  presence guarantee. The guaranteed CLI roster is **non-selectable** (always installed); only extra
  CLI tiers are components.

### D4a — Hermes is not part of the baseline system

The bluefin Hermes shell hooks (`home/dot_bashrc.d/hermes-agent`, `private_fish/conf.d/hermes-agent.fish`)
are **dropped**, not moved. Hermes is a service/agent concern (it lives on specific agent hosts via
`service-friday` and friends), not something every machine's shell layer should carry.

- **Rejected — move to `baseline-shell` as a component (or as an always-sourced self-guarding file).**
  Both keep an agent-framework concern in the universal baseline layer that most targets never run.
  Cleaner to draw the line at "baseline shell tooling," which Hermes is not.
- **Consequence:** the decomposition map row moves from "→ `baseline-shell`" to **DROP**, joining
  `home/private_dot_claude/*`. Nothing in `baseline-*` references Hermes.

### D5 — L2 (`meta-ai-dev`) is a single opt-in pseudo-component

`meta-ai-dev` appears in the picker as one opt-in entry (default-on for interactive/coding hosts,
off for headless/throwaway) that maps to a bare `meta-ai-dev/install.sh`. It is **exempt from the C2/C3
manifest/`--components` contract** but is selection-visible and recorded in `selected.toml`.

- **Rejected — give it a real manifest with sub-components** (skills/statusline/carry-down separately).
  Its `install.sh` is not built for partial installs; forcing granularity is scope creep into another
  repo. L2 is genuinely all-or-nothing today.
- **Consequence:** ARCHITECTURE's "L2 skippable by flag" is reconciled to this pseudo-component model.

### D6 — The layer roster lives in `baseline-setup`; manifests carry only components

`baseline-setup` holds a small static roster mapping each layer → its entry-point script → its stage.
Manifests declare components only.

- **Rejected — a `[layer]` header in each manifest + repo-scan discovery.** More "manifest-driven" but
  adds discovery complexity for a set of five stable, slow-changing repos.
- **Invariant-2 clarification:** invariant 2 forbids `baseline-setup` knowing a layer's component
  *contents*; it does **not** forbid knowing the *list of layers and their entry points* — that is the
  orchestrator's legitimate business (ARCHITECTURE already says it may know the stage order). The
  invariant wording is updated to say so.

### D7 — `de =` predicate; profile replay of hidden components is skip-and-report

C2's `requires` gains a `de = [...]` predicate (C1 already exports `PLATFORM_DE`), so per-DE components
gate correctly (a KDE box never shows `gnome-dconf`). Applying a saved selection whose component is
**hidden** on this host is **skip-and-report, never an error**.

- **Rejected — DE-dispatch stays installer-internal, picker shows one "desktop" component.** Leaves
  `selected.toml` recording components that never applied; less honest.
- **Rationale:** skip-and-report is forced by the fleet reality that one profile is applied across
  heterogeneous hosts, so "component hidden here" must be normal, not fatal.

### D8 — Empty selection skips the layer; "omitted → defaults" is the standalone path only

The engine always passes `--components`; an **empty** value → the layer is skipped and reported. The
"omitted flag → install the `default = true` set" behavior (C3) applies only when a human runs the
installer directly without `baseline-setup`. A missing layer table in `selected.toml` means *skip*,
never *defaults*.

- **Rationale:** makes "untick everything in this layer" mean what the operator expects instead of
  silently reinstalling defaults — the single most likely latent bug in the naive implementation.

### D9 — One source of truth for the app set; rename the machine-wide selector

`baseline-apps` drops its separate `~/.config/baseline-apps/profile` file — its app set lives only as
its components in `selected.toml`. `baseline-setup`'s machine-wide selector flag is renamed
`--profile` → **`--selection`** to remove the clash with `baseline-apps`' app-set `--profile`.

- **Rationale:** eliminates a "fifth hand-kept list" (the two files could disagree with no defined
  precedence) per the workspace's one-canonical-home spine, and disambiguates the overloaded flag.

## Consequences (rollup)

- The plan's appendix C1–C5, Phases 1–3/6, decomposition map, Bitwarden section, risk list, and
  several acceptance lines are updated to match these decisions (same PR).
- `needs`/`conflicts` resolution (C2): the picker auto-ticks `needs` transitively and refuses a
  selection with an active `conflict` (named-ids error); a `needs` pointing at a `requires`-hidden
  component is a selection error; standalone installer runs are best-effort and exempt.
- Two risks are added to the plan: migration-window dual ownership of the laptop's dotfiles (freeze
  bluefin's `push`/`install dotfiles` once Phase 7 begins), and `baseline-shell` being live
  fleet infrastructure (keep `--apps` as a working alias through Phase 8; gate Phase 2 on a real
  headless `--dry-run`; note the backlog-loop collision exposure).
