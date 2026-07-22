---
date: 2026-07-22
session: phase6-picker-apply-engine
project: baseline-setup
related:
  - plans/baseline-decomposition.md
  - decisions/0003-component-tui-and-manifest-contract.md
  - decisions/0004-contract-refinements.md
  - baseline-setup PR#14
  - baseline-access PR#1
  - [[2026-07-21-2335-phase5-set-hostname]]
status: done
---

## Goal
Execute Phase 6 of the `baseline-decomposition` migration — give `baseline-setup` its first real code, a component picker + apply engine over every layer's `manifest.toml` — and land it.

## Context
- Continuing from [[2026-07-21-2335-phase5-set-hostname]]: Phases 1–5 shipped, Phase 6 was the only thing left before Phase 7 (laptop cutover validation).
- Before writing any code, forked a research pass over `baseline-shell`/`baseline-apps`/`baseline-desktop`'s actual shipped implementations (not just the plan's spec) — the C1 `platform.sh` sourcing idiom, the python3/`tomllib` manifest-parsing pattern, the dry-run threading convention, and the batch-failure-tolerant install loop, all confirmed byte-for-byte identical across the three sibling repos.

## What we did
- `baseline-setup.sh` (entry point) + `lib/manifest.sh`, `lib/apply.sh`, `lib/gum-bootstrap.sh`, `lib/picker.sh` — `baseline-setup` PR#14, merged `dced154`.
- `lib/manifest.sh` is the first generic implementation anywhere in the family of the `requires = {gui,atomic,family,de}` predicate (every sibling hand-codes its own per-component gate checks); parameterized by manifest path, since `baseline-setup` is the first consumer that has to read *other* repos' manifests rather than its own.
- `lib/apply.sh`'s `LAYER_ROSTER` is a static repo:script list with no component ids in it (ADR 0004 D6) — enforced by a grep-based bats test (invariant 2), not just a comment.
- `lib/gum-bootstrap.sh` pins a `gum` version + per-asset sha256 (Linux x86_64/arm64, lifted from upstream's own `checksums.txt`) and refuses to use anything unverified.
- Vendored `tests/bats.d/` from `baseline-apps` (same harness convention as `baseline-desktop`); wrote fixture stub repos under `tests/fixtures/repos/` (logging stub installers, fixture manifests, a fixture `platform.sh`) so the full CLI could be exercised as a real subprocess with `git` mocked — no network, no real machine touched.
- Two independent code-review passes before merge: round 1 on the initial diff, round 2 specifically re-verifying round 1's fixes for regressions (worth doing given the size of this phase — see "What worked").
- `baseline-access` PR#1, merged `72f25b2`: `print_next_step` now points most machines at `baseline-setup`, keeping `baseline-bluefin` called out explicitly for the still-uncut-over laptop.
- Updated `plans/baseline-decomposition.md`'s Status section and this repo's own `CLAUDE.md`/`README.md` to stop saying "documentation only".

## Decisions
- Chose to make `--dry-run`'s meaning explicitly path-dependent (non-interactive: skip the entire clone/auth bootstrap and preview straight from the profile file; interactive: still clone+render the picker, since there's no way to preview a checklist without live manifests, but stop before invoking any installer) rather than forcing one uniform behavior — the uniform version is what round 1's review caught as broken.
- Chose to hold off flipping `baseline-setup`'s GitHub visibility to public, even though the plan calls for it "as part of this phase" — asked the user directly rather than deciding solo, since a visibility flip is a one-way-ish action with an external audience; they confirmed holding off until the code is reviewed and settled.
- Chose to run a *second* code-review pass specifically targeting the fix commit, not just the original diff — the first round's fixes touched enough surface (a full `run_noninteractive`/`run_interactive` redesign) that verifying the fixes themselves was worth a dedicated pass rather than assuming "fixed" meant "correct."

## What worked
- Forking the research step before writing any code meant the manifest-parsing/platform-sourcing/dry-run/batch-failure conventions in `baseline-setup` matched the sibling repos exactly on the first pass — no rework needed to reconcile against real code later.
- The second code-review pass earned its keep: it caught that the round-1 fix for the broken `--dry-run` had left the `--yes`/confirmation gate checked *before* the new dry-run short-circuit (a pure preview could still die "requires --yes" or prompt for confirmation), and that a test ("already-cloned repo left untouched") had gone vacuous under the redesign — it kept passing, but for the wrong reason, no longer reaching the code it claimed to test. Neither would have been caught by re-running the test suite alone, since the suite was green both times.
- Building fixture stub repos (logging installers + fixture manifests + a fixture `platform.sh`) let the integration tests exercise the *real* CLI as a subprocess, including the clone step via a mocked `git`, rather than only unit-testing the library functions in isolation — this is what surfaced the `--dry-run` bug in the first place (a unit test on `apply_selection` alone wouldn't have shown the fresh-box, nothing-cloned-yet scenario).

## What didn't work
- The first version of `visible_component_ids`'s python fragment contained an apostrophe inside a comment (`a manifest author's typo`) — since the whole fragment is embedded in a single-quoted bash string (deliberately, to avoid bash expanding `$` inside the python source), the apostrophe broke out of the string early and every line after it got parsed as raw bash, producing a bash syntax error pointing at an unrelated python line number. Caught immediately by the test suite. `baseline-apps.sh` already has a code comment warning about exactly this failure mode for its own python fragments — read it, then made the mistake anyway a layer up. Fixed by rewording to avoid the apostrophe; worth remembering as a standing constraint on every python-fragment-in-single-quoted-bash string in this file, not just the one that broke.
- `run_noninteractive`'s original design threaded `--dry-run` straight into `apply_selection` — which is exactly the shape used for real installs — without noticing that `apply_selection` requires the layer repos to already be cloned, and `--dry-run` was designed to skip cloning. This was a design gap that a full read-through before writing tests probably would have caught; instead it took an independent reviewer plus real fixture-repo integration tests to surface it.

## Open / next
- Phase 7 (laptop cutover validation) is next — run `baseline-setup` end-to-end on the Bluefin laptop. This is also the first real exercise of the interactive gum picker path, which has zero automated coverage (documented limitation, not an oversight — it needs a real TTY + `gum` binary).
- Flip `baseline-setup` to public before or during Phase 7 — held off this session per the user's explicit call, revisit then.
- Per this repo's `CLAUDE.md`, the migration stays out of every `BACKLOG.md` — no backlog items added or swept this session.
- Git hygiene: every worktree/branch created this session (`baseline-setup`'s two — the main Phase 6 work and this plan-status/devlog one — plus `baseline-access`'s) was removed after its PR merged; both repos' primary checkouts confirmed clean.
