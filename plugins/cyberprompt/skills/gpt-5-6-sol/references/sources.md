# Freshness and source routing

Use this reference to refresh working context; do not describe retrieval as changing model training.

## Canonical OpenAI sources

- GPT-5.6 model guide: `https://developers.openai.com/api/docs/guides/latest-model`
- GPT-5.6 Sol prompting guide: `https://developers.openai.com/api/docs/guides/prompt-guidance-gpt-5p6.md`
- Codex manual: `https://developers.openai.com/codex/codex-manual.md`
- Codex hooks: `https://learn.chatgpt.com/docs/hooks`
- Codex skills: `https://learn.chatgpt.com/docs/build-skills`
- Plugin packaging: `https://developers.openai.com/plugins/build/plugins`
- Open-source Codex runtime and generated hook schemas: `https://github.com/openai/codex`
- OpenAI evaluation best practices: `https://developers.openai.com/api/docs/guides/evaluation-best-practices`
- OpenAI prompt optimizer status: `https://developers.openai.com/api/docs/guides/prompt-optimizer`
- OpenAI self-evolving-agent implementation: `https://developers.openai.com/cookbook/examples/partners/self_evolving_agents/autonomous_agent_retraining`

Fetch the exact page before relying on it. Use the installed CLI's help and feature list as current-session evidence when public docs and local behavior differ.

## Domain evidence

For the prompt's subject, prefer sources in this order:

1. current official specifications and vendor documentation;
2. current release notes and maintained source repositories;
3. original papers, benchmarks, and reproducible artifacts;
4. deployed reference implementations with concrete configuration;
5. secondary synthesis only to find primary sources, never as sole support for a material technical claim.

Search narrowly. Record publication or release dates and distinguish directly supported facts from inference. “State of the art” requires a named task, metric, evaluation setting, and date; otherwise say “current strong practice.”

## Prompt-optimization research anchors

These are starting points, not universal winners. Re-check the maintained implementation, paper status, task, metric, evaluation budget, and held-out results before recommending one:

- GEPA paper and maintained implementation: `https://arxiv.org/abs/2507.19457` and `https://github.com/gepa-ai/gepa`
- DSPy optimizer documentation, including GEPA and MIPROv2: `https://dspy.ai/learn/optimization/optimizers/`
- AGOPS task-specific guideline optimization: `https://arxiv.org/abs/2607.14105`

Current strong implementations optimize against an explicit evaluator and examples, retain a baseline, and validate candidates on held-out cases. That is a different product shape from an inference-time, single-prompt normalizer such as CYBERPROMPT. Do not transfer benchmark claims between those settings.

The legacy OpenAI dashboard prompt optimizer is scheduled for deprecation with the Evals platform in late 2026. Verify its current status before mentioning it and do not choose it as a new deployment default solely because the documentation page still exists.

## Offline fallback

The bundled references are a snapshot distilled on 2026-07-31. If fresh retrieval fails, use them only as bounded fallback. State that current availability, parameters, flags, and best practice could not be reverified.
