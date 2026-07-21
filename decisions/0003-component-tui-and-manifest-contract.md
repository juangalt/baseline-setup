# 0003 — `baseline-setup` is a component picker over per-layer manifests, not a hardcoded menu

- **Status:** accepted
- **Date:** 2026-07-20
- **Amends:** [`0001`](0001-baseline-layer-decomposition.md) — refines the "orchestrator holds no
  layer logic" invariant into "holds no *hardcoded layer knowledge*; it renders declared
  manifests"; and [`0002`](0002-multi-distro-multi-de.md) — the manifest gating reuses the
  `platform.sh` contract
- **Guide:** [`../ARCHITECTURE.md`](../ARCHITECTURE.md) (§ Component manifest contract)

## Context

The operator wants `baseline-setup` to be the single entry point to the whole family and to offer
an interactive picker — tick which components of each layer to install, then install them. That is
a good front door for a fresh laptop. It also walks straight into the invariant 0001 fought hardest
to establish.

**The trap.** A picker that *knows* "baseline-shell has {zsh, tmux, starship, hermes-aliases};
baseline-apps has {these flatpaks}" is layer logic living in the orchestrator. Every time a layer
gains a component, `baseline-setup` changes too — and the coupling three ADRs removed comes back
through the menu. That is invariant 2 (*"holds no layer logic — fails as: the monolith reassembling
itself in a new location"*) failing in a new costume.

Two further constraints the naive picker ignores:

- **Reproducibility.** A TUI that installs and forgets violates the workspace's reproducible-by-
  default convention (`meta-ai-dev/decisions/0007`). What got installed must survive as an artifact.
- **Headless.** Most of the fleet has no TTY. A picker cannot be the *only* way in, or LXC bring-up
  hangs at a menu (invariant 5).

## Decision

**A component-manifest contract plus a single apply engine. The TUI is a front-end that produces a
selection; it is never a second install path.** This is the same indirection that fixed platform
detection in 0002: the orchestrator owns a *schema*, never the *contents*.

### 1. Each layer ships a manifest

A `manifest.toml` at each consumable layer's repo root declares that layer's selectable components:

```toml
# baseline-shell/manifest.toml
[[component]]
id       = "zsh-default"
label    = "zsh as default shell"
desc     = "chsh + rc wiring"
default  = true

[[component]]
id       = "hermes-aliases"
label    = "Hermes agent aliases"
desc     = "shell hooks for the Hermes CLI"
default  = false

[[component]]
id       = "gui-flatpaks-laptop"
label    = "Laptop app profile"
requires = { gui = true }          # gated on PLATFORM_GUI — auto-hidden when headless
```

Fields: `id`, `label`, `desc`, `default` (bool), optional `requires` (a predicate over the
`platform.sh` variables — `gui`, `atomic`, `family`), optional `needs`/`conflicts` (other `id`s).
**The manifest owns metadata only — never install logic.**

### 2. Each layer's installer accepts a selection

The installer already owns *how* to install; it gains one input: `--components <id,id,…>` (install
exactly these) with its existing default-run as the fallback. `baseline-setup` passes each layer
only the ids drawn from *that layer's own manifest*. The contract is two halves, both owned by the
layer: **it declares its ids, and it consumes its ids.**

### 3. `baseline-setup` renders, collects, and applies — via one engine

- **Reads** every layer's `manifest.toml`, filters each component through `platform.sh`
  (headless auto-hides `requires.gui`, non-atomic hides `requires.atomic`, etc.), and renders a
  **gum** checklist grouped by layer, seeded from `default` + any existing selection.
- **Writes** the ticked ids to a selection file (`~/.config/baseline-setup/selected.toml`, or a
  named `--profile`). This file is the reproducible artifact.
- **Applies** by invoking each layer's installer with its slice — the **apply engine**.

**The TUI has no install path of its own.** `baseline-setup` (bare) → picker → write selection →
apply engine. `baseline-setup --profile laptop --yes` → apply engine, same code, no gum. One
engine, two front-ends — which is what makes "TUI-first" safe despite its acknowledged parity risk.

### 4. gum is the toolkit, bootstrapped only on the interactive path

A single static Go binary, fetched checksum-verified to `~/.local/bin` as step 0 of the
*interactive* run (or `brew`/native where present). The headless path (`--profile … --yes`) never
touches gum, so an LXC needs neither a TTY nor the binary. If stdin is not a TTY and no `--profile`
is given, `baseline-setup` errors with the `--profile` hint rather than hanging.

## Alternatives considered

- **Hardcoded menu in `baseline-setup`.** Simplest to write, and exactly the monolith-in-the-TUI
  failure. Rejected on invariant 2.
- **TUI installs directly; `--profile` is a separate replay path.** The literal reading of
  "TUI-first". Rejected: two code paths that drift — the operator's acknowledged risk. Folding both
  into one apply engine keeps the friendly front door without the drift.
- **Declarative-first (profile is primary; TUI is an optional editor).** Cleaner reproducibility
  story, but a worse fresh-laptop experience, and the operator chose TUI-first. The single-apply-
  engine design recovers the reproducibility (every run still writes the selection file) without
  demoting the picker.
- **A dependency-heavy TUI (Python Textual).** Richer, but forces Python + uv onto every
  interactive target before baseline-shell has run. gum is one self-contained binary. Rejected on
  the early-run dependency cost.
- **whiptail/dialog.** Zero-bootstrap where present, but absent on minimal images and visually
  poor; the checklist ergonomics for many grouped components are weak. gum bootstraps cleanly and
  only on the path that needs it.
- **A central component registry in `baseline-setup`.** One file listing every layer's components.
  Rejected: it is the hardcoded menu with extra steps — the registry drifts from the layers exactly
  as a menu would.

## Consequences

- **Invariant 2 is reworded** (see ARCHITECTURE): the orchestrator may know the *manifest schema*,
  never a layer's component *contents*. A hardcoded component id in `baseline-setup` is now the
  smell to catch in review.
- **Every consumable layer gains two obligations:** ship a `manifest.toml`, and accept
  `--components`. This lands in each layer's own migration phase (2/3/4), not as a big-bang.
- **`baseline-setup` gains real code** — a manifest reader, a gum renderer, the apply engine, a
  selection-file format — and with it a test suite (mock manifests + `--profile --yes` golden runs).
  It is still not *layer* logic; the boundary moves from "no code" to "no hardcoded layer knowledge".
- **Reproducibility is preserved under TUI-first:** every install, interactive or not, leaves a
  selection file that `--profile` can replay. A machine's exact component set is recoverable.
- **Headless is unaffected:** the fleet path is `--profile <name> --yes`, no gum, no TTY, and
  GUI-gated components never appear in a headless selection anyway.
- **The manifest is the natural home for the guaranteed-roster / residue metadata** each layer
  already owes (0001/0002), so the two contracts reinforce rather than duplicate each other.
- **Ordering still holds:** the apply engine runs the selected components in the fixed L0.5 → L1a →
  L1b → L1c → L2 stage order; the picker changes *what* runs within a stage, never the sequence.
