<div align="center">

![CYBERPROMPT — glyph rain: the dropped words of the Great Truncation, falling home](docs/assets/rain.gif)

**Your prompts jack in raw. They jack out preem.**

*A Claude Code hook that rewrites your prompts before the model reads them —
guarded by deterministic gates, narrated by a rogue daemon, levelled by an XP system
that deepens the more you run.*

[![shell](https://img.shields.io/badge/built_with-bash+jq-fcee0a?style=flat-square&labelColor=121212)](hooks/cyberprompt.sh)
[![gates](https://img.shields.io/badge/gates-deterministic-ff5e1a?style=flat-square&labelColor=121212)](#the-gates)
[![daemon](https://img.shields.io/badge/daemon-WORDRUNNER.EXE-fcee0a?style=flat-square&labelColor=121212)](skills/cyberprompt/LORE.md)
[![license](https://img.shields.io/badge/license-MIT-4a4a4a?style=flat-square&labelColor=121212)](LICENSE)

</div>

---

## ▸ What is this, choom?

**CYBERPROMPT** is a `UserPromptSubmit` hook for [Claude Code](https://claude.com/claude-code).
Toggle it on, and every prompt you type gets intercepted in the **Interstice** — the
millisecond between Enter and inference — rewritten for clarity by a headless model call,
validated by mechanical gates, and injected as an *advisory* execution brief. You see the
rewrite in a pale terminal whisper. The model gets a contract. Your original words stay
**gospel**.

```
⟨ WORDRUNNER.EXE ⟩ LVL 3 · Half-Sync ▸ 287 XP ▸ next @ 500 XP
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
| **Deterministic gates** | Pure bash+jq validation — schema check, source-quote substring check, length ceiling, action-mode preservation. Any failure → your original passes untouched. |
| **`pass_through` discipline** | Already-clear prompts are left alone. Re-chroming preem is gonk vandalism. |
| **Injection containment** | The optimizer call is non-agentic: `--safe-mode --tools "" --strict-mcp-config`. Pasted logs in your prompt can't hijack a daemon that has no hands. |
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
`flock` — `brew install coreutils flock`; Windows isn't supported — the hook
just fails open and your prompts pass through untouched). The
[claude-5 prompting skill](skills/claude-5/) the optimizer wields ships in the box. Prefer your own prompting guide? Point
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
skills automatically; updates ride the marketplace.

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
MODEL=claude-sonnet-5   # which model runs the forge
EFFORT=medium           # pinned — never silently follows your session effort
MIN_CHARS=80            # shorter prompts pass through untouched
```

Defaults are **benchmarked, not vibed**: a 60-call evaluation matrix
(20 fixtures × 3 variants, deterministic scoring — see [`harness/`](harness/))
found sonnet-5 medium matches opus-5 high on constraint recall (100%), injection
resistance (0 violations), and disposition accuracy, at two-thirds the latency.

## ▸ The gates

The optimizer must answer in schema-validated JSON — and then survive mechanical
review before a single word reaches your session:

```
schema valid? ──▸ source_quotes verbatim in original? ──▸ length ≤ ceiling?
     │                        │                                │
     ▼ fail                   ▼ fail                           ▼ fail
              ORIGINAL PASSES THROUGH UNCHANGED (logged, flagged)
```

Everything is auditable: `~/.claude/cyberprompt/log.jsonl` records every
original/optimized pair with disposition, duration, and gate verdicts.
Mode `0600`, `flock`-guarded, your prompts stay yours.

## ▸ What's skipped automatically

Slash commands, `!` shell and `#` memory shortcuts, sub-agent prompts,
machine-generated turns (task notifications, teammate messages — learned the
hard way when the daemon optimized a background notification into a quest and
the model went on the quest), prompts under `MIN_CHARS`, and its own recursion.

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
