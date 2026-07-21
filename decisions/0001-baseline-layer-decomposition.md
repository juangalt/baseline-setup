# 0001 — Decompose `baseline-bluefin` into DE-agnostic baseline layers

- **Status:** accepted — scope broadened and the atomic-detection sub-decision **reversed** by
  [`0002`](0002-multi-distro-multi-de.md) (multi-distro/multi-DE; detection becomes a shared
  contract owned by `baseline-shell`, not duplicated per repo)
- **Date:** 2026-07-20
- **Amends (cross-repo):** `meta-ai-dev/decisions/0002-fleet-setup-layers.md` (adds an
  orchestrator and an L0.5 rung to the layer model) and
  `meta-ai-dev/decisions/0003-repo-taxonomy-by-type.md` (three new `baseline-*` repos, one
  rename, one archival). Both carry a pointer back to this ADR.
- **Executable how:** [`../plans/baseline-decomposition.md`](../plans/baseline-decomposition.md)

> **Why this ADR lives here.** It is the founding decision of `baseline-setup` — the repo
> exists *because* of this decomposition, and the layer table below is its reason for
> being. It amends two `meta-ai-dev` ADRs, which record the amendment by pointer rather
> than by holding the rationale twice.

## Context

`baseline-bluefin` is a single-image monolith. One repo carries chezmoi dotfiles, a
Brewfile, GNOME dconf inis, GitHub-key installation, git identity, hostname setting, and
Tailscale name sync — all of it implicitly scoped to *one image on one laptop*.

The operator wants to rebase freely between Universal Blue siblings (Bluefin/GNOME,
Aurora/KDE, Bazzite, a Cosmic image). Research settled the actual risk surface:

- `rpm-ostree`/`bootc` rebase **never writes to `/home`** — shell dotfiles are always safe
  across a rebase. The monolith's coupling to the image is largely accidental, not
  necessary.
- Running different DEs against one shared `$HOME` **does** cross-pollute session-level
  state: `~/.config/gtk-{2,3,4}.0` (KDE actively rewrites these), `mimeapps.list`,
  `user-dirs.dirs`, `~/.local/share/applications`, `environment.d`, autostart,
  `systemd/user`, icon/cursor/font dconf state, kwallet-vs-GNOME-Keyring, and
  `xdg-desktop-portal` backend selection (keys off `XDG_CURRENT_DESKTOP`; the daemon is
  often not restarted on switch). Community consensus: cosmetic and annoying, **not
  destructive**.

So the problem is not "rebasing is dangerous" — it is that a *single-image* repo cannot
express which of its contents are image-independent (shell, CLI tools, identity) and which
are per-DE session state that must be captured and restored per image. A second symptom of
the same flaw: an LXC that wants only shell + CLI tools cannot consume the monolith at all,
because it would drag GNOME dconf and laptop hostname logic along with it.

Two constraints shaped the target shape:

1. **The public entry point is load-bearing.** `baseline-github` is public precisely so its
   bootstrap one-liner can be audited byte-by-byte on a pinned tag before being piped into a
   shell, on a machine that has no credentials yet. That property must survive.
2. **Not every target wants promotion.** `fleet control-node bootstrap` makes a machine a
   *control node* — privileged, gets all services, can deploy to others. Correct for a
   personal laptop; wrong for an LXC or a throwaway box, which is enrolled via
   `fleet host add` from an existing control node.

## Decision

Decompose into single-responsibility layers, one repo per responsibility:

| Repo | Layer | Scope |
|---|---|---|
| `app-fleet-control` + `content-fleet-policy` | L0 | SSH policy, hostname + Tailscale sync, recovery key (agent-only, never disk) |
| `baseline-access` (renamed from `baseline-github`) | L0.5 | **PUBLIC.** Zero-credential git-readiness. Stays small; behavior unchanged |
| **`baseline-setup`** *(this repo)* | orchestrator | Orchestration only, no layer logic of its own. The single front door |
| `baseline-shell` | L1 | Shell/dotfiles/tmux **+ all CLI tooling**. Does not orchestrate |
| `baseline-desktop` | L1 | Per-DE session state, multi-DE (see its `decisions/0001`) |
| `baseline-apps` | L1 | **NEW.** GUI apps only — flatpak-primary, brew casks secondary |
| `meta-ai-dev` | L2 | unchanged |

Load-bearing sub-decisions:

- **`baseline-setup` orchestrates; nothing else does.** Front door is
  `git clone <baseline-setup> && ./baseline-setup.sh`. `baseline-shell` was considered as
  the orchestrator and rejected — orchestration is not a shell concern, and putting it
  there would have forced a private repo to become the entry point.
- **The security gate is structural, not cryptographic.** Phase 1 delegates to
  `baseline-access` (public, no auth) → a GitHub key exists → the private repos clone over
  SSH. Everything past phase 1 requires the Bitwarden-derived key. Encrypting payloads in a
  public repo was considered and rejected: it buys nothing over "put it in a private repo"
  and adds key management.
- **`baseline-access` runs first, fleet promotion is explicit opt-in.** Order:
  clone+run public `baseline-access` → private clones → `baseline-shell` → `baseline-apps` →
  `baseline-desktop` → `meta-ai-dev`. `baseline-setup` performs **no** L0 enrolment — it only
  *prints* the concise control-node / fleet-host setup instructions and continues (L0 is
  privileged and independent of the flow; the private-repo clone is gated by the Bitwarden key,
  not by fleet enrolment). Access-first also strictly helps the fleet path: with the key on
  disk, the policy-repo clone needs no HTTPS+PAT dance.
