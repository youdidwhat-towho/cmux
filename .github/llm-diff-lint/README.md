# LLM Diff Lint

This lint runs one DeepSeek request per rule. Each request receives the complete PR diff plus one focused rule and returns JSON with `violated`, `severity`, `summary`, and findings.

The workflow uses `pull_request_target` and fetches the patch with `gh pr diff`. It does not check out or execute PR code, which keeps repository secrets out of untrusted PR scripts.

## Secrets And Variables

Required secret:

- `DEEPSEEK_API_KEY`

Optional repository variables:

- `DEEPSEEK_MODEL`, defaults to `deepseek-v4-pro`
- `DEEPSEEK_BASE_URL`, defaults to `https://api.deepseek.com`
- `DEEPSEEK_MAX_TOKENS`, defaults to `4096`
- `DEEPSEEK_THINKING`, defaults to `disabled`
- `LLM_DIFF_LINT_MAX_DIFF_BYTES`, defaults to `5000000`

If `DEEPSEEK_API_KEY` is missing, the workflow emits a notice and skips. This lets the workflow merge before the secret is configured.

## Rule Size

Keep each rule around 150 to 300 words. That is large enough to define failure cases and allowed cases, while small enough that the model focuses on one decision.

Avoid broad style guides. A good rule has:

- a narrow behavior class
- concrete failure cases
- concrete allowed cases
- one preferred fix direction

Do not include large code examples unless the syntax is ambiguous. Every extra rule token is paid once per PR per rule because each rule reads the full diff.

## Agent Split

The current split is 6 rules, 6 matrix jobs, with `max-parallel: 3`.

This keeps each LLM call independent and gives complete per-rule status in GitHub checks. `fail-fast: false` lets all rules finish even when one fails.

Use this default for normal PR linting:

- 4 to 8 rules total
- 1 rule per LLM call
- 2 to 4 concurrent jobs

Add another rule only when it catches a distinct class of bug. If a rule starts mixing unrelated topics, split it. If two rules routinely flag the same lines, merge them.
