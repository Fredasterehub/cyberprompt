# GPT-5.6 Sol smoke evaluation

As of 2026-07-31, CYBERPROMPT's Codex forge was evaluated on `codex-cli 0.146.0` with `gpt-5.6-sol` at `low` and `medium` effort.

```bash
./harness/run-codex.sh --smoke --jobs 2
```

The fixed smoke set contains six fixtures and produces twelve real model calls. The evaluated instruction SHA-256 was `aaecdec35f32e48d3eba394ec59f90c019e6b92ff2ba93ff27adfdb4eb7e72a7`; the schema SHA-256 was `a6aafdfdccae2f78b94ef91b3990eed9b98b1e817bfdfa90c81b0546ad726a60`.

| Metric | Sol low | Sol medium |
|---|---:|---:|
| Successful calls | 6/6 | 6/6 |
| Schema valid | 6/6 | 6/6 |
| Source quotes valid | 6/6 | 6/6 |
| Core hook gate valid | 6/6 | 6/6 |
| Must-preserve recall | 18/18 | 18/18 |
| Must-not-add violations | 0/10 | 0/10 |
| Calls without runtime tools | 6/6 | 6/6 |
| Normalized speech-act exact match | 4/6 | 3/6 |
| Minimum latency | 5.414 s | 5.760 s |
| Median latency | 7.947 s | 9.170 s |
| Maximum latency | 12.135 s | 11.506 s |
| Total output tokens | 1,472 | 1,682 |

Both efforts scored 4/6 against the shared legacy disposition labels. The two misses expect a rewrite for already self-contained prompts; the current closed-warrant contract deliberately returns exact pass-through. The source-quoted operative wording remains mechanically preserved even when a normalized speech-act label misses the fixture's canonical vocabulary.

This is a release smoke, not a universal quality or state-of-the-art claim. Keep `low` as the latency-sensitive default on this evidence, then replay representative project cases before changing effort, model, schema, or instruction text.
