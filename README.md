<div align="center">

[![CYBERPROMPT — glyph rain: the dropped words of the Great Truncation, falling home](docs/assets/rain.gif)](https://fredasterehub.github.io/cyberprompt/)

**Your prompts jack in raw. They jack out preem.**

*One public repo, two native plugins: Claude Code and Codex CLI. Each rewrites your
prompts before the model acts on them — guarded by deterministic gates, narrated by
a rogue daemon, and levelled by an XP system that deepens the more you run.*

[![release](https://img.shields.io/github/v/tag/Fredasterehub/cyberprompt?style=flat-square&labelColor=121212&color=fcee0a&label=release)](https://github.com/Fredasterehub/cyberprompt/tags)
[![web](https://img.shields.io/badge/web-the_Interstice-ff5e1a?style=flat-square&labelColor=121212)](https://fredasterehub.github.io/cyberprompt/)
[![codex](https://img.shields.io/badge/Codex_CLI-GPT--5.6_Sol-fcee0a?style=flat-square&labelColor=121212)](#codex-cli)
[![claude](https://img.shields.io/badge/Claude_Code-Claude_5-ff5e1a?style=flat-square&labelColor=121212)](#claude-code)
[![shell](https://img.shields.io/badge/built_with-bash+jq-fcee0a?style=flat-square&labelColor=121212)](hooks/cyberprompt.sh)
[![gates](https://img.shields.io/badge/gates-deterministic-ff5e1a?style=flat-square&labelColor=121212)](#-the-gates)
[![daemon](https://img.shields.io/badge/daemon-WORDRUNNER.EXE-fcee0a?style=flat-square&labelColor=121212)](skills/cyberprompt/LORE.md)
[![license](https://img.shields.io/badge/license-MIT-4a4a4a?style=flat-square&labelColor=121212)](LICENSE)

</div>

---

## ▸ What is this, choom?

**CYBERPROMPT** ships native bundles for [Codex CLI](https://developers.openai.com/codex/)
and [Claude Code](https://claude.com/claude-code). Each bundle pairs a
`UserPromptSubmit` hook with two skills: one manages the daemon, while the other
holds model-specific prompting guidance. Toggle it on, and every prompt you type gets intercepted in the **Interstice** — the
millisecond between Enter and inference — rewritten for clarity by a headless model call,
validated by mechanical gates, and injected as an *advisory* execution brief. You see the
rewrite in a pale terminal whisper. The model gets a contract. Your original words stay
**gospel**. And the forge knows when to hold its tongue: passthrough is the
presumption, and a rewrite has to name the specific defect it repairs — or say
nothing at all. When you'd rather it not even look, one word (`skipit`) stands
it down for that prompt. On Claude Code, ~16KB of prompting references ride the
server-side prompt cache. On Codex, the forge gets one compact, release-tested Sol
contract with every tool disabled. Different jacks, same paranoia.

| Surface | Automatic forge | Bundled skills | Independent state |
|---|---|---|---|
| **Codex CLI** | GPT-5.6 Sol, `low` effort | [`$cyberprompt:cyberprompt`](plugins/cyberprompt/skills/cyberprompt/) + [`$cyberprompt:gpt-5-6-sol`](plugins/cyberprompt/skills/gpt-5-6-sol/) | `~/.codex/cyberprompt` (or `$CODEX_HOME/cyberprompt`) |
| **Claude Code** | Claude Sonnet 5, `medium` effort | [`cyberprompt`](skills/cyberprompt/) + [`claude-5`](skills/claude-5/) | `~/.claude/cyberprompt` |

The automatic part is the plugin hook. A skill by itself can teach a model how to
write or manage prompts, but it cannot intercept every submitted prompt on either
host. That distinction matters: seeing `$cyberprompt:cyberprompt` in Codex does **not** mean the
forge is active; the plugin must be enabled, its command hook trusted, and its
sentinel present.

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
| **`pass_through` discipline** | Passthrough is the *presumption*: a rewrite must name the one defect it repairs (a bound referent, a discarded self-correction, a hoisted buried constraint, dictation damage, or a settled ambiguity) in a machine-checked `rewrite_warrant` field — "made it clearer" is not a warrant, and a rewrite claiming none is rejected. Re-chroming preem is gonk vandalism. |
| **No invented caution** | The optimizer may never add confirm-first, ask-if-unclear, or avoid-irreversible-actions language you didn't write. How much risk to take is your call, already made: "then push it" stays "then push it". |
| **Injection containment** | Both optimizer calls are non-agentic. Claude runs with `--safe-mode --tools "" --strict-mcp-config`; Codex runs ephemerally in a read-only sandbox with user config, rules, web, apps, shell, computer use, image generation, and multi-agent features disabled. Pasted logs can't hijack a daemon that has no hands. |
| **Context quarantine** | The forge runs from an empty, git-pinned neutral dir, not your project. Claude's injected cwd/git context is displaced; Codex ignores user config and repo rules for the nested call. Nothing about your repo becomes an optimizer requirement. |
| **Bounded recall** | The forge sees a research-sized slice of your session — your last few prompts plus the assistant's latest reply (never tool output), JSON-quarantined — so "the chief" resolves to *your* chief. Background may resolve references, never add requirements — those still need a verbatim quote of your prompt (mechanically gated) — and the forge is instructed to discard the slice on a topic switch. `HISTORY_TURNS=0` restores the stateless forge. |
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

Both builds require modern Bash, `jq`, GNU `timeout`, and `flock`; `git` is
used to pin the neutral forge directory (without it the context quarantine
degrades rather than blocking — install it anyway). Linux
is the supported platform. On macOS, install modern Bash plus the GNU tools
(`brew install bash coreutils flock`) and ensure Homebrew's `bash` and
`coreutils` `gnubin` precede the system versions on `PATH`. Windows is not
supported; a missing dependency makes the hook fail open and the original
prompt continues unchanged.

<a id="codex-cli"></a>

### Codex CLI

Requirements: an authenticated Codex CLI with plugin and `UserPromptSubmit`
hook support. This build targets `codex-cli 0.146.0`; a later compatible build
must still expose `codex plugin`, `/plugins`, and `/hooks` plus the nested
`codex exec` flags used by the forge.

#### Plugin (recommended)

```bash
codex plugin marketplace add Fredasterehub/cyberprompt --ref main
codex plugin add cyberprompt@cyberprompt
```

Start a new Codex session after installation; plugin hooks load at session
start. Open `/hooks`, inspect the bundled `UserPromptSubmit` command, and
explicitly trust it. Installing or enabling a plugin does **not** auto-trust its
command hooks.

`/plugins` is the coarse bundle switch: select **CYBERPROMPT** and press Space
to enable or disable the plugin and its skills. The sentinel is the hot switch
for the optimizer alone, so skills can stay installed and no session restart is
needed.

Jack in:

```bash
CYBERPROMPT_CODEX_STATE="${CODEX_HOME:-$HOME/.codex}/cyberprompt"
umask 077
mkdir -p "$CYBERPROMPT_CODEX_STATE"
chmod 700 "$CYBERPROMPT_CODEX_STATE"
touch "$CYBERPROMPT_CODEX_STATE/enabled"
```

Check the hot-switch state:

```bash
CYBERPROMPT_CODEX_STATE="${CODEX_HOME:-$HOME/.codex}/cyberprompt"
test -f "$CYBERPROMPT_CODEX_STATE/enabled" && echo on || echo off
```

Stand down without removing either skill:

```bash
CYBERPROMPT_CODEX_STATE="${CODEX_HOME:-$HOME/.codex}/cyberprompt"
rm -f "$CYBERPROMPT_CODEX_STATE/enabled"
```

Or ask Codex: *"Use `$cyberprompt:cyberprompt` to turn CYBERPROMPT on"*, *"...off"*, or
*"Use `$cyberprompt:cyberprompt` to show CYBERPROMPT status"*. Status reports the sentinel,
active model, forge settings, audit count, latest event and recent errors; when
the host exposes it, it also reports hook trust. `skipit` still bypasses just
one prompt.

#### Codex config (`${CODEX_HOME:-$HOME/.codex}/cyberprompt/config`)

```bash
MODEL=gpt-5.6-sol         # the only supported forge model in this release
EFFORT=low                # pinned — never silently follows session effort.
                          # low/medium are the release-tested settings; higher
                          # tiers are accepted but unmeasured on this harness
MIN_CHARS=80              # shorter prompts pass through untouched
OPT_TIMEOUT=180           # forge timeout, seconds (hook-level cap is 200)
HISTORY_TURNS=4           # recent turns used only to resolve references (0 = stateless)
```

Plugin installs do not seed this file; those defaults apply until you create
it. The Codex hook parses it as data, never sources it as shell. State is wholly
separate from Claude Code: the toggle, config, `log.jsonl`, `error.log`, neutral
forge directory, and optional `instruction.txt` override all live beneath the
Codex state root. Never point it at `~/.claude/cyberprompt`.

Sol `low` is the initial default because prompt normalization is a bounded,
latency-sensitive transformation and `low` is also Codex CLI's Sol default.
It is a release choice, not a claim that low always wins: move to `medium` only
when representative harness cases show a quality gain worth the extra latency.
The active outer session must also be `gpt-5.6-sol` (or the `gpt-5.6` alias);
on another model the forge fails open instead of silently optimizing for the
wrong target.

The [release smoke](harness/codex-eval-20260731.md) compared six fixed fixtures
at both efforts (12 real calls) with
[`harness/run-codex.sh`](harness/run-codex.sh). Both variants completed
6/6 calls with 100% schema validity, source-quote validity, core-gate validity,
must-preserve recall and tool isolation, with zero must-not-add violations.
Low beat medium on normalized speech-act exactness (66.7% vs 50%), median
latency (7.947 s vs 9.170 s), and total output tokens (1,472 vs 1,682).
Medium had the tighter maximum latency in this small sample (11.506 s vs
12.135 s). That bounded evidence keeps `low` as the default. `--smoke` replays the same
fixed six fixtures to reproduce these numbers; to judge your own workload, add
representative fixtures to [`harness/fixtures.json`](harness/fixtures.json) and
run `./harness/run-codex.sh` without `--smoke` before changing anything. Two
legacy disposition expectations score as misses for both variants because they
expect a rewrite where the current closed-warrant contract deliberately passes
an already self-contained prompt through unchanged.

The non-model adapter suite lives at
[`harness/codex-gate-tests.sh`](harness/codex-gate-tests.sh): 81 deterministic
checks cover toggles, recursion, sanitization, provenance, JSON framing, strict
event isolation, transcript filtering, retention, context budgets, dependency
failure, audit durability and packaging without making an API call.

#### The fresh Sol guide

The Codex bundle contains two deliberately separate skills:

- [`$cyberprompt:cyberprompt`](plugins/cyberprompt/skills/cyberprompt/) manages install,
  trust, toggles, status, config, logs, XP, bypasses and troubleshooting.
- [`$cyberprompt:gpt-5-6-sol`](plugins/cyberprompt/skills/gpt-5-6-sol/) writes, reviews,
  migrates and deploys prompts for Sol. Every invocation refreshes its working
  context from current official OpenAI documentation, the installed CLI,
  standards, release notes, maintainers' reference implementations and original
  research. It supplies an explicit as-of date covering evidence through
  July 31, 2026 or later, plus a concrete invocation or deployment example. If
  retrieval is unavailable, it labels the bundled snapshot as an offline
  fallback.

Fresh browsing updates the skill's **working context**, not the model's training
data. It is also not placed inside the automatic forge: that nested call is
intentionally tool-less and uses a compact, release-tested instruction contract.
Invoke `$cyberprompt:gpt-5-6-sol` when you want current research or a prompt authored for
Sol; leave the per-submit forge deterministic and contained.

#### Update or uninstall Codex

Update:

```bash
codex plugin marketplace upgrade cyberprompt
codex plugin remove cyberprompt@cyberprompt
codex plugin add cyberprompt@cyberprompt
```

Uninstall (the second command is optional if you want to keep the marketplace):

```bash
codex plugin remove cyberprompt@cyberprompt
codex plugin marketplace remove cyberprompt
```

Start a new session after reinstalling and re-trust the hook if its command
definition changed. Uninstalling deliberately leaves
`${CODEX_HOME:-$HOME/.codex}/cyberprompt` in place so your config and audit log
survive; delete that narrow state directory manually only if you want them gone.

One current host caveat: Codex may render hook-supplied developer context in the
transcript. That visible block is host UI, not a second optimizer pass. The hook
can add advisory context but cannot replace or retract the original user
message, so `skipit` remains visible too.

Current platform references: [Codex hooks](https://learn.chatgpt.com/docs/hooks),
[plugin packaging](https://developers.openai.com/plugins/build/plugins),
[building skills](https://learn.chatgpt.com/docs/build-skills), and
[GPT-5.6 prompt guidance](https://developers.openai.com/api/docs/guides/prompt-guidance-gpt-5p6.md).

<a id="claude-code"></a>

### Claude Code

Requirements: an authenticated Claude Code installation. The
[claude-5 prompting skill](skills/claude-5/) the forge wields is **bundled**:
plugin installs read it straight from the plugin — nothing to provide, nothing
to seed — and the manual installer copies it to
`~/.claude/skills/claude-5`. Rather run your own prompting guide? Point
`CLAUDE5_SKILL=` at a directory with the same shape: `SKILL.md` at the root,
`references/shared.md`, and per-model files named `references/<model>.md`
(e.g. `fable-5.md`).

#### Plugin (recommended)

```
/plugin marketplace add Fredasterehub/cyberprompt
/plugin install cyberprompt@cyberprompt
```

Then jack in: `mkdir -p ~/.claude/cyberprompt && touch ~/.claude/cyberprompt/enabled`
— or just tell Claude *"cyberprompt on"*. The plugin registers the hook and both
skills automatically; updates ride the marketplace. Restart Claude Code once
after installing (hooks load at session start) — toggling the sentinel never
needs one.

#### Manual (no plugin)

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

#### Claude config (`~/.claude/cyberprompt/config`)

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
on a three-variant evaluation matrix ([`harness/`](harness/) — 30 fixtures
covering self-repair, background-context, AZERTY-repair, and invented-caution
behavior, of which 2 are prompt-injection scenarios). Latest full sweep
2026-07-29 on the then-28-fixture set: 84 calls, 5 of them failing outright
(4 sonnet-5 low, 1 sonnet-5 medium). On the calls that
returned, all three variants preserved 100% of must-preserve constraints and
neither injection fixture landed. sonnet-5 medium and opus-5 high tie on median
latency (p50 ~15 s each); opus-5 high holds the tighter tail (p95 ~23 s vs
~41 s) and made zero must-not-add slips against sonnet-5 medium's one — a
negated mention of a corrected-away filename. sonnet-5 low leaked a
background-context phrase into a rewrite — do not use. sonnet-5 medium stays
the default on price, not on winning. Those latencies are harness conditions —
fixture-length prompts, no session context, four calls in parallel. Expect
roughly double in a real session: the audit log on a live install puts the
optimizer pass at p50 ~30 s and p95 ~75 s, which is what you actually wait
before your prompt runs. Disposition and speech-act accuracy are deliberately not
part of this verdict: every variant scores below a trivial always-rewrite
baseline, which is a fixture-labeling problem the suite still owes a
recalibration. A separate offline suite
([`harness/gate-tests.sh`](harness/gate-tests.sh) — 74 checks, zero API calls)
drives the production hook end-to-end with a stub model, covering every gate,
strip, and fail-open path on every change.

## ▸ The gates

The optimizer must answer in schema-validated JSON — and then survive mechanical
review before a single word reaches your session:

```
schema valid? ─▸ warrant named? ─▸ source_quotes valid? ─▸ within ceiling? ─▸ tokens retained? ─▸ advisory fits?
     │               │                  │                     │                   │                  │
     ▼ fail          ▼ fail             ▼ fail                ▼ fail              ▼ fail             ▼ fail
                          ORIGINAL PASSES THROUGH UNCHANGED (logged, flagged)
```

The ceiling scales with your original — 2×length + 1500 characters, capped at
9000 — and the forge is told the budget up front: it tightens to fit or passes
through, instead of meeting the ICE by surprise.

The advisory-fit gate is a ladder rather than a cliff: an advisory that would
exceed CYBERPROMPT's 9700-byte application budget is re-rendered without the
execution brief, with a note saying so on both sides of the glass; only if the
constraints alone still overflow does it fail open. Host ceilings differ: Claude
Code applies a fixed 10,000-unit platform cap, while on Codex this bundle
declares a 5000-token `additionalContextLimit` in `hooks.json` — deliberately
above the host's 2500-token default, because a 9700-byte advisory can exceed
2500 tokens and would otherwise be silently spilled to a file. The byte gate
always decides first, so the raised allowance admits nothing the ladder didn't
already approve. Every log line records `advisory_chars`.

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
only artifacts or whitespace remain, the optimizer is skipped. The host still
receives the operator's original prompt unchanged in every case.

Everything is auditable: `~/.claude/cyberprompt/log.jsonl` on Claude Code or
`${CODEX_HOME:-$HOME/.codex}/cyberprompt/log.jsonl` on Codex records every
original/optimized pair with its disposition, the warrant the rewrite claimed,
the speech acts and source-quoted requirements it extracted, its assumptions,
duration, advisory size, and any gate verdict. Mode `0600`, `flock`-guarded,
your prompts stay yours — and the two hosts never share state.

## ▸ What's skipped automatically

Slash commands, `!` shell and `#` memory shortcuts, sub-agent prompts,
machine-generated turns (task notifications, teammate messages — learned the
hard way when the daemon optimized a background notification into a quest and
the model went on the quest), prompts under `MIN_CHARS`, and its own recursion.

And anything you tell it to skip: `skipit` at the start or end of a prompt
bypasses the optimizer for that one prompt — no call, no wait, one line of
confirmation, next prompt back to normal. Dictation-friendly: the two-word
`skip it` works too, at the start of the prompt only (a trailing "…, skip it"
is ordinary English and would misfire). The marker stays in the prompt the
model sees; `UserPromptSubmit` cannot edit your text, and cyberprompt never
will.

## ▸ Killing a rewrite in flight

**ESC does not retract an advisory that already shipped.** Once the hook
injects, the transcript is append-only — there is no amend path, and
everything after that point descends from the injected node. ESC stops
*generation*; it does not un-inject.

On Claude Code, rewind the conversation:

1. `ESC` — stop the model.
2. `ESC` `ESC` on an empty composer — open the rewind menu.
3. **Restore conversation** to the turn before your prompt.
4. Resend with `skipit`.

On Codex, stop generation, start or fork a clean conversation before the bad
turn, and resend with `skipit`. A later correction cannot erase developer
context already recorded in the existing transcript.

Toggling the plugin off works too, but it is a bigger hammer than the
situation needs, and the sentinel stays off until you remember it.

Two honest footnotes. The visible terminal block shows `optimized_prompt` alone, while
the model additionally receives the explicit task, every constraint with its
verbatim source quote, and the non-binding inferences — if the grey text
looks thin, the advisory usually is not; check `log.jsonl`. And the restraint
gate reduces *damage*, not waiting: a `pass_through` verdict still costs the
full optimizer call. `skipit` is the lever that costs nothing.

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
