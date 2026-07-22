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
status: done
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
- Ran an independent `code-reviewer` agent against PR#36's diff before merging (this repo's `/code-review` convention). It found two real gaps and both got fixed in a follow-up commit before merge: a missing `hostnamectl` binary raised an unhandled `FileNotFoundError` instead of degrading cleanly (fixed: caught, clean exit 1, matching this file's own convention on every other `subprocess.run` call site); the Tailscale sync used a bare `sudo`, which can hang forever on an interactive password prompt when passwordless sudo isn't configured for `tailscale` — fixed by switching to `sudo -n` plus a timeout, matching `_derive_lxc_ip`'s existing `sudo -n` idiom in the same file. Also added the 4 tests the review flagged as missing (`FileNotFoundError` path, empty-stderr message branch, probe `OSError` arm, non-interactive-sudo argv) — 12 tests total, full suite 1335/1335 green.
- Documented the new command in `meta-ai-dev/skills/fleet/SKILL.md`'s command table — `meta-ai-dev` PR#112.
- Merged all three: `app-fleet-control` PR#36 (`d5002b8`), `meta-ai-dev` PR#112 (`20d742a`), `baseline-setup` PR#13 — the last updated in place to record "shipped" with both merge SHAs instead of the earlier "implemented, PRs open" placeholder.

## Decisions
- Placed `set-hostname` at the top level of the `fleet` CLI rather than under `control-node app` — every other `control_node_app` command (`fetch-recovery-key`, `bootstrap`, …) does control-node bootstrap/DR/policy work, but `set-hostname` touches neither the policy repo nor SSH; it's a local-machine identity op any fleet-managed host could plausibly run, so it doesn't belong grouped with control-node-specific concerns.
- Kept Tailscale sync failure (missing binary, daemon not running, `tailscale set` erroring) as a warning with exit 0, matching `baseline-bluefin`'s ADR 0004 exactly, because `hostnamectl` succeeding is the actual state change the caller cares about — a Tailscale hiccup shouldn't make a script treat the hostname change as failed.
- Recorded the plan's Phase 5 status line as "implemented, PRs open" rather than "shipped" — the prior session's post-Phase-4 review explicitly flagged stale progress claims as a recurring failure mode, so this session wrote the more conservative claim up front instead of fixing it after the fact.

## What worked
- `app-fleet-control`'s existing `_derive_lxc_ip` tests (`tests/test_cli.py`) were a ready-made template for mocking `cli_mod.subprocess.run` by branching on `cmd[0]`/`cmd[:2]` — writing the 8 new `set-hostname` tests took one pass, no iteration needed to get the mocking pattern right.
- Isolating each of the three touched repos (`app-fleet-control`, `meta-ai-dev` — both backlog-loop-allowlisted — and `baseline-setup` itself) in its own worktree/branch *before* the first edit, this time by discipline rather than by the previous session's after-the-fact catch: `git status` clean-check → `git worktree add` (or `EnterWorktree` for the primary repo) → edit → test → commit → push → draft PR, repeated three times with zero cross-contamination.
- The `/code-review` gate earned its keep a fourth phase running: an independent `code-reviewer` agent found the `FileNotFoundError` and bare-`sudo`-hang issues on a diff that had already passed a full green test suite and manual read-through — neither was something the writing pass would have caught without deliberately hunting for "what happens when the assumed-present binary isn't there" and "what happens under non-interactive automation," which is exactly the blind spot a second independent pass exists to cover.

## What didn't work
- Made the mistake this session started with: edited `app-fleet-control/src/fleet_control/cli.py` and `tests/test_cli.py` directly in the live checkout before isolating, because the initial focus was on understanding the CLI's existing patterns rather than on the isolation step itself. Caught it via a `git status` check immediately after the edits (before running anything else) — recovered cleanly with `git stash push -u -- <the two files>` → `git worktree add` → `git stash pop` inside the new worktree, no data at risk since nothing else was dirty. The `[[2026-07-21-2236-phases-2-4-and-plan-review]]` session already logged the same category of near-miss (a devlog written outside a worktree); this time it was the actual code edit, which is a more serious instance of the same discipline gap.
- The `app-fleet-control` worktree's `.venv` needed `uv sync --all-extras` (plain `uv sync` alone left `ruamel.yaml` and the test deps unresolved) before `pytest`/`ruff` would run — cost one extra round-trip to diagnose.

## Open / next
- Phase 5 is fully shipped: `app-fleet-control` PR#36, `meta-ai-dev` PR#112, and `baseline-setup` PR#13 all merged; the plan's Status section reflects it.
- Phase 6 (the picker + apply engine) is next — see the plan's Status section for the concrete C1/C3 contract guidance (the `platform.sh` sourcing idiom, batch-failure resilience) to build against from the start.
- Per this repo's `CLAUDE.md`, the migration stays out of every `BACKLOG.md` — no backlog items added or swept this session.
- Git hygiene: run at session close across all three touched repos (`app-fleet-control`, `meta-ai-dev`, `baseline-setup`) to prune the now-merged `phase5-set-hostname` worktrees/branches.
