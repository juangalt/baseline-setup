---
date: 2026-07-21
session: phases-2-4-and-plan-review
project: baseline-setup
related:
  - plans/baseline-decomposition.md
  - decisions/0001-baseline-layer-decomposition.md
  - decisions/0002-multi-distro-multi-de.md
  - decisions/0003-component-tui-and-manifest-contract.md
  - decisions/0004-contract-refinements.md
  - PR#8, PR#9, PR#10, PR#11 (baseline-setup, plan status updates)
  - baseline-shell PR#15, baseline-desktop PR#4, baseline-apps PR#1
status: done
---

## Goal
Execute Phases 2–4 of the `baseline-decomposition` migration (the shared `platform.sh` contract, the GNOME dconf engine, and the flatpak app installer) across three repos, then review overall progress and fold what was learned back into the plan before handing off to Phase 5/6.

## Context
- Session opened with a repo review: Phase 1 (`baseline-access` rename) had already shipped 2026-07-20, but the plan's own Status section still said "no phase has been executed yet" — first fix was correcting that stale claim (PR #8).
- From there, executed Phases 2, 3, and 4 in sequence, each as a real PR with an independent code-review pass before merge — the pattern established in Phase 2 held for all three.

## What we did
- **Phase 2** (`baseline-shell` PR #15): `platform.sh` (contract C1), `manifest.toml` + `bootstrap.sh --components` (C2/C3), git identity wiring absorbed from `baseline-bluefin`, zypper/brew branches in `apps/baseline.sh`. Code review caught a real safety issue (auto-`chsh` on component deselect) — fixed to warn-only.
- **Phase 3** (`baseline-desktop` PR #4): ported the selective per-key dconf engine from `baseline-bluefin.sh` into `baseline-desktop.sh`, plus a new `gnome-autostart` component. Code review caught `install_autostart`'s bare `ln -sf` silently destroying a real pre-existing file — fixed to back up, mirroring `bootstrap.sh`'s `link_dotfile`.
- **Phase 4** (`baseline-apps` PR #1, a brand-new repo): flatpak-primary GUI installer, native-residue drift check, structural no-formula lint. Code review caught a `rpm-ostree status --json` "reads `deployments[0]`, not the booted one" bug and an abort-on-first-failure install loop — both fixed.
- Devlog entries written per-repo for each phase (`baseline-shell`, `baseline-desktop`, `baseline-apps` each got their own). One was initially left uncommitted in the primary checkout instead of going through an isolated worktree/PR (`baseline-shell`'s Phase 2 devlog) — caught during a later cross-repo status check and landed properly (`baseline-shell` PR #16).
- Final step: a progress review across all four shipped phases, then two concrete contract additions to the appendix (C1's `platform.sh` sourcing idiom, C3's "one item's failure doesn't abort the batch") plus a consolidated "Known deferred items" list before Phase 8 — PR #11.

## Decisions
- Ran an independent `code-reviewer` agent against every phase's PR diff before merging, not just once — three times, one per repo. Each pass found something real (never zero findings), which is itself the argument for keeping the practice for Phase 5/6 rather than treating it as a one-time gate.
- Chose to fold Phase 2–4's convergent implementation choices (the `platform.sh` sourcing idiom, batch-failure resilience) back into the plan's appendix contracts (C1/C3) rather than leaving them as three independent, undocumented conventions — so Phase 6's apply engine (which has to get both right on the first attempt, since it's the thing every layer's installer answers to) can build against a contract instead of reverse-engineering the pattern from three sibling repos.
- Chose to consolidate deferred-scope items (casks/VS Code in `baseline-apps`, non-brew `starship`, KDE/Cosmic backends) into one list in the plan rather than leaving them scattered across three repos' `decisions/`/`devlog/` — Phase 8 is explicitly the catch-all sweep, and it shouldn't have to rediscover what earlier phases already knew and wrote down.

## What worked
- The `manifest_query`/`read_default_components`/`valid_component_ids`/`validate_components` pattern, first written for `baseline-shell` in Phase 2, ported to `baseline-desktop` and `baseline-apps` with zero redesign — genuine evidence the C2/C3 contracts are implementation-agnostic, not just convenient for one script.
- Isolating every real code change in a manually-created `git worktree` (since this session's cwd was pinned to `baseline-setup`, and `EnterWorktree` only isolates the session's primary repo) kept four repos' work cleanly separated across one long session with no cross-contamination.
- Code review finding real bugs three phases running, each time something a solo read would plausibly have missed (a shell-state clobber, a file clobber, a JSON-parsing edge case) — the pattern earned its keep, not just theater.

## What didn't work
- `EnterWorktree` isolates only the session's *primary* repo (`baseline-setup`); for the other three repos, manually-created `git worktree add` was needed instead — but the harness's isolation guard only recognizes edits made via `EnterWorktree` *for the primary repo specifically*, and rejected a manual-worktree edit attempt on `baseline-setup` itself late in the session (had to discard the manual worktree and redo it with `EnterWorktree`). Worth remembering: for the session's own primary repo, always `EnterWorktree`; for siblings, manual `git worktree add` is fine and the only option.
- A `baseline-shell` devlog entry got written directly into the primary checkout (not a worktree) during the Phase 2 close-out, never committed, and sat as an untracked file until a routine `git status` sweep across all four repos surfaced it — well after Phase 3 and 4 had already shipped. The fix for this exact failure mode (write the devlog inside an isolated worktree, same as any other change) had already been established for Phase 3's devlog; it just didn't get applied retroactively to Phase 2's until caught by inspection, not by design.
- Two small self-inflicted bash/Python quoting bugs while applying `baseline-apps`'s code-review fixes (an f-string with an escaped quote inside its expression — invalid Python <3.12 syntax; a bare single quote inside an already-single-quoted bash string, silently truncating it) — both caught immediately by the test suite on first run, neither reaching a merged commit, but a reminder that small inline Python-in-bash snippets are genuinely easy to get subtly wrong and worth testing the moment they're written.
- Scaffolding `baseline-apps` via `new-repo --category baseline baseline-apps` doubled the prefix to `baseline-baseline-apps` (passed the already-prefixed name to a flag that also prefixes) — caught immediately, fixed via `gh repo rename` + local `mv` + `git remote set-url` before any commit referenced the wrong name.

## Open / next
- Phase 5 (`app-fleet-control`'s `set-hostname` subcommand) and Phase 6 (`baseline-setup`'s picker + apply engine) are next, independent of each other — see the plan's Status section "Next" line for the concrete contract guidance to build Phase 6 against from the start.
- "Known deferred items" (in the plan, before Phase 8) tracks what Phases 2–4 knowingly left out: `baseline-apps` casks/VS Code extensions/zypper native-residue, `baseline-shell` `starship` on non-brew platforms, `baseline-desktop` KDE/Cosmic backends.
- Per this repo's own `CLAUDE.md`, the migration stays out of every `BACKLOG.md` — no backlog items added or swept this session, in any of the four repos touched.
- Git hygiene: every worktree and branch created this session (across `baseline-setup`, `baseline-shell`, `baseline-desktop`, `baseline-apps`) was removed after its PR merged; all four repos' primary checkouts confirmed clean at session close. `baseline-shell` and `baseline-desktop`'s primary checkouts were left untouched on their own unrelated in-progress branches throughout.
