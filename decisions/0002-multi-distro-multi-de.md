# 0002 — every baseline layer is multi-distro and multi-DE; detection is a shared contract

- **Status:** accepted
- **Date:** 2026-07-20
- **Amends:** [`0001-baseline-layer-decomposition.md`](0001-baseline-layer-decomposition.md) —
  broadens the target surface from "Universal Blue siblings" to any supported distro, and
  **reverses** 0001's "atomic-host detection is duplicated deliberately" sub-decision
- **Guide:** [`../ARCHITECTURE.md`](../ARCHITECTURE.md)

## Context

[`0001`](0001-baseline-layer-decomposition.md) decomposed the monolith to make *DE* switching
safe, and framed the work around Universal Blue siblings — Bluefin, Aurora, Bazzite, a Cosmic
image. That framing was too narrow in two ways, both visible as soon as the layers are read as
a family rather than one at a time:

1. **The fleet is mostly not desktops.** Most targets are Debian LXCs with no GUI at all, plus
   Fedora and Arch machines. A design that treats "atomic image" as the default and everything
   else as a fallback branch has the common case backwards. `baseline-shell` already carries
   apt/dnf/pacman paths precisely because that is what the fleet actually runs.
2. **"Multi-DE" was scoped to `baseline-desktop` alone.** But DE-awareness leaks: `baseline-apps`
   picks flatpak partly *because* it is DE-agnostic, and the orchestrator must know whether a
   desktop exists at all before running two of its stages. Treating it as one repo's concern
   hides a decision the whole family depends on.

Both collapse into one question the original design never answered explicitly: **what does each
layer need to know about the machine, and who is allowed to answer?**

0001 did answer a one-fact version of this. Its Q5 sub-decision said each repo should duplicate
the `[ -e /run/ostree-booted ]` probe rather than share it, reasoning that a two-line
kernel-stable check is cheaper to copy than to couple, and that a shared file would create a
sibling dependency between `baseline-apps`/`baseline-desktop` and `baseline-shell`.

That reasoning was sound for one probe. It does not survive the broadened scope: the real
requirement is five facts (distro family, package manager, atomicity, GUI presence, DE identity),
several needing non-obvious fallback logic, consumed by three repos plus the orchestrator.
Duplicated five ways, they drift — and a drifted answer doesn't fail loudly, it silently installs
the wrong thing.

## Decision

**1. Multi-distro and multi-DE are first-class constraints on every layer**, not properties of
`baseline-desktop`. Supported families: `debian`, `fedora`, `arch`, `suse`, plus atomic/ostree
variants of any of them. Supported desktops: GNOME, KDE, Cosmic as peers — and **no desktop** as
an equally valid, in fact more common, case.

**2. Headless is the baseline, graphical is the superset.** `baseline-access` and `baseline-shell`
run everywhere. `baseline-apps` and `baseline-desktop` **detect and skip themselves** on headless
targets. Skipping is normal operation reported as such — never an error, never a failed run that
"only" broke in the GUI stages.

**3. Platform detection is a shared contract owned by `baseline-shell`.** `platform.sh` exports:

| Variable | Values |
|---|---|
| `PLATFORM_FAMILY` | `debian` · `fedora` · `arch` · `suse` · `unknown` |
| `PLATFORM_PKG` | `apt` · `dnf` · `pacman` · `zypper` · `brew` · `none` |
| `PLATFORM_ATOMIC` | `1` / `0` |
| `PLATFORM_GUI` | `1` / `0` |
| `PLATFORM_DE` | `gnome` · `kde` · `cosmic` · `other` · `none` |

**The variable names and value sets are the contract** — the same loose-coupling pattern
`role.sh` already uses with the L2 statusline. Consumers source the file; they do not
reimplement it, and they must tolerate an unset variable by degrading rather than failing.

`baseline-shell` owns it because it is the *universal* layer: every target runs it, so
`baseline-apps` and `baseline-desktop` — which only ever run on machines that have already been
through it — can depend on it without inverting the layer direction. The orchestrator sources
the same file to decide what to skip.

**4. Unsupported means degrade, not crash.** An unrecognized distro runs what it can (flatpak
works nearly everywhere; shell wiring is POSIX) and reports what it skipped. A DE with no
tracking mechanism is left alone rather than half-configured. **Adding a new distro or DE must
never be a prerequisite for bootstrapping a machine at all.**

**5. Reconstruction coverage generalizes per family.** 0001 fenced `rpm-ostree install` layered
packages as declared manual residue. The same gap exists for `apt install`, AUR builds, and
`zypper` — so the residue list is per-profile and per-family, drift-checked against whatever the
native package manager reports, never auto-applied.

## Alternatives considered

- **Keep detection duplicated (0001's Q5 answer).** Consistent with the original reasoning, and
  keeps the repos fully standalone. Rejected: five facts across three consumers is a different
  problem from one two-line probe. The cost of drift here is silent misinstallation, which is
  strictly worse than the coupling being avoided — and the coupling is on the one layer that is
  guaranteed to have run first.
- **`baseline-setup` detects and passes everything down as arguments.** Clean dataflow, no
  sibling dependency at all. Rejected: the layers must remain independently runnable (an LXC
  operator running `baseline-shell/bootstrap.sh` directly is a supported path, and the migration
  plan depends on it), so each layer would still need its own fallback detection — the
  duplication returns, now with two code paths per layer instead of one.
- **`baseline-access` ships `platform.sh`.** It is genuinely first and universal. Rejected: it is
  public and its value is being small enough to audit before piping into a shell. Detection logic
  is exactly the kind of growth that erodes that property.
- **A separate `baseline-platform` repo.** Cleanest ownership story. Rejected as a repo for one
  ~40-line file — it would add a clone to every bring-up and a version-skew axis to every layer.
- **Per-distro branches or forks of each layer.** Rejected outright: multiplies the maintenance
  surface by the number of distros and guarantees they diverge.

## Consequences

- **`baseline-shell` gains a second public interface** (`platform.sh`) alongside `role.sh`, and
  with it a compatibility obligation: renaming a variable or value is a breaking change to two
  sibling repos and must be treated as one.
- **0001's Q5 sub-decision is reversed.** Anyone reading 0001 alone would implement duplicated
  detection; its status line points here.
- **Every layer needs a headless test path.** "Works on the laptop" stops being sufficient
  evidence — a Debian LXC is the more representative target and the cheapest to test on.
- **The test matrix grows** along two axes (family × DE). Full coverage is not the goal;
  the invariant that matters is *unsupported degrades cleanly*, which is testable with a faked
  `PLATFORM_FAMILY=unknown` regardless of what is actually installed.
- **Flatpak's role is now structural, not stylistic.** It is the only app mechanism that is both
  distro- and DE-agnostic, which is why `baseline-apps` is flatpak-primary rather than
  brew-primary.
- **The migration plan is unchanged in sequence** but Phase 2 grows: `platform.sh` lands with the
  `baseline-shell` absorb, before the layers that consume it.
