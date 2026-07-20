# Architecture — how a machine gets built

Read this before changing any `baseline-*` repo. The layer boundaries look arbitrary in places
and are not; the reasons are here so a future edit doesn't "simplify" something load-bearing.

**The one-paragraph model.** A machine is assembled by a fixed sequence of independent,
idempotent layers. Each layer owns exactly one kind of state, can be run on its own, and is
safe to re-run. `baseline-setup` runs them in order and contributes no state of its own. Every
layer must work on any supported distro and any supported desktop — or explicitly skip itself.

## Design goals

1. **Rebase-safe.** Switching a machine between OS images (or reinstalling) must not lose
   configuration. Anything that can be re-derived from a repo is; anything that can't is backed up.
2. **Multi-distro.** The same layers apply to a Debian LXC, a Fedora VM, an Arch desktop, and an
   atomic Universal Blue image. See [`decisions/0002`](decisions/0002-multi-distro-multi-de.md).
3. **Multi-DE.** GNOME, KDE, and Cosmic are peers. No layer assumes a desktop exists at all.
4. **Headless-first.** Most of the fleet is LXCs with no GUI. A headless target must get a
   complete, useful machine while skipping the graphical layers entirely — not by failing through
   them.
5. **Single responsibility per repo.** If two layers both want to own a fact, one of them is wrong.

## The stages

| # | Stage | Repo | Runs on | Skippable? |
|---|---|---|---|---|
| L0 | Access policy | `app-fleet-control` + `content-fleet-policy` | fleet-managed hosts | Not by `baseline-setup` — happens before it |
| L0.5 | Git readiness | `baseline-access` | **every** target | No |
| — | Orchestration | **`baseline-setup`** | every target | No |
| L1a | Shell + CLI | `baseline-shell` | **every** target | No |
| L1b | GUI apps | `baseline-apps` | graphical targets | Yes — auto-skip when headless |
| L1c | Desktop session | `baseline-desktop` | graphical targets | Yes — auto-skip when headless or DE unsupported |
| L2 | AI/dev meta | `meta-ai-dev` | interactive/coding hosts | Yes — by flag |

Order is not arbitrary: each stage depends on the state the previous one leaves behind.

---

### L0 — access policy (`app-fleet-control` + `content-fleet-policy`)

**What it does.** Owns who may SSH where, host identity (hostname + Tailscale node name), and the
recovery key. `policy.yaml` is the single source of truth; `fleet deploy` renders it onto hosts.

**When it runs.** *Before* `baseline-setup`, and by two different paths depending on the target:

- **Fleet-managed hosts** (LXCs, servers, anything not your own laptop) are enrolled with
  `fleet host add` **from an existing control node**. The machine itself does nothing.
- **Personal machines** may self-promote with `fleet control-node bootstrap`, which is
  self-sufficient — it does its own one-time HTTPS+PAT clone and Bitwarden login.

**Why `baseline-setup` doesn't do this for you.** Control-node promotion is *privileged*: the
machine gets every service key and can deploy to other hosts. That is correct for a laptop and
wrong for a throwaway container. Making it a default would silently over-privilege the common
case, so it is opt-in — and in v1 `baseline-setup` only *prints* the command rather than running it.

**Leaves behind.** `~/.ssh/config.d/ssh-access-managed`, `authorized_keys`, host identity.

---

### L0.5 — git readiness (`baseline-access`) · PUBLIC

**What it does.** Takes a machine with **zero credentials** to one that can clone private repos:
fetches the GitHub service key from Bitwarden, installs it, writes `known_hosts`, sets git identity,
and verifies the result.

**Why it is public and stays small.** It is the one thing you run *before* you have any secrets, so
it must be auditable byte-by-byte on a pinned tag before being piped into a shell. Every feature
added here is a feature someone has to read before trusting it. Resist growth.

**Why it runs before fleet, not after.** `fleet control-node bootstrap` doesn't need it — but with
the key already on disk, fleet's own policy-repo clone skips the HTTPS+PAT dance. Access-first is
strictly simpler and never wrong.

**Leaves behind.** A working `git clone` over SSH. Everything after this point depends on that, and
that dependency *is* the security boundary — see "Invariants" below.

---

### Orchestration (`baseline-setup`) · this repo

