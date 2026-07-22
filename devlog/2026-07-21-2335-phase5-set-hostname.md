---
date: 2026-07-21
session: phase5-set-hostname
project: baseline-setup
related:
  - plans/baseline-decomposition.md
  - decisions/0004-contract-refinements.md
  - app-fleet-control PR#36
  - meta-ai-dev PR#112
  - baseline-setup PR#13
  - [[2026-07-21-2236-phases-2-4-and-plan-review]]
status: in-progress
---

## Goal
Execute Phase 5 of the `baseline-decomposition` migration — give `baseline-bluefin`'s `set-hostname` command a new home as `fleet set-hostname` in `app-fleet-control` — then record the result in the plan.

## Context
- Continuing from [[2026-07-21-2236-phases-2-4-and-plan-review]]: Phases 1–4 shipped, Phase 5 and Phase 6 both unblocked and order-independent; picked Phase 5 (small, independent) per the plan's own guidance and a direct question to the user.
- `baseline-bluefin`'s `cmd_set_hostname` was the reference semantics (its own ADR 0004): `hostnamectl set-hostname` is mandatory, Tailscale device-name sync is best-effort and never fails the command.

## What we did
- Read `baseline-bluefin/baseline-bluefin.sh`'s `cmd_set_hostname` (lines 916–942) as the semantics reference before writing anything new.
- Surveyed `app-fleet-control`'s `cli.py` (Typer app, ~7000 lines) for the closest existing pattern — landed on the `subprocess.run` + local-`import shutil` idiom already used throughout the file, not the async SSH `operations.py` path (that's for remote hosts; this is a local-machine op).
- Added `fleet set-hostname <name>` as a plain top-level command (not nested under `control-node` — it isn't a policy mutation) in `src/fleet_control/cli.py`, plus 8 new tests in `tests/test_cli.py` (empty-hostname guard, hostnamectl failure, no-tailscale-installed success, tailscale-installed-but-not-running, sync success, sync failure treated as non-fatal, `tailscale status` timeout, `--help` output) — `app-fleet-control` PR#36.
- Documented the new command in `meta-ai-dev/skills/fleet/SKILL.md`'s command table — `meta-ai-dev` PR#112.
- Updated this repo's plan Status section to record Phase 5 as implemented-but-unmerged, explicit that it graduates to "shipped" only once both PRs land — `baseline-setup` PR#13.

## Decisions
- Placed `set-hostname` at the top level of the `fleet` CLI rather than under `control-node app` — every other `control_node_app` command (`fetch-recovery-key`, `bootstrap`, …) does control-node bootstrap/DR/policy work, but `set-hostname` touches neither the policy repo nor SSH; it's a local-machine identity op any fleet-managed host could plausibly run, so it doesn't belong grouped with control-node-specific concerns.
- Kept Tailscale sync failure (missing binary, daemon not running, `tailscale set` erroring) as a warning with exit 0, matching `baseline-bluefin`'s ADR 0004 exactly, because `hostnamectl` succeeding is the actual state change the caller cares about — a Tailscale hiccup shouldn't make a script treat the hostname change as failed.
- Recorded the plan's Phase 5 status line as "implemented, PRs open" rather than "shipped" — the prior session's post-Phase-4 review explicitly flagged stale progress claims as a recurring failure mode, so this session wrote the more conservative claim up front instead of fixing it after the fact.

## What worked
- `app-fleet-control`'s existing `_derive_lxc_ip` tests (`tests/test_cli.py`) were a ready-made template for mocking `cli_mod.subprocess.run` by branching on `cmd[0]`/`cmd[:2]` — writing the 8 new `set-hostname` tests took one pass, no iteration needed to get the mocking pattern right.
- Isolating each of the three touched repos (`app-fleet-control`, `meta-ai-dev` — both backlog-loop-allowlisted — and `baseline-setup` itself) in its own worktree/branch *before* the first edit, this time by discipline rather than by the previous session's after-the-fact catch: `git status` clean-check → `git worktree add` (or `EnterWorktree` for the primary repo) → edit → test → commit → push → draft PR, repeated three times with zero cross-contamination.

## What didn't work
- Made the mistake this session started with: edited `app-fleet-control/src/fleet_control/cli.py` and `tests/test_cli.py` directly in the live checkout before isolating, because the initial focus was on understanding the CLI's existing patterns rather than on the isolation step itself. Caught it via a `git status` check immediately after the edits (before running anything else) — recovered cleanly with `git stash push -u -- <the two files>` → `git worktree add` → `git stash pop` inside the new worktree, no data at risk since nothing else was dirty. The `[[2026-07-21-2236-phases-2-4-and-plan-review]]` session already logged the same category of near-miss (a devlog written outside a worktree); this time it was the actual code edit, which is a more serious instance of the same discipline gap.
- The `app-fleet-control` worktree's `.venv` needed `uv sync --all-extras` (plain `uv sync` alone left `ruamel.yaml` and the test deps unresolved) before `pytest`/`ruff` would run — cost one extra round-trip to diagnose.

## Open / next
- Review `app-fleet-control` PR#36, `meta-ai-dev` PR#112, and `baseline-setup` PR#13 (`/code-review`, per this repo's convention of gating every shipped step) and merge — immediate next step this same session.
- Once all three merge, the plan's Phase 5 status line needs one more edit: "implemented, PRs open" → "shipped", with merge SHAs/dates. Don't let that update lag, per the same-session discipline this entry itself is modeling.
- Phase 6 (the picker + apply engine) is next after Phase 5 fully lands — see the plan's Status section for the concrete C1/C3 contract guidance to build against from the start.
- Per this repo's `CLAUDE.md`, the migration stays out of every `BACKLOG.md` — no backlog items added or swept this session.
- Git hygiene deferred to session close, after the merge/PR work below completes.
