---
date: 2026-07-22
session: phase8-tombstone-doc-sweep
project: baseline-setup
related:
  - plans/baseline-decomposition.md
  - baseline-bluefin PR#1
  - meta-ai-dev PR#113
  - workspace-homelab PR#207
  - [[2026-07-22-0941-phase7-baseline-apps-validation]]
status: done
---

## Goal
Execute Phase 8 of the baseline decomposition — tombstone `baseline-bluefin` and reconcile every doc that still described the migration as pending, now that Phase 7's parity checklist passed.

## Context
- [[2026-07-22-0941-phase7-baseline-apps-validation]] closed Phase 7 (real-hardware validation for `baseline-shell`/`baseline-apps`/`baseline-desktop`, the parity checklist, and the public-visibility flip) — the gate Phase 8 was waiting on.
- Phase 8's scope per `plans/baseline-decomposition.md`: tombstone `baseline-bluefin` (README/CLAUDE pointer + `gh repo archive`), doc sweep across `meta-ai-dev`/`workspace-homelab`, devlog entry.

## What we did
- Found the tombstone precedent by reading `service-claude-oauth-refresh`'s actual README/CLAUDE (the plan referenced it by name but it's not GitHub-archived itself — just decommissioned-in-place) and matched its format: retired banner, "what it was"/"why it's gone"/"where to look" structure.
- `baseline-bluefin` (`baseline-bluefin` [PR#1](https://github.com/juangalt/baseline-bluefin/pull/1), merged `ad3cf83`): rewrote `README.md`/`CLAUDE.md` as a tombstone with a full command-by-command pointer table (every `baseline-bluefin.sh` verb → its real replacement, including the two intentional non-parities from Phase 7); annotated all four `decisions/*.md` ADRs with a "Superseded" note pointing to the successor repo/ADR (`0001` → the manifest+component model, `0002` → `baseline-access`, `0003` → `baseline-desktop/decisions/0001`, `0004` → `app-fleet-control`'s `fleet set-hostname`); removed `DISPLAYLINK.md`/`BLUEFIN-USB-INSTALL.md` (moved, not deleted-in-place); added a final devlog entry to the repo's own `devlog/`. Then `gh repo archive juangalt/baseline-bluefin`, confirmed `isArchived: true`.
- `workspace-homelab` (`workspace-homelab` [PR#207](https://github.com/juangalt/workspace-homelab/pull/207), merged `f568b3a`): new `machines/fedora-x1.md` spoke — hardware/role summary (from `server-inventory.md`'s existing row) plus the two runbooks moved verbatim, with the USB-install doc's post-install command block updated from `baseline-bluefin` to `baseline-setup`. Indexed in `machines/README.md`.
- `meta-ai-dev` (`meta-ai-dev` [PR#113](https://github.com/juangalt/meta-ai-dev/pull/113), merged `ce7eff3`): `decisions/0002-fleet-setup-layers.md`'s "Not yet executed" amendment note flipped to "Executed 2026-07-22"; `decisions/0003-repo-taxonomy-by-type.md`'s current-repos table updated — `baseline-bluefin` row marked archived, new row added for the five `baseline-*` repos. Checked `references/layered-bringup.md` for `baseline-bluefin` references first — found none (it already pointed at `baseline-shell` for L1), so no edit needed there.
- Each repo's changes went through its own branch → PR → squash-merge, matching this workspace's normal review-gate convention, even though `baseline-bluefin`'s PR was effectively unreviewable by anyone but the archival action itself.

## Decisions
- Did not resolve the plan's "Known deferred items" list (no cask/VS-Code support in `baseline-apps`, no `starship` binary install on non-brew platforms, no KDE/Cosmic dconf automation) as part of this sweep — those are real product-scope calls (build now vs. defer vs. drop), not mechanical doc reconciliation, and deciding them unilaterally mid-sweep would be overstepping. Left explicit in the plan as the one remaining open piece of Phase 8, for the operator to weigh in on.
- Chose to keep each cross-repo change as its own PR (three total, plus `baseline-bluefin`'s) rather than one giant unreviewable commit sequence — even for pure docs, per-repo PRs keep the blast radius and review surface matched to what actually changed in that repo.

## What worked
- The decomposition plan and the four original ADRs already had every successor mapping written down from when they were created (the decomposition map table, cross-references in `baseline-access`/`baseline-desktop`'s own ADRs) — writing the tombstone content was mostly transcription against already-decided facts, not new design work under time pressure.
- Checking `layered-bringup.md` for actual `baseline-bluefin` references before editing it saved a wasted edit — the plan's own Phase 8 line predicted it would need updating, but it turned out to already be current (pointed at `baseline-shell`, never `baseline-bluefin`).

## What didn't work
- The plan's phrase "the `service-claude-oauth-refresh` tombstone precedent" was slightly ambiguous — that repo is not itself GitHub-archived (`isArchived: false`), despite functioning as a tombstone in its README/CLAUDE content. Worth reading the actual repo rather than assuming from the name alone; the *content* pattern was the useful precedent, not its archival status.

## Open / next
- **One real decision left to close Phase 8 fully**: the "Known deferred items" list in `plans/baseline-decomposition.md` needs an operator call (build now / defer indefinitely / drop) for each of the three items — not resolved this session, flagged explicitly rather than silently carried forward again.
- Dropping `baseline-bluefin` from the arrakis `~/code` mirror is explicitly "at leisure" per the plan — not done this session.
- No `BACKLOG.md` sweep in `baseline-setup` (none exists, migration explicitly excluded from every other repo's backlog per this repo's `CLAUDE.md`).
- Git hygiene: every branch created this session (`baseline-bluefin/tombstone-baseline-decomposition-phase8`, `meta-ai-dev/docs/baseline-decomposition-phase8-sweep`, `workspace-homelab/docs/fedora-x1-machine-spoke-baseline-tombstone`) squash-merged and auto-deleted on merge; nothing left to prune.
