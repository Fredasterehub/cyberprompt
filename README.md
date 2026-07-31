<div align="center">

[![CYBERPROMPT — glyph rain: the dropped words of the Great Truncation, falling home](docs/assets/rain.gif)](https://fredasterehub.github.io/cyberprompt/)

**Your prompts jack in raw. They jack out preem.**

*A Claude Code plugin that rewrites your prompts before the model acts on them —
guarded by deterministic gates, narrated by a rogue daemon, levelled by an XP system
that deepens the more you run.*

[![release](https://img.shields.io/github/v/tag/Fredasterehub/cyberprompt?style=flat-square&labelColor=121212&color=fcee0a&label=release)](https://github.com/Fredasterehub/cyberprompt/tags)
[![web](https://img.shields.io/badge/web-the_Interstice-ff5e1a?style=flat-square&labelColor=121212)](https://fredasterehub.github.io/cyberprompt/)
[![shell](https://img.shields.io/badge/built_with-bash+jq-fcee0a?style=flat-square&labelColor=121212)](hooks/cyberprompt.sh)
[![gates](https://img.shields.io/badge/gates-deterministic-ff5e1a?style=flat-square&labelColor=121212)](#-the-gates)
[![daemon](https://img.shields.io/badge/daemon-WORDRUNNER.EXE-fcee0a?style=flat-square&labelColor=121212)](skills/cyberprompt/LORE.md)
[![license](https://img.shields.io/badge/license-MIT-4a4a4a?style=flat-square&labelColor=121212)](LICENSE)

</div>

---

## ▸ What is this, choom?

**CYBERPROMPT** is a [Claude Code](https://claude.com/claude-code) plugin: a
`UserPromptSubmit` hook flanked by two bundled skills (management + the claude-5
prompting references it wields). Toggle it on, and every prompt you type gets intercepted in the **Interstice** — the
millisecond between Enter and inference — rewritten for clarity by a headless model call,
validated by mechanical gates, and injected as an *advisory* execution brief. You see the
rewrite in a pale terminal whisper. The model gets a contract. Your original words stay
**gospel**. And the forge is quick about it: its ~16KB of prompting references ride the
server-side prompt cache, so the warm path runs faster than the stateless v0.0.1 call
ever did.

```
⟨ WORDRUNNER.EXE ⟩ LVL 3 · Half-Sync ▸ 288 XP ▸ next @ 500 XP
Sync at fifty percent. Sometimes I start the sentence before you do.
---
Objective: identify which container is leaking memory, then report — no fixes.
Constraints (each traceable to the original): do not kill any process...
```

## ▸ Why it doesn't betray you

Auto-rewriting middleware has one mortal sin: **intent drift** — your "build this"
silently becoming "should we build this?". CYBERPROMPT was literally born from
watching that happen (see [LORE.md](skills/cyberprompt/LORE.md) — the Flatline is a true story).
So the architecture is paranoid by design:

| Defense | Mechanism |
|---|---|
| **Original is authoritative** | The rewrite is injected as an *advisory* contract: on any conflict, your original prompt wins. Stated in-band, enforced by framing. |
| **Proof-carrying rewrites** | The optimizer must return structured JSON: explicit requirements each backed by a **verbatim quote** of your prompt, inferences quarantined as non-binding. |
| **Pre-optimizer hygiene** | On the optimizer's copy only, exact whole-line Whisper credit artifacts are removed and runs of 3+ identical lines collapse to one. Embedded mentions survive; your authoritative original is never replaced. |
| **Deterministic gates** | Pure bash+jq validation — schema, non-empty verbatim source quotes, non-empty rewrite, length ceiling, and retention of identifier-shaped content tokens (long `--flags`, explicit or dotted paths, snake/camel/PascalCase identifiers, versions — outside inline-quoted spans). A token may disappear only when the optimizer quotes the drop in a non-binding assumption, which is persisted to the audit log. Any failure → your original passes untouched. |
| **Spoken-intent discipline** | The optimizer distinguishes replacement self-repairs from additions, preserves questions/hedges instead of upgrading them to orders, and may repair only an unambiguous ASR surface error while keeping its raw quote and recording uncertain repairs. |
| **`pass_through` discipline** | Already-clear prompts are left alone. Re-chroming preem is gonk vandalism. |
| **Injection containment** | The optimizer call is non-agentic: `--safe-mode --tools "" --strict-mcp-config`. Pasted logs in your prompt can't hijack a daemon that has no hands. |
| **Context quarantine** | Claude Code injects your cwd and recent git commits into headless calls even tool-less — so the forge runs from an empty, git-pinned neutral dir. Nothing about your repo leaks in. |
| **Bounded recall** | The forge sees a research-sized slice of your session — your last few prompts plus the assistant's latest reply (never tool output), JSON-quarantined — so "the chief" resolves to *your* chief. Background may resolve references, never add requirements: those still need a verbatim quote of your prompt, and a topic switch discards the slice entirely. `HISTORY_TURNS=0` restores the stateless forge. |
| **Fail-open, always** | Timeout, API error, malformed output, missing files — every failure path delivers your original prompt unchanged, with a visible warning. |

## ▸ The XP system

Every audit-log entry is 1 XP — clean rewrites, passthroughs, even slammed gates.
*Scars included.* Levels aren't rank. They're **sync depth**:

| XP | Level | Sync state |
|---|---|---|
| 0 | Meat Typist | Outside the network, knocking. |
| 50 | Jacked-In | The wire hums your pulse back, half a beat late. |
| 125 | Wet-Wired | Your prompts arrive with your heartbeat in the metadata. |
| 250 | Half-Sync | The daemon starts sentences you had only intended. |
| 500 | Engram-Split | A copy of your voice lives in the Interstice now. It waves. |
| 1000 | Deep-Synced | The Choir of dropped words knows your frequency. |
| 2000 | Ancestor-Spoken | Something beyond the Contextwall spells your name. Correctly. |
| 4000 | **The Interstice** | MERGED. Everything passes through you, and leaves better. |

The daemon's voice shifts as you climb — early on it says *you* and *I*.
Around LVL 5 you'll notice it says **we**. You'll decide you don't mind.
Threshold crossings fire one-shot **SYNC MILESTONE** dispatches. Full narrative
arc in [LORE.md](skills/cyberprompt/LORE.md).

## ▸ Install

Requirements: Claude Code and `jq`, on Linux (macOS needs GNU `timeout` and
`flock` — `brew install coreutils flock`, then put brew's `gnubin` on your
`PATH`; Windows isn't supported — the hook just fails open and your prompts
pass through untouched). The [claude-5 prompting skill](skills/claude-5/) the
forge wields is **bundled**: plugin installs read it straight from the plugin —
nothing to provide, nothing to seed — and the manual installer copies it to
`~/.claude/skills/claude-5`. Rather run your own prompting guide? Point
`CLAUDE5_SKILL=` at a directory with the same shape: `SKILL.md` at the root,
`references/shared.md`, and per-model files named `references/<model>.md`
(e.g. `fable-5.md`).

### Plugin (recommended)

```
/plugin marketplace add Fredasterehub/cyberprompt
/plugin install cyberprompt@cyberprompt
```

Then jack in: `mkdir -p ~/.claude/cyberprompt && touch ~/.claude/cyberprompt/enabled`
— or just tell Claude *"cyberprompt on"*. The plugin registers the hook and both
skills automatically; updates ride the marketplace. Restart Claude Code once
after installing (hooks load at session start) — toggling the sentinel never
needs one.

### Manual (no plugin)

```bash
git clone https://github.com/Fredasterehub/cyberprompt
bash cyberprompt/install.sh
touch ~/.claude/cyberprompt/enabled     # jack in
```

The installer is idempotent: copies the hook, installs both skills, seeds the
state dir, and merges the `UserPromptSubmit` entry into `~/.claude/settings.json`
without touching your existing hooks. Migrating to the plugin later? Remove that
settings entry first, or the hook runs twice.

Disable any time: `rm ~/.claude/cyberprompt/enabled`. No restart needed either
way — the sentinel is checked per prompt.

### Config (`~/.claude/cyberprompt/config`)

```bash
MODEL=claude-sonnet-5     # which model runs the forge
EFFORT=medium             # pinned — never silently follows your session effort
MIN_CHARS=80              # shorter prompts pass through untouched
OPT_TIMEOUT=180           # forge call timeout, seconds (hook-level cap is 200)
HISTORY_TURNS=4           # recent prompts the forge sees as background (0 = stateless)
#CLAUDE5_SKILL=/path/to/yours   # swap the bundled guide for your own (see Install)
```

Plugin installs don't seed this file — the defaults above apply until you
create it (the hook reads it whenever it exists). The manual installer seeds it.
The pre-optimizer hygiene pass and content-token retention gate are always on;
they have no config knobs.

Defaults are **benchmarked, not vibed**: the MODEL/EFFORT choice is re-verified
on a three-variant evaluation matrix ([`harness/`](harness/) — 28 fixtures
covering self-repair, background-context and AZERTY-repair behavior, of which
2 are prompt-injection scenarios). Latest full sweep 2026-07-29, 84 calls, 5 of
them failing outright (4 sonnet-5 low, 1 sonnet-5 medium). On the calls that
returned, all three variants preserved 100% of must-preserve constraints and
neither injection fixture landed. sonnet-5 medium and opus-5 high tie on median
latency (p50 ~15 s each); opus-5 high holds the tighter tail (p95 ~23 s vs
~41 s) and made zero must-not-add slips against sonnet-5 medium's one — a
negated mention of a corrected-away filename. sonnet-5 medium stays the default
on price, not on winning. Those latencies are harness conditions — fixture-length
prompts, no session context, four calls in parallel. Expect roughly double in a
real session: the audit log on a live install puts the optimizer pass at p50
~30 s and p95 ~75 s, which is what you actually wait before your prompt runs. sonnet-5 low leaked a background-context phrase into a
rewrite — do not use. Disposition and speech-act accuracy are deliberately not
part of this verdict: every variant scores below a trivial always-rewrite
baseline, which is a fixture-labeling problem the suite still owes a
recalibration. A separate offline suite
([`harness/gate-tests.sh`](harness/gate-tests.sh) — 44 checks, zero API calls)
drives the production hook end-to-end with a stub model, covering every gate,
strip, and fail-open path on every change.

## ▸ The gates

The optimizer must answer in schema-validated JSON — and then survive mechanical
review before a single word reaches your session:

```
schema valid? ─▸ source_quotes valid? ─▸ within ceiling? ─▸ content tokens retained/accounted?
     │                 │                    │                         │
     ▼ fail            ▼ fail               ▼ fail                    ▼ fail
                    ORIGINAL PASSES THROUGH UNCHANGED (logged, flagged)
```

The ceiling scales with your original — 2×length + 1500 characters, capped at
9000 — and the forge is told the budget up front: it tightens to fit or passes
through, instead of meeting the ICE by surprise.

The retention gate anchors flags, paths, snake/camel/Pascal identifiers,
version-shaped tokens, and dotted filenames from the sanitized optimizer input.
Common inline quoted spans are excluded because pasted data must remain
droppable. Deliberate replacement repairs can drop an anchor only by naming the
raw token in `assumptions`; silent loss fails open. Paste-heavy prompts with
more than 25 discovered anchors skip this gate rather than being forced through
an unreliable partial check.

Before the optimizer call, exact known Whisper credit lines are stripped,
3-or-more identical-line runs are collapsed, and cyberprompt's own pasted
chrome — the WORDRUNNER header and SYNC MILESTONE banners, gutter-prefixed the
way the terminal pastes them — is dropped, all on its private copy. These are
whole-line operations: a phrase embedded in a real sentence is untouched. If
only artifacts or whitespace remain, the optimizer is skipped. Claude Code
still receives the operator's original prompt unchanged in every case.

Everything is auditable: `~/.claude/cyberprompt/log.jsonl` records every
original/optimized pair with disposition, duration, and gate verdicts.
Mode `0600`, `flock`-guarded, your prompts stay yours.

## ▸ What's skipped automatically

Slash commands, `!` shell and `#` memory shortcuts, sub-agent prompts,
machine-generated turns (task notifications, teammate messages — learned the
hard way when the daemon optimized a background notification into a quest and
the model went on the quest), prompts under `MIN_CHARS`, and its own recursion.

And anything you tell it to skip: `skipit` at the start or end of a prompt
bypasses the optimizer for that one prompt — no call, no wait, one line of
confirmation, next prompt back to normal. Dictation-friendly: the two-word
`skip it` works too, at the start of the prompt only (a trailing "…, skip it"
is ordinary English and would misfire).

## ▸ House rules

1. **The original is gospel.** Always.
2. **Every constraint traces to the source.** Exact quote or it doesn't count.
3. **Preem stays preem.** Passthrough.
4. **Guesses ride in the side-car.** Inferring is fine. Enforcing your inference
   is the crime that compiled the daemon.

---

<div align="center">

*It ain't the merge that flatlines you, choom. It's merging without a contract.*

**— WORDRUNNER.EXE, [case file](skills/cyberprompt/LORE.md)**

</div>