- **CLI tooling is exclusively `baseline-shell`'s; `baseline-apps` is GUI-only.**
  `baseline-shell` gains an atomic-host brew branch alongside its apt/dnf/pacman path.
  `baseline-apps`' profile format has **no formula section at all**, so misfiling a CLI tool
  there is a lint error rather than silent drift. A single documented *guaranteed roster*
  (what any script may assume exists: `rg`, `fzf`, `jq`, `tmux`, …) is asserted on both
  install branches.
- **Atomic-host detection is duplicated deliberately.** `[ -e /run/ostree-booted ]` is a
  two-line, kernel-stable probe. Extending `baseline-shell/role.sh` with `ATOMIC_HOST` would
  not invert the layer direction, but it would create a new sibling coupling (`baseline-apps`
  sourcing a `baseline-shell` file, or depending on an interactive-session env var that
  install-time shells do not have). Add it to `role.sh` only when an interactive consumer
  wants it.
  > **⚠ Reversed by [`0002`](0002-multi-distro-multi-de.md).** This held for *one* probe. Once
  > the target surface broadened beyond atomic images, the real requirement became five facts
  > (family, package manager, atomicity, GUI, DE) consumed by three repos — duplicated, they
  > drift, and a drifted answer silently mis-installs rather than failing. Detection now lives
  > in `baseline-shell/platform.sh` as a shared name-and-value contract.
- **chezmoi is dropped.** After decomposition the chezmoi-managed inventory is ~4 files,
  none templated (zero `.tmpl` files exist). `baseline-shell`'s existing marker-block +
  symlink approach covers it, and adopting chezmoi would force a new dependency onto every
  fleet LXC that runs `bootstrap.sh` to buy features nothing uses.
- **`baseline-apps` ships named profiles from day one** (`common` + `laptop` + a `handheld`
  stub). A Bazzite handheld and a dev laptop want different app sets; a flat list would have
  to be split later under pressure.
- **Reconstruction coverage is fenced honestly.** `rpm-ostree install` layered packages sit
  outside both flatpak and brew, so `baseline-apps` records them in
  `profiles/<p>/layered.list` as **declared manual residue** per `meta-ai-dev/decisions/0007`
  — listed and drift-checked against `rpm-ostree status --json`, never auto-applied. The
  README states plainly that `baseline-apps` does not claim full reconstruction.

Migration is **additive**: every responsibility is copied to its new home and proven on the
live laptop before being deleted from `baseline-bluefin`, which stays functional until a
final parity checklist passes and is then tombstoned and archived.

## Alternatives considered

- **Keep the monolith, add per-DE subdirectories.** Cheapest, but leaves the image coupling
  in place: the repo still cannot be consumed by an LXC that wants only shell + CLI tools,
  which is most of the fleet.
- **`git filter-repo` history-preserving extraction per target repo.** The moved artifacts
  are small curated files (inis, ~40-line functions, a Brewfile), the destination repos
  already exist with their own histories, and provenance lines in the successor ADRs buy the
  traceability at zero tooling cost — the same pattern `baseline-bluefin` itself used when
  porting from `z-bluefin-bootstrap`.
- **A separate user account per DE.** Rejected: the operator wants a shared home, and a
  fully-shared home across two UIDs recreates the collision *and* adds permission friction —
  strictly worse than one account.
- **Fleet-bootstrap before `baseline-access` in the orchestrator.** Matches the layer ADR's
  L0-before-L1 order literally, but `fleet control-node bootstrap` is self-sufficient (it
  does its own one-time HTTPS+PAT clone and `bw` login), so the ordering buys nothing — and
  it would make privileged control-node promotion the default path for every target. For
  fleet-managed hosts L0 still genuinely happens first, via `fleet host add` from an existing
  control node, before anyone runs `baseline-setup` there.

## Consequences

- **Five repos to keep coherent instead of one.** Mitigated by single responsibility per
  repo and the guaranteed-roster assertion; the cost is real and accepted.
- **The rename is the one risky moment.** `baseline-github` is the sole zero-credential entry
  point. Phase 1 must verify GitHub's redirect keeps the old clone and raw-tag URLs alive
  immediately after renaming.
- **`baseline-desktop`'s data classification changes** from pure restore-from-backup to mixed
  — GNOME dconf is recreate-from-code, KDE/Cosmic archives are restore-from-backup. Its
  `CLAUDE.md`/`README.md` are rewritten accordingly; the ownership matrix is that repo's
  `decisions/0001`.
- **Tests are rewritten per target, not copied.** `baseline-bluefin`'s bats mocks assume its
  own function names; each move carries a test rewrite in the same PR.
- **One Bitwarden item name standardizes.** The GitHub service key is reachable under both
  `ssh-access service key: github` and `fleet-policy:keys/service/github`; a fingerprint
  comparison on 2026-07-20 confirmed **the same key**. `baseline-access` moves to the
  `fleet-policy:` name, which fleet's schema requires as a prefix on every reference.
- **`baseline-bluefin` becomes a tombstone** — README/CLAUDE replaced by a pointer table to
  the new homes (the `service-claude-oauth-refresh` precedent), then `gh repo archive`. Its
  four ADRs stay put as history; successors carry provenance lines back to them.
- **This repo starts private and goes public at Phase 6.** The design calls for
  `baseline-setup` to be public so its front-door one-liner is auditable like
  `baseline-access`'s. It is private until the orchestrator script exists, because the
  migration plan it currently carries describes fleet internals with no offsetting benefit
  to publishing them early. Flipping visibility is a Phase 6 step, not an oversight.