**What it does.** Detects the platform, then runs the stages in order, passing the detection results
down. Holds **no layer logic of its own**.

**The boundary.** If a change here starts wiring shell config, installing packages, or touching
dconf, it belongs in a sibling repo. The moment `baseline-setup` knows *how* a layer works rather
than *whether and when* to run it, the decomposition has failed.

**Leaves behind.** Nothing. It is a sequencer.

---

### L1a — shell + CLI tooling (`baseline-shell`)

**What it does.** Shell wiring (rc marker blocks, symlinks, zsh default), tmux/starship config, git
config, and **all CLI package installation** across every supported package manager.

**Why CLI tooling lives here and not in `baseline-apps`.** A headless LXC needs `rg`, `jq`, and
`tmux` and will never install a GUI app. Splitting CLI tools into a separate layer would mean every
headless target runs two layers instead of one, for no benefit. The split that matters is
**headless-capable vs graphical**, not *CLI vs GUI-adjacent tooling*.

**The guaranteed roster.** One documented list of tools any downstream script may assume exists,
asserted on *every* package-manager branch. Without it, a script written on Fedora breaks on a
Debian LXC that got a slightly different package set — the exact silent drift this layer exists to
prevent.

**Owns platform detection.** `platform.sh` lives here because `baseline-shell` is the *universal*
layer — every target runs it, so every later layer can rely on it. See "The platform contract".

**Leaves behind.** A usable interactive shell + the guaranteed CLI roster + `platform.sh`.

---

### L1b — GUI applications (`baseline-apps`)

**What it does.** Installs desktop applications from named **profiles** (`common`, `laptop`,
`handheld`, …). Flatpak-primary, because it is the only mechanism that is both distro- and
DE-agnostic. Brew casks and per-distro native packages are secondary.

**Why profiles from day one.** A handheld and a dev laptop want genuinely different app sets. A flat
list would have to be split later, under pressure, after things depend on its shape.

**Why the profile format has no formula section.** CLI tools belong to `baseline-shell`. Making that
structurally impossible to express here turns a misfile into a lint error instead of silent drift
where two layers install overlapping tool sets.

**Honest coverage.** Native packages installed outside flatpak/brew — `rpm-ostree install` layered
packages, `apt install`, AUR builds — cannot be fully reconstructed. They are recorded per profile
as **declared manual residue**: listed, drift-checked against the live system, never auto-applied.
The README says plainly that this layer does not claim full reconstruction. A documented gap beats
an implicit one.

**Skips itself** when the platform is headless.

---

### L1c — desktop session state (`baseline-desktop`)

**What it does.** Captures and restores per-DE session configuration so switching desktops or
reinstalling doesn't mean reconfiguring from scratch.

**Two mechanisms, deliberately.** This is the subtlest part of the whole design — see that repo's
[`decisions/0001`]:

- **GNOME** is tracked as curated `.ini` files pushed **key-by-key** — *recreate-from-code*.
  Diffable, testable, reviewable. Chosen over `dconf dump` because a dump captures system-managed
  and default-valued noise, and because root-path settings can't be dumped at all.
- **KDE / Cosmic** use SaveDesktop archives — *restore-from-backup*. Opaque blobs, but the
  GNOME-schema key map is structurally inapplicable to them.
- **GNOME gets no archive by default.** SaveDesktop always embeds a full dconf dump; keeping one
  around is a loaded footgun whose only use is to clobber the curated keys.
- **Where both apply: blobs restore first, code reapplies last.** Code wins on tracked keys.

**Why cross-DE pollution is documented but not fixed.** Sharing one `$HOME` across desktops bleeds
`gtk-*` config, `mimeapps.list`, portal backend selection, and keyring choice. It is cosmetic and
annoying, not destructive, and the fix (per-DE accounts) is worse than the problem — it recreates
the collision *and* adds permission friction. Documented as expected symptoms.

**Skips itself** when headless, or when the running DE has no tracking mechanism yet.

---

### L2 — AI/dev meta layer (`meta-ai-dev`)

**What it does.** Claude carry-down `CLAUDE.md`, shared skills, agents, statusline. Unchanged by
this decomposition.

