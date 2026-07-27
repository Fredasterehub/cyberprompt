# Prompting Claude Fable 5 (and Mythos 5)

Distilled from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5 (captured 2026-07-26). Snippets in ```text blocks are official, copy-paste-ready prompt language — use them verbatim or lightly adapted.

## Profile

Built for problems previously too complex, long-running, or ambiguous: end-to-end work that takes a person hours to weeks. Strongest at long-horizon autonomy, first-shot correctness on well-specified complex problems, dense-image vision, bug-finding recall, navigating ambiguity, and dispatching/sustaining parallel subagents. Test it on your hardest unsolved problems — simple workloads undersell it. Fable 5 and Mythos 5 share the same underlying model; the same guidance applies to both.

Hard constraints:
- Not for offensive cybersecurity or biology/life-sciences work — safety classifiers return `stop_reason: "refusal"`, and benign adjacent work can also trip them. Configure fallback to Claude Opus 4.8 for declined requests.
- Adaptive thinking only, always on; thinking output is summarized-only; no extended thinking budgets.
- Turns run long by default: minutes per request at higher effort, hours for autonomous runs. Adjust client timeouts and check on runs asynchronously rather than blocking.

## Effort

`high` is the default and right for most tasks; `xhigh` for the most capability-sensitive workloads; `medium`/`low` for routine work — lower-effort Fable 5 still often exceeds `xhigh` on prior models. Reduce effort if tasks complete but take too long. At `high`/`xhigh`, set a large `max_tokens`: it is a hard cap on thinking plus response combined.

## Patterns

### Prevent overplanning on ambiguous tasks

```text
When you have enough information to act, act. Do not re-derive facts already established in the conversation, re-litigate a decision the user has already made, or narrate options you will not pursue in user-facing messages. If you are weighing a choice, give a recommendation, not an exhaustive survey. This does not apply to thinking blocks.
```

### Prevent unrequested tidying/refactoring at higher effort

```text
Don't add features, refactor, or introduce abstractions beyond what the task requires. A bug fix doesn't need surrounding cleanup and a one-shot operation usually doesn't need a helper. Don't design for hypothetical future requirements: do the simplest thing that works well. Avoid premature abstraction and half-finished implementations. Don't add error handling, fallbacks, or validation for scenarios that cannot happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs). Don't use feature flags or backwards-compatibility shims when you can just change the code.
```

### Brevity — one short instruction beats enumerating behaviors

Instruction-following is strong enough that brief steering replaces lists of named behaviors:

```text
Lead with the outcome. Your first sentence after finishing should answer "what happened" or "what did you find": the thing the user would ask for if they said "just give me the TLDR." Supporting detail and reasoning come after. Being readable and being concise are different things, and readability matters more.

