---
date: 2026-07-22
session: phase7-real-hardware-validation
project: baseline-setup
related:
  - plans/baseline-decomposition.md
  - baseline-setup PR#16
  - baseline-setup PR#17
  - [[2026-07-22-0046-phase6-picker-apply-engine]]
status: blocked
---

## Goal
Begin Phase 7 (laptop cutover validation) — run `baseline-setup` end-to-end on the actual Bluefin laptop and start working through the parity checklist against `baseline-bluefin.sh`.

## Context
- Continuing from [[2026-07-22-0046-phase6-picker-apply-engine]]: Phase 6 shipped, Phase 7 is the last gate before Phase 8's deletion of `baseline-bluefin`.
- Phase 7 is categorically different from Phases 1–6: it's a validation run against real hardware the user actually uses daily, not a code change in a repo. This session runs on `arrakis` (a cloud host), not the laptop.

## What we did
- Identified the target: no fleet host is literally named "bluefin"; confirmed with the user that `fedora-x1` is the actual machine (`NAME="Bluefin"`, atomic/Silverblue, hostname `fedora-x1`).
- Created an isolated local test user (`baselinetest`, no sudo beyond a narrow `felipe ALL=(baselinetest) NOPASSWD: ALL` grant the user set up themselves) specifically so the real apply engine could run for real without touching `felipe`'s actual account, dotfiles, git identity, or live GNOME session.
- Staged the layer repos into `baselinetest`'s home by copying from `felipe`'s already-cloned checkouts (not re-cloning — a fresh user has no GitHub SSH key wired, and that requires interactive Bitwarden login this session can't do) — discovered and worked around two real environment issues in the process: `felipe`'s local `baseline-shell`/`baseline-desktop`/`baseline-access` checkouts on this laptop were stale (behind by whole merged phases — pulled to `origin/main`), and `felipe`'s local `meta-ai-dev` had diverged from origin (unpushed local commits) — extracted `origin/main`'s content via `git worktree add --detach` instead of touching that branch.
- Ran `baseline-setup.sh --selection laptop --dry-run` as `baselinetest` on a genuinely fresh, uncloned account — confirmed it prints the plan and touches nothing, real-world proof of the Phase 6 `--dry-run` redesign.
- Ran the real (non-dry) apply via `apply_selection` directly (skipping `baseline-setup.sh`'s own `bootstrap_access` step, which needs interactive Bitwarden auth) — this is what surfaced a real bug: `bootstrap.sh` rejected `install` as an unknown argument. Root cause: `lib/apply.sh` hardcoded `<script> install --components <csv>` for every L1 layer, but `bootstrap.sh` has no subcommand at all (unlike `baseline-apps.sh`/`baseline-desktop.sh`, which do use `install` alongside their own `status`/`push`). Fixed in `baseline-setup` PR#16 (merged `bc0e3f5`) — `LAYER_ROSTER` gained a third `invoke` field (`install`/`flags`), and the bats fixtures (previously loose enough to accept either shape) were made strict per-style with a dedicated regression-guard test.
- Re-verified the fix on the real laptop: `bootstrap.sh` ran correctly — symlinked dotfiles, wired `.bashrc`/`.zshrc`, cloned zsh plugins, gracefully degraded on its two `sudo`-gated steps (no password available to `baselinetest`, exactly the designed fallback) — and the apply engine correctly continued past a sandbox-only `brew` permission failure (`baselinetest` isn't in the `linuxbrew` group) to finish `baseline-desktop`/`meta-ai-dev`, confirming batch-failure-tolerance holds on real hardware, not just mocks. `baseline-apps`/`baseline-desktop` correctly auto-skipped themselves (no live GUI session for `baselinetest` — both `requires = {gui}`-gated, working as designed).
- Recorded all of this in the plan (`baseline-setup` PR#17, merged `91bc334`).
- Started on `baseline-apps` (flatpak) validation next, with a plan to fake `DISPLAY` for `baselinetest` (platform.sh's GUI gate just needs a non-empty `DISPLAY`/`WAYLAND_DISPLAY`; `flatpak install` itself doesn't need a real display server) — `fedora-x1` went offline (intermittent host) before this could run.

## Decisions
- Chose the isolated-test-user approach over testing against `felipe`'s real account, at the user's explicit request — real `install` steps (packages, live dconf writes, shell defaults) on a daily-driver machine warrant isolation, not an automated pass on the real thing.
- Chose to copy already-cloned repos through `felipe` rather than re-clone as `baselinetest` — re-running `baseline-access`'s interactive Bitwarden flow for a throwaway test account wasn't warranted, and the thing actually under test (the apply engine + layer installers) doesn't depend on how the repos got onto disk.
- Chose not to attempt `baseline-desktop`'s real dconf write against any session this pass — it can only be meaningfully tested against a *live* GNOME session, and mutating `felipe`'s real one unattended is exactly the risk isolation was meant to avoid. Left as an explicit open item rather than silently skipped.
- Stopped retrying SSH connectivity after `fedora-x1` went offline mid-session rather than polling indefinitely — asked the user, who chose to pause rather than wait.

## What worked
- The isolated-test-user + fresh-repo-copy approach caught a real bug that zero amount of mocked bats testing would have caught — Phase 6's own fixtures were "close enough" to reality that a fundamentally wrong assumption (every layer takes an `install` subcommand) passed 62 tests cleanly. Real hardware, real scripts, no mocks, surfaced it on the first real run.
- `bootstrap.sh`'s own designed degradation (warn and continue when `sudo` isn't available, rather than dying) worked exactly as intended under a genuinely unprivileged account — nothing needed patching there.
- The apply engine's batch-failure-tolerance (one layer's failure doesn't block the rest) held up against a real, unplanned failure (the `brew` permission error), not just the synthetic failures the bats suite injects.

## What didn't work
- `felipe`'s local checkouts on `fedora-x1` were significantly stale for some repos (`baseline-shell` was missing `platform.sh` entirely) and diverged for `meta-ai-dev` — a reminder that a laptop that isn't the primary dev machine for a repo can silently drift a long way behind `origin/main` between sessions. Cost a few extra steps to detect and work around, but nothing was force-pushed or overwritten.
- `fedora-x1` going offline mid-validation (twice — once before starting, once mid-flatpak-setup) is the nature of an `[intermittent]` fleet host; cost real wall-clock time waiting/retrying. Nothing to fix here, just a real constraint on how Phase 7 sessions against this specific machine will go.

## Open / next
- `baseline-apps` (flatpak) real validation is next once `fedora-x1` is back online: fake `DISPLAY` for `baselinetest` to pass the GUI gate, run the real install (~40 apps, real bandwidth/time — deliberately not incidental).
- `baseline-desktop` (GNOME dconf) still needs a validation plan against a *live* session — not yet decided how (the user's own account, watched, vs. some other approach).
- The interactive gum picker has zero automated or manual exercise yet — needs the user at an actual keyboard with a real TTY.
- The full parity checklist (`baseline-bluefin.sh` command ↔ new-layer equivalent) hasn't started.
- `baselinetest` is still on `fedora-x1`, isolated, ready to resume — not torn down, since more testing is expected. Teardown command (`sudo userdel -r baselinetest && sudo rm /etc/sudoers.d/felipe-baselinetest`) is in the earlier conversation if wanted before that.
- Per this repo's `CLAUDE.md`, the migration stays out of every `BACKLOG.md` — no backlog items added or swept this session.
- Git hygiene: `baseline-setup` PRs #16 and #17 both merged and their worktrees/branches removed during the session; primary checkout confirmed clean and up to date. No other repos had open work this session.
