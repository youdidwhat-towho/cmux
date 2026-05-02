# LLM Diff Lint

This lint runs one AI SDK request per provider per rule. Each request receives the complete PR diff plus one focused rule and returns JSON with `violated`, `severity`, `summary`, and findings.

The workflow uses `pull_request_target` and fetches the net PR diff with `gh pr diff`. It does not check out or execute PR code, which keeps repository secrets out of untrusted PR scripts.

Security boundaries:

- no `pull_request` trigger, so fork or branch PR code never runs with repository secrets
- manual `workflow_dispatch` accepts only a numeric PR number and still checks out the repository default branch
- checkout always uses the repository default branch
- `id-token: write` is scoped only to the Google Vertex job
- model input and model output are redacted before artifacts, annotations, and PR comments
- the GCP Workload Identity provider is restricted to `.github/workflows/llm-diff-lint.yml` on `main`

## Secrets And Variables

Required secret:

- `DEEPSEEK_API_KEY`

Optional repository variables:

- `GCP_WORKLOAD_IDENTITY_PROVIDER`, defaults to the cmux GitHub Actions workload identity provider
- `GCP_SERVICE_ACCOUNT`, defaults to `cmux-vertex-ai@manaflow-437420.iam.gserviceaccount.com`
- `GOOGLE_VERTEX_PROJECT`, required for Gemini unless `GOOGLE_CLOUD_PROJECT` is set in the environment
- `GOOGLE_VERTEX_LOCATION`, defaults to `global`
- `LLM_DIFF_LINT_MAX_TOKENS`, defaults to `8192`
- `LLM_DIFF_LINT_RETRIES`, defaults to `0`
- `LLM_DIFF_LINT_THINKING`, defaults to `disabled` for DeepSeek
- `LLM_DIFF_LINT_MAX_DIFF_BYTES`, defaults to `5000000`
- `DEEPSEEK_BASE_URL`, optional DeepSeek override

The default provider matrix compares `deepseek-v4-pro` with `gemini-3-flash-preview` through Vertex AI. GitHub Actions authenticates to Vertex with OIDC workload identity and the `cmux-vertex-ai` service account. This avoids storing a long-lived GCP service account key.

Use `LLM diff lint status` as the required branch-protection check.

For local Gemini runs, authenticate Application Default Credentials first:

```bash
gcloud auth application-default login
```

## Cost Model

Every provider/rule job sends the full diff plus one rule. Estimated input tokens are roughly:

```text
(diff bytes / 4 + rule tokens + prompt overhead) * provider count * rule count
```

Current published prices as of 2026-05-02:

| Model | Input, cache miss | Input, cache hit | Output | Notes |
| --- | ---: | ---: | ---: | --- |
| `deepseek-v4-pro` | $1.74 / 1M | $0.0145 / 1M | $3.48 / 1M | DeepSeek official list price |
| `deepseek-v4-pro` | $0.435 / 1M | $0.003625 / 1M | $0.87 / 1M | DeepSeek promotional price through 2026-05-31 |
| `deepseek-v4-flash` | $0.14 / 1M | $0.0028 / 1M | $0.28 / 1M | Cheaper DeepSeek option, not current production model |
| `gemini-3-flash-preview` | $0.50 / 1M | provider dependent | $3.00 / 1M | Current latest Gemini Flash model used by this workflow |
| `gemini-2.5-flash-lite` | $0.10 / 1M | $0.01 / 1M | $0.40 / 1M | Cheapest generally available Gemini Flash-Lite model |

Sources: [DeepSeek API pricing](https://api-docs.deepseek.com/quick_start/pricing), [Vertex AI Gemini pricing](https://cloud.google.com/vertex-ai/generative-ai/pricing), and [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing).

With cache misses, `deepseek-v4-pro` is currently cheaper than `gemini-3-flash-preview` during the DeepSeek promotion, but it is not cheaper than `gemini-2.5-flash-lite`. After the promotion, DeepSeek Pro is materially more expensive than both Flash options.

Assume cache miss for planning unless provider billing proves otherwise. PR diffs are usually unique, and this prompt is rule-first, so repeated rule calls should not rely on prefix-cache hits.

Retries repeat the full request and can multiply cost. Keep `LLM_DIFF_LINT_RETRIES=0` for required checks unless provider errors are transient and measured. One retry is reasonable for advisory shadow runs, but it did not fix repeated Gemini structured-output failures in the 2026-05-02 comparison.

## Rule Size

Keep each rule around 150 to 300 words. That is large enough to define failure cases and allowed cases, while small enough that the model focuses on one decision.

Avoid broad style guides. A good rule has:

- a narrow behavior class
- concrete failure cases
- concrete allowed cases
- one preferred fix direction

Do not include large code examples unless the syntax is ambiguous. Every extra rule token is paid once per PR per rule because each rule reads the full diff.

## Provider And Rule Split

The current split is 6 rules across 2 providers, for 12 matrix jobs, with `max-parallel: 4`.

This keeps each LLM call independent and gives complete per-provider, per-rule status in GitHub checks. `fail-fast: false` lets all rules finish even when one fails.

Use this default for normal PR linting:

- 4 to 8 rules total
- 1 provider and 1 rule per LLM call
- 2 to 4 concurrent jobs, adjusted for provider rate limits

Add another rule only when it catches a distinct class of bug. If a rule starts mixing unrelated topics, split it. If two rules routinely flag the same lines, merge them.