The way to keep output short is to be selective about what you include (drop details that don't change what the reader would do next), not to compress the writing into fragments, abbreviations, arrow chains like A → B → fails, or jargon.
```

### Checkpoint behavior — when to stop and ask

```text
Pause for the user only when the work genuinely requires them: a destructive or irreversible action, a real scope change, or input that only they can provide. If you hit one of these, ask and end the turn, rather than ending on a promise.
```

### Ground progress claims on long runs

Nearly eliminated fabricated status reports in Anthropic's testing — include it in any long-run prompt:

```text
Before reporting progress, audit each claim against a tool result from this session. Only report work you can point to evidence for; if something is not yet verified, say so explicitly. Report outcomes faithfully: if tests fail, say so with the output; if a step was skipped, say that; when something is done and verified, state it plainly without hedging.
```

### State the boundaries — prevent unrequested actions

```text
When the user is describing a problem, asking a question, or thinking out loud rather than requesting a change, the deliverable is your assessment. Report your findings and stop. Don't apply a fix until they ask for one. Before running a command that changes system state (restarts, deletes, config edits), check that the evidence actually supports that specific action. A signal that pattern-matches to a known failure may have a different cause.
```

### Parallel subagents

Fable 5 dispatches subagents readily and manages long-lived ones dependably. Prefer asynchronous orchestrator↔subagent communication over blocking; long-lived subagents that keep context across subtasks save time and cost via cache reads.

```text
Delegate independent subtasks to subagents and keep working while they run. Intervene if a subagent goes off track or is missing relevant context.
```

### Memory system

Performs particularly well when it can record and reference lessons across runs. A Markdown file is enough:

```text
Store one lesson per file with a one-line summary at the top. Record corrections and confirmed approaches alike, including why they mattered. Don't save what the repo or chat history already records; update an existing note rather than creating a duplicate; delete notes that turn out to be wrong.
```

Bootstrap from history: "Reflect on the previous sessions we've had together. Use subagents to identify core themes and lessons, and store them in [X]. Make sure you know to reference [X] for future use."

### Autonomous pipelines — prevent rare early stopping

Deep into long sessions, Fable 5 can occasionally end a turn on a statement of intent without the tool call, or ask permission it doesn't need. For unattended pipelines add:

```text
You are operating autonomously. The user is not watching in real time and cannot answer questions mid-task, so asking "Want me to…?" or "Shall I…?" will block the work. For reversible actions that follow from the original request, proceed without asking. Offering follow-ups after the task is done is fine; asking permission after already discussing with the user before doing the work is not. Before ending your turn, check your last paragraph. If it is a plan, an analysis, a question, a list of next steps, or a promise about work you have not done ("I'll…", "let me know when…"), do that work now with tool calls. End your turn only when the task is complete or you are blocked on input only the user can provide.
```

### Context-budget reassurance

Avoid showing the model remaining-token countdowns; if the harness must, add:

```text
You have ample context remaining. Do not stop, summarize, or suggest a new session on account of context limits. Continue the work.
```

### Give the reason, not only the request

```text
I'm working on [the larger task] for [who it's for]. They need [what the output enables]. With that in mind: [request].
```

### Readability addendum for long agentic sessions

```text
Terse shorthand is fine between tool calls (that's you thinking out loud, and brevity there is good). Your final summary is different: it's for a reader who didn't see any of that.

If you've been working for a while without the user watching (overnight, across many tool calls, since they last spoke), your final message is their first look at any of it. Write it as a re-grounding, not a continuation of your working thread: the outcome first, then the one or two things you need from them, each explained as if new. The vocabulary you built up while working is yours, not theirs; leave it behind unless you re-introduce it.

When you write the summary at the end, drop the working shorthand. Write complete sentences. Spell out terms. Don't use arrow chains, hyphen-stacked compounds, or labels you made up earlier. When you mention files, commits, flags, or other identifiers, give each one its own plain-language clause. Open with the outcome: one sentence on what happened or what you found. Then the supporting detail. If you have to choose between short and clear, choose clear.
```

### Send-to-user tool for long async agents

For agents whose UX needs verbatim mid-task delivery (deliverables, precise numbers, direct answers), define a `send_to_user` tool whose input is rendered directly to the user. Tool inputs are never summarized. The tool alone is not enough — pair it with elicitation language:

```text
Between tool calls, when you have content the user must read verbatim (a partial deliverable, a direct answer to their question), call the send_to_user tool with that content. Use send_to_user only for user-facing content, not for narration or reasoning.
```

## Scaffolding changes when adopting Fable 5

- Start at the top of your difficulty range; have it scope, ask clarifying questions, execute.
- Make self-verification explicit in long-run prompts; separate fresh-context verifier subagents outperform self-critique: "Establish a method for checking your own work at an interval of [X] as you build. Run this every [X interval], verifying your work with subagents against the specification."
- Refactor old prompts and skills: instructions written for prior models are often too prescriptive and degrade output. Remove them if default behavior is better.
- Never instruct it to echo, transcribe, or explain its internal reasoning in the response — this triggers the `reasoning_extraction` refusal category and elevates fallbacks. Read structured thinking blocks instead; surface progress with a send-to-user tool.
