---
date: 2026-07-22
session: phase7-baseline-apps-validation
project: baseline-setup
related:
  - plans/baseline-decomposition.md
  - [[2026-07-22-0137-phase7-real-hardware-validation]]
status: in-progress
---

## Goal
Resume Phase 7 on `fedora-x1` where the prior session left off: validate `baseline-apps` (flatpak) and `baseline-desktop` (dconf) under the isolated `baselinetest` account, now that the host is back online.

## Context
- [[2026-07-22-0137-phase7-real-hardware-validation]] left `baselinetest` staged on `fedora-x1` with all layer repos in place, `--dry-run` and the L1 (`baseline-shell`) real apply already verified, `baseline-apps`/`baseline-desktop` confirmed to auto-skip on no-GUI sessions.
- Plan was to fake `DISPLAY` for `baselinetest` to pass `platform.sh`'s GUI gate and run a real flatpak install.

## What we did
- Confirmed `baselinetest` still live on `fedora-x1`, sudo-accessible from `felipe` (`sudo -n -u baselinetest`), repos in place.
- Set `DISPLAY=:0` for `baselinetest` to pass the `PLATFORM_GUI` gate (`baseline-shell/platform.sh:78-79` — any non-empty `DISPLAY`/`WAYLAND_DISPLAY` satisfies it, no real display server needed for a flatpak-only check).
- Ran `baseline-apps.sh install --components app-obsidian --dry-run` and `--components profile-laptop --dry-run` — both reported "already installed".
- Diffed the full target set (`profile-common` + `profile-laptop` + `app-obsidian`, 39 flatpak ids read from `baseline-apps.sh`'s `COMPONENT_FLATPAKS`) against `flatpak list --app` on `fedora-x1`: zero missing (`comm -23` empty).
- Ran the real, read-only `status` and `push` subcommands as `baselinetest` (not `--dry-run`, no gate to bypass — both are inherently non-mutating): all 4 components report installed, native-residue check reports clean (0 declared, matches), and both correctly surfaced 15 real untracked flatpaks present on `fedora-x1` but absent from any manifest component (Spotify, GIMP, Telegram, SaveDesktop, DejaDup, Calendar, Contacts, Characters, Vivaldi, and others).
- User set `baselinetest`'s GDM account session type to GNOME, expecting a live session; checked and found none actually running (`loginctl list-sessions` shows only `felipe`'s seat0 session, `ps -u baselinetest` empty, no `/run/user/1001`) — a GDM session-type preference doesn't start a session by itself; that needs an actual console login, which SSH can't drive.
- Activated a headless dconf-capable environment for `baselinetest` myself instead of waiting on a console login: faked `DISPLAY`/`XDG_CURRENT_DESKTOP=GNOME`/`DESKTOP_SESSION=gnome` to satisfy `platform.sh`'s `PLATFORM_GUI`/`PLATFORM_DE` gates, and wrapped the real commands in `dbus-run-session` (a private, throwaway D-Bus session bus) so `dconf load`/`dconf read` have something to talk to — no compositor, no visible window, nothing touching `felipe`'s live session.
- Ran `baseline-desktop.sh status` under that environment as `baselinetest`: correctly detected real drift (`keybindings` area differed from a fresh account's GNOME defaults; the other 2 tracked areas already matched) and a missing autostart symlink.
- Ran the real (non-dry) `baseline-desktop.sh install --components gnome-dconf,gnome-autostart`: `ca.desrt.dconf` D-Bus-activated correctly, `dconf load` wrote the drifted `keybindings` area, and the `com.seafile.Client.desktop` autostart symlink was created pointing into the repo checkout.
- Verified the write persisted and was correctly isolated: `dconf read` back showed the loaded custom-keybindings tree; re-running `status` reported "all 3 area(s) in sync" and "linked"; `baselinetest`'s own `~/.config/dconf/user` (2621 bytes) was created fresh, while `felipe`'s real `~/.config/dconf/user` was confirmed untouched (still its own separate file, unmodified).

## Decisions
- Did not uninstall any flatpak from `fedora-x1` to manufacture a "missing app" test case — `felipe`'s daily-driver flatpaks are shared system-wide state (installs are `flatpak install` with no `--user` flag, so `baselinetest` sees everything `felipe` has), and deliberately mutating that without asking wasn't warranted for a validation pass.
- Validated the read-only `status`/`push` paths instead of forcing an install test, since they're safe, exercise real detection logic (component-installed check, untracked-flatpak diff, native-residue check) against real system state, and still produced genuine signal (the 15-app untracked list is real, previously-undocumented drift on this laptop).
- Chose a headless `dbus-run-session` over spinning up a real nested/visible GNOME compositor for `baselinetest` — `dconf load`/`read` only need a session D-Bus bus, not an actual window server, so this exercises the identical write path (`ca.desrt.dconf` activation, gvdb write) with zero risk of a stray window appearing in `felipe`'s live session.

## What worked
- `status`/`push` both ran cleanly as an unprivileged, no-sudo, no-GUI-session account (`DISPLAY` faked, no real Wayland/X11 compositor) — confirms these commands need nothing beyond the `flatpak` CLI itself, matching the read-only-Q4-check design.
- The `COMPONENT_FLATPAKS` list is accurate against reality: no drift between what the manifest declares and what's actually on the machine for the tracked profiles.
- The `dbus-run-session` + faked-env-vars approach fully validated `baseline-desktop`'s real dconf write path end to end (drift detection → `dconf load` → `ca.desrt.dconf` activation → persisted write → clean re-read) with total isolation from `felipe`'s real GNOME session/dconf database — this was the deferred-since-last-session item and it's now closed.

## What didn't work
- The actual `flatpak install -y --noninteractive flathub "$id"` code path (`baseline-apps.sh:296`) remains completely unexercised on real hardware — every target app across all three components was already present, so no install call was ever triggered. This is a structural gap in this specific validation setup (shared system-wide flatpak state with the daily-driver account), not a code defect. A real install-path test needs either a genuinely fresh machine/account with no pre-existing flatpaks, or an explicit, asked-for uninstall of something real to create a gap — neither was done this session.
- Confirms flatpak installs in this design are system-wide only (no `--user` remote), so `baselinetest`-vs-`felipe` isolation for flatpak specifically is weaker than for dotfiles/shell config — worth knowing going into any future install-path test (it will affect `felipe`'s real environment, not just the test account's).

## Open / next
- `baseline-apps` install-path (the actual `flatpak install` call) is still unvalidated on real hardware — needs either a fresh test machine/account or an explicit user-approved uninstall-then-reinstall of one real app on `fedora-x1` to create a genuine gap.
- `baseline-desktop` (GNOME dconf) real-write validation is **done** this session, headless — a follow-up with an actual live/visible GNOME session for `baselinetest` (real console login) would be a stronger signal but isn't blocking; the headless path already exercises the identical `dconf load` code.
- The interactive gum picker still has zero exercise — needs the user at a real keyboard/TTY.
- Full parity checklist (`baseline-bluefin.sh` command ↔ new-layer equivalent) not yet started.
- `baselinetest` still live on `fedora-x1`, now with a populated dconf database + autostart symlink from this session's real install — untouched otherwise, no teardown this session.
- No `BACKLOG.md` in this repo (confirmed) and this migration is explicitly kept out of every other repo's backlog per this repo's `CLAUDE.md` — skipped the backlog sweep step by design, not by oversight.
- Git hygiene: this session's only changes are this devlog entry + a plan status update, committed directly to a worktree branch; no other stale branches/worktrees found to prune in `baseline-setup`.
