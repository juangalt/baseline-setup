---
date: 2026-07-22
session: phase7-baseline-apps-validation
project: baseline-setup
related:
  - plans/baseline-decomposition.md
  - [[2026-07-22-0137-phase7-real-hardware-validation]]
status: done
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
- User uninstalled `io.github.nacho.mecalin` (`profile-laptop`) on `fedora-x1` to create a genuine install-path test gap. First attempt as `baselinetest` over non-interactive SSH failed with "Flatpak system operation Deploy not allowed for user" — confirmed this wasn't account-specific by trying the identical `flatpak install` directly as `felipe` over SSH too, same failure. Root cause: system-wide flatpak installs require either an active polkit authentication agent (a real console GUI session) or root; a non-interactive SSH session has neither, and `felipe` has no passwordless sudo (`sudo -n true` failed). The apply engine's failure handling worked exactly as designed regardless — `WARN flatpak install failed ... continuing with the rest` then a non-zero exit for the batch.
- User then ran `baseline-apps.sh install --components profile-common,profile-laptop` directly at the real console (their own terminal, live GNOME session, real polkit password prompt) — succeeded. Verified remotely afterward: `flatpak list --app` on `fedora-x1` shows `io.github.nacho.mecalin` reinstalled.
- User exercised the interactive gum picker at a real console/TTY for the first time this whole migration: confirmed the options render and can be selected. Stopped deliberately before applying anything — no install triggered, no `selected.toml` written this pass.
- Ran the remaining parity-checklist items against `fedora-x1`: discovered `baseline-shell`/`baseline-access` have no `status` subcommand at all (checked `--help`), so ran `bootstrap.sh --dry-run` instead — correctly reported `ok` for everything already applied and `DRY` for the still-pending `sudo`-gated steps. Ran `baseline-desktop.sh push` (same headless `dbus-run-session` environment) — correctly reported "already in sync", took no action (this command only commits+pushes to git on real drift). Cross-checked the full `baseline-bluefin.sh` command table against replacements and closed out the parity checklist in `plans/baseline-decomposition.md`, including two intentional non-parities (no `status` verb for shell/access; no CLI-side `push packages` equivalent since the guaranteed roster is fixed/non-selectable).

## Decisions
- Did not uninstall any flatpak from `fedora-x1` to manufacture a "missing app" test case — `felipe`'s daily-driver flatpaks are shared system-wide state (installs are `flatpak install` with no `--user` flag, so `baselinetest` sees everything `felipe` has), and deliberately mutating that without asking wasn't warranted for a validation pass.
- Validated the read-only `status`/`push` paths instead of forcing an install test, since they're safe, exercise real detection logic (component-installed check, untracked-flatpak diff, native-residue check) against real system state, and still produced genuine signal (the 15-app untracked list is real, previously-undocumented drift on this laptop).
- Chose a headless `dbus-run-session` over spinning up a real nested/visible GNOME compositor for `baselinetest` — `dconf load`/`read` only need a session D-Bus bus, not an actual window server, so this exercises the identical write path (`ca.desrt.dconf` activation, gvdb write) with zero risk of a stray window appearing in `felipe`'s live session.

## What worked
- `status`/`push` both ran cleanly as an unprivileged, no-sudo, no-GUI-session account (`DISPLAY` faked, no real Wayland/X11 compositor) — confirms these commands need nothing beyond the `flatpak` CLI itself, matching the read-only-Q4-check design.
- The `COMPONENT_FLATPAKS` list is accurate against reality: no drift between what the manifest declares and what's actually on the machine for the tracked profiles.
- The `dbus-run-session` + faked-env-vars approach fully validated `baseline-desktop`'s real dconf write path end to end (drift detection → `dconf load` → `ca.desrt.dconf` activation → persisted write → clean re-read) with total isolation from `felipe`'s real GNOME session/dconf database — this was the deferred-since-last-session item and it's now closed.
- The operator-driven uninstall-then-reinstall approach (user removed `mecalin`, ran the script themselves at the console) was exactly right for the flatpak install-path gap: it produced a real failure signal over SSH (polkit/root requirement) *and* a real success signal at the console, both genuinely informative, without me ever needing to touch `felipe`'s daily-driver flatpak state unprompted.

## What didn't work
- Confirms flatpak installs in this design are system-wide only (no `--user` remote), so `baselinetest`-vs-`felipe` isolation for flatpak specifically is weaker than for dotfiles/shell config — worth knowing going into any future install-path test (it will affect `felipe`'s real environment, not just the test account's).
- The non-interactive-SSH install attempt (both as `baselinetest` and as `felipe` directly) failed on a real, structural constraint: system-wide flatpak installs need an active polkit auth agent or root, and neither is available over plain SSH without passwordless sudo. This isn't fixable within this session's scope — it's a real limit on how far `baseline-setup`'s non-interactive `--selection --yes` mode can go for GUI-machine flatpak installs specifically (now documented in the plan rather than silently discovered and dropped).

## Open / next
- **Phase 7 is complete.** `baseline-shell`, `baseline-apps`, `baseline-desktop` are all validated end to end on real hardware (install/status/push/dry-run paths, real failure-tolerance), the gum picker's UI has had its first real exercise, and the full parity checklist against `baseline-bluefin.sh` is checked off in `plans/baseline-decomposition.md`.
- Next actual step: **flip `baseline-setup` to public** (`gh repo edit juangalt/baseline-setup --visibility public`) — deliberately deferred since Phase 6, now due.
- Then **Phase 8**: tombstone `baseline-bluefin` (README/CLAUDE pointer + `gh repo archive`), doc sweep across `meta-ai-dev`/`workspace-homelab`, and sweep the plan's "Known deferred items" list (no-cask/VS-Code-extension support in `baseline-apps`, no `starship` binary install path on non-brew platforms in `baseline-shell`, no KDE/Cosmic automation in `baseline-desktop`) into real decisions rather than leaving them implicit.
- Carry into Phase 8's docs: `baseline-setup`'s non-interactive `--selection --yes` mode has a real, documented limit for GUI machines — flatpak system installs need an active polkit agent or root, neither available over plain non-interactive SSH without passwordless sudo.
- `baselinetest` still live on `fedora-x1`, now with a populated dconf database + autostart symlink from this session's real install — untouched otherwise, no teardown this session; it may still be useful for Phase 8 validation.
- No `BACKLOG.md` in this repo (confirmed) and this migration is explicitly kept out of every other repo's backlog per this repo's `CLAUDE.md` — skipped the backlog sweep step by design, not by oversight.
- This session's PR (#19) was merged and its branch auto-deleted mid-session; this final round of parity-checklist findings goes out as a follow-up commit/PR on a fresh branch off the post-merge `main`.
