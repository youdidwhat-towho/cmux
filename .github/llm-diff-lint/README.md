# LLM Diff Lint

This lint runs one AI SDK request per provider per rule. Each request receives the complete PR diff plus one focused rule and returns JSON with `violated`, `severity`, `summary`, and findings.

The workflow uses `pull_request_target` and fetches the net PR diff with `gh pr diff`. It does not check out or execute PR code, which keeps repository secrets out of untrusted PR scripts.

Security boundaries:

- no `pull_request` trigger, so fork or branch PR code never runs with repository secrets
- no `workflow_dispatch`, so branch-modified workflow code cannot be manually run with repository secrets
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
- `LLM_DIFF_LINT_MAX_TOKENS`, defaults to `4096`
- `LLM_DIFF_LINT_THINKING`, defaults to `disabled` for DeepSeek
- `LLM_DIFF_LINT_MAX_DIFF_BYTES`, defaults to `5000000`
- `DEEPSEEK_BASE_URL`, optional DeepSeek override

The default provider matrix compares `deepseek-v4-pro` with `gemini-3-flash-preview` through Vertex AI. GitHub Actions authenticates to Vertex with OIDC workload identity and the `cmux-vertex-ai` service account. This avoids storing a long-lived GCP service account key.

Use `LLM diff lint status` as the required branch-protection check.

For local Gemini runs, authenticate Application Default Credentials first:

```bash
gcloud auth application-default login
```

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
