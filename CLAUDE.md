# baseline-setup

> **Category:** baseline (the generic layer every machine gets) — see `~/code/meta-ai-dev/decisions/0003-repo-taxonomy-by-type.md`.

<!--
Thin per-project stub. General dev practices are inherited LIVE from ~/code/CLAUDE.md
(-> meta-ai-dev/dev-practices.md) via Claude Code's up-tree CLAUDE.md walk — do NOT duplicate them here.
-->

The **orchestrator** for machine bring-up: runs the other baseline layers in order and holds
**no layer logic of its own**. If a change here starts doing shell wiring, package installs,
or dconf work, it belongs in `baseline-shell` / `baseline-apps` / `baseline-desktop` instead —
that boundary is the whole point of the repo.

## Stack

- POSIX-ish bash (`set -euo pipefail`) + **`python3`** (TOML manifest/selection parsing, ADR 0004 D1). `git` and `bw` (transitively, via `baseline-access`) are the other prerequisites. A truly minimal LXC without python3 has it ensured by the provision path.
- `baseline-setup.sh` (entry point) + `lib/manifest.sh` (C2 manifest + C4 selection-file I/O), `lib/apply.sh` (the apply engine + static layer roster), `lib/gum-bootstrap.sh` (checksum-verified `gum` fetch), `lib/picker.sh` (the interactive checklist).

## Build / run / test

- `tests/run` — the full bats suite (vendored `bats.d/`, **not** a submodule; copied from `baseline-apps`'s harness). Unit tests (`tests/unit/`) source `lib/*.sh` directly; integration tests (`tests/integration/`) exec `baseline-setup.sh` as a real subprocess with `git` mocked (`tests/helpers/mocks.bash`) and every layer's installer replaced by a logging stub (`tests/fixtures/repos/`) — nothing touches the network or a real machine.
- `shellcheck baseline-setup.sh lib/*.sh` — clean is the bar, not aspirational.
- The interactive gum picker itself (`lib/picker.sh`'s `picker_layer`/`run_picker`) is **not** exercised by the suite — it needs a real TTY + `gum` binary. Keep its logic in terms of the pure, unit-tested `lib/manifest.sh` functions (`resolve_needs`, `detect_conflicts`, `visible_component_ids`, …) rather than growing untested bespoke logic there.

## Current state

**Phase 6 shipped:** the picker + apply engine exist and are tested. What each doc still covers:

| Path | Role |
|---|---|
| `ARCHITECTURE.md` | **Read first.** Every stage, what it does, skip rules, the platform contract, invariants |
| `decisions/0001-baseline-layer-decomposition.md` | Why the monolith is being decomposed; the layer table; the founding decision for this repo |
| `decisions/0002-multi-distro-multi-de.md` | Multi-distro/multi-DE as a constraint on every layer; reverses 0001's Q5 detection answer |
| `decisions/0003-component-tui-and-manifest-contract.md` | Component picker (gum) over per-layer manifests; single apply engine |
| `plans/baseline-decomposition.md` | The executable how — decomposition map, test-migration table, 8 phases, deletion gate |

`baseline-bluefin` is still live and fully functional, untouched by the migration until Phase 7's
cutover checklist passes. See `plans/baseline-decomposition.md`'s **Status** section for
current phase-by-phase state — don't duplicate it here, it goes stale fast.

## Non-negotiables

- **Multi-distro, multi-DE, headless-first.** Debian/Fedora/Arch/SUSE + atomic variants;
  GNOME/KDE/Cosmic as peers; **no desktop** is the most common case. Graphical layers detect
  and skip — never fail — on headless targets.
- **Detection is a contract, not a copy.** `baseline-shell/platform.sh` exports
  `PLATFORM_FAMILY` / `PLATFORM_PKG` / `PLATFORM_ATOMIC` / `PLATFORM_GUI` / `PLATFORM_DE`.
  Consumers source it. Reimplementing a probe locally is the drift this design exists to stop.
- **The picker renders manifests; it never hardcodes components.** A layer's components live in
  that layer's `manifest.toml`. A component id written into `baseline-setup` is the monolith
  reforming in the menu — catch it in review. One apply engine; the TUI is only a front-end
  ([`decisions/0003-component-tui-and-manifest-contract.md`](decisions/0003-component-tui-and-manifest-contract.md)).
- **Unsupported degrades, never crashes.** A new distro must never be a prerequisite for
  bootstrapping a machine at all.

## Notes

- **Private today; the plan calls for flipping to public once Phase 6's code lands.** The design
  reasoning: the front-door one-liner should be auditable on a pinned tag before being piped into
  a shell. When it flips: repo **names** only, never values — same discipline as
  `baseline-access`. (Confirm with the operator before actually flipping visibility — a public
  GitHub repo is not quietly reversible.)
- **The migration is deliberately not in any `BACKLOG.md`.** Four repos involved
  (`meta-ai-dev`, `workspace-homelab`, `app-fleet-control`, `baseline-shell`) are in the
  backlog-loop allowlist; this work is driven by hand, not by an autonomous leg. Don't
  "helpfully" add backlog items for it.
- Phase-specific ADRs (orchestrator internals, `baseline-apps` profiles) get written when
  those phases are built — not up front against code that doesn't exist.