**Leaves behind.** `~/.claude/` wiring. Depends on L1a for the loose `role.sh` env-var contract
(`FLEET_ROLE`, `DEV_GLYPH`, `DEV_ACCENT`) and degrades gracefully when absent.

---

## The platform contract

Layers must not each reimplement platform detection. `baseline-shell/platform.sh` exports a fixed
set of variables; **the names and values are the contract**, the same loose-coupling pattern
`role.sh` already uses:

| Variable | Values |
|---|---|
| `PLATFORM_FAMILY` | `debian` · `fedora` · `arch` · `suse` · `unknown` |
| `PLATFORM_PKG` | `apt` · `dnf` · `pacman` · `zypper` · `brew` · `none` |
| `PLATFORM_ATOMIC` | `1` when `/run/ostree-booted` exists, else `0` |
| `PLATFORM_GUI` | `1` when a graphical session/target exists, else `0` |
| `PLATFORM_DE` | `gnome` · `kde` · `cosmic` · `other` · `none` |

**Why `baseline-shell` owns it.** It is the one layer *every* target runs, so later layers can
depend on it without inverting anything. Consumers source it; they don't reimplement it.

**This revises an earlier decision.** The original design had each repo duplicate a two-line
`/run/ostree-booted` check, on the reasoning that a tiny stable probe is cheaper to copy than to
couple. That held for one probe. It does not hold for five facts consumed by three repos, where
copies drift and a wrong answer silently mis-installs. Rationale:
[`decisions/0002`](decisions/0002-multi-distro-multi-de.md).

## Target profiles

| Target | L0 | L0.5 | L1a | L1b | L1c | L2 |
|---|---|---|---|---|---|---|
| Headless LXC / server | `fleet host add` | ✅ | ✅ | ⏭ skip | ⏭ skip | optional |
| Atomic desktop (Bluefin/Aurora/Bazzite) | self-promote | ✅ | ✅ brew branch | ✅ flatpak | ✅ | ✅ |
| Traditional desktop (Fedora/Debian/Arch) | self-promote | ✅ | ✅ native pkg | ✅ flatpak | ✅ | ✅ |
| Handheld (Bazzite) | `fleet host add` | ✅ | ✅ | ✅ `handheld` profile | ✅ | optional |

## Invariants

Rules that must hold after any change. Each has a failure mode attached, because the reason is
easier to remember than the rule.

1. **Every layer is idempotent and independently runnable.** Re-running must converge, not
   accumulate. *Fails as:* duplicated rc blocks, growing config files.
2. **`baseline-setup` holds no layer logic.** *Fails as:* the monolith reassembling itself in a new
   location.
3. **`baseline-access` stays small and public.** *Fails as:* an entry point nobody can realistically
   audit before piping into a shell.
4. **The security gate is structural, not cryptographic.** Everything past L0.5 requires the
   Bitwarden-derived key, because the repos are private. There is no encrypted payload — that buys
   nothing over a private repo and adds key management. *Fails as:* secrets in a public repo behind
   a password.
5. **Headless targets skip graphical layers by detection, not by error.** *Fails as:* LXC bring-up
   that dies partway with a flatpak error.
6. **One fact, one owner.** CLI tools → `baseline-shell`. GUI apps → `baseline-apps`. DE state →
   `baseline-desktop`. Identity → `baseline-access`. Access → fleet. *Fails as:* two layers fighting
   over the same file.
7. **Unsupported distro or DE degrades, never crashes.** An unknown platform runs what it can and
   reports what it skipped. *Fails as:* a new OS being unbootstrappable until someone patches
   detection.

## Where the reasoning lives

| Question | Document |
|---|---|
| Why decompose at all; the layer table | [`decisions/0001`](decisions/0001-baseline-layer-decomposition.md) |
| Multi-distro / multi-DE; the platform contract | [`decisions/0002`](decisions/0002-multi-distro-multi-de.md) |
| dconf vs SaveDesktop ownership | `baseline-desktop/decisions/0001` |
| Migration sequence and deletion gate | [`plans/baseline-decomposition.md`](plans/baseline-decomposition.md) |
| Layer model in the wider workspace | `meta-ai-dev/decisions/0002`, `0003` |
| Recreate-from-code vs restore-from-backup | `meta-ai-dev/references/reproducible-deployments.md` |
