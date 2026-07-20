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

- POSIX shell. No runtime deps beyond `git` (and `bw` transitively, via `baseline-access`).
- `baseline-setup.sh` — **not yet written**; lands in Phase 6 of the migration plan.

## Build / run / test

- Nothing executable yet. The planned suite is bats with a vendored `bats.d/` (copy
  `baseline-access`'s harness pattern — vendored, **not** submodules), mocking `git`/`bw`.

## Current state

This repo currently carries **documentation only**:

| Path | Role |
|---|---|
| `decisions/0001-baseline-layer-decomposition.md` | Why the monolith is being decomposed; the layer table; the founding decision for this repo |
| `plans/baseline-decomposition.md` | The executable how — decomposition map, test-migration table, 8 phases, deletion gate |

`baseline-bluefin` is still live and fully functional; nothing has been migrated yet.

## Notes

- **Private today, public at Phase 6.** The design calls for this repo to be public so the
  front-door one-liner is auditable on a pinned tag before being piped into a shell. It stays
  private while it holds only the migration plan (fleet internals, no benefit to publishing
  early). When it flips: repo **names** only, never values — same discipline as
  `baseline-access`.
- **The migration is deliberately not in any `BACKLOG.md`.** Four repos involved
  (`meta-ai-dev`, `workspace-homelab`, `app-fleet-control`, `baseline-shell`) are in the
  backlog-loop allowlist; this work is driven by hand, not by an autonomous leg. Don't
  "helpfully" add backlog items for it.
- Phase-specific ADRs (orchestrator internals, `baseline-apps` profiles) get written when
  those phases are built — not up front against code that doesn't exist.
