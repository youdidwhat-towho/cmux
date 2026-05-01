#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RULE="$TMP_DIR/rule.md"
DIFF="$TMP_DIR/pr.diff"

cat > "$RULE" <<'EOF'
# Fixture Rule

Flag changed lines containing fixture violations.
EOF

cat > "$DIFF" <<'EOF'
diff --git a/Sources/Foo.swift b/Sources/Foo.swift
index 1111111..2222222 100644
--- a/Sources/Foo.swift
+++ b/Sources/Foo.swift
@@ -1,3 +1,4 @@
 struct Foo {
+    func bad() { print("bad") }
 }
EOF

CLEAN='{"rule_id":"rule","violated":false,"severity":"none","summary":"clean","findings":[]}'
python3 scripts/llm_diff_lint.py \
  --rule "$RULE" \
  --diff-file "$DIFF" \
  --output "$TMP_DIR/clean.json" \
  --mock-response "$CLEAN" > "$TMP_DIR/clean.out"

if ! grep -Fq '"violated": false' "$TMP_DIR/clean.out"; then
  echo "expected clean mock response to pass" >&2
  cat "$TMP_DIR/clean.out" >&2
  exit 1
fi

if ! grep -Fq '"summary": "clean"' "$TMP_DIR/clean.json"; then
  echo "expected clean JSON output file" >&2
  cat "$TMP_DIR/clean.json" >&2
  exit 1
fi

WARNING='{"rule_id":"rule","violated":true,"severity":"warning","summary":"needs review","findings":[{"file":"Sources/Foo.swift","line":2,"excerpt":"print(\"bad\")","why":"suspicious","confidence":"medium"}]}'
python3 scripts/llm_diff_lint.py \
  --rule "$RULE" \
  --diff-file "$DIFF" \
  --mock-response "$WARNING" > "$TMP_DIR/warning.out"

if ! grep -Fq '"severity": "warning"' "$TMP_DIR/warning.out"; then
  echo "expected warning mock response to pass without failing" >&2
  cat "$TMP_DIR/warning.out" >&2
  exit 1
fi

FAILURE='{"rule_id":"rule","violated":true,"severity":"failure","summary":"bad","findings":[{"file":"Sources/Foo.swift","line":2,"excerpt":"print(\"bad\")","why":"print in runtime code","confidence":"high"}]}'
if python3 scripts/llm_diff_lint.py \
  --rule "$RULE" \
  --diff-file "$DIFF" \
  --mock-response "$FAILURE" > "$TMP_DIR/failure.out" 2>&1; then
  echo "expected failure mock response to fail" >&2
  exit 1
fi

if ! grep -Fq '"severity": "failure"' "$TMP_DIR/failure.out"; then
  echo "expected failure output" >&2
  cat "$TMP_DIR/failure.out" >&2
  exit 1
fi

env -u DEEPSEEK_API_KEY python3 scripts/llm_diff_lint.py \
  --rule "$RULE" \
  --diff-file "$DIFF" \
  --skip-if-missing-key > "$TMP_DIR/missing-key.out"

if ! grep -Fq 'DEEPSEEK_API_KEY is not set' "$TMP_DIR/missing-key.out"; then
  echo "expected missing key skip notice" >&2
  cat "$TMP_DIR/missing-key.out" >&2
  exit 1
fi

if python3 scripts/llm_diff_lint.py \
  --rule "$RULE" \
  --diff-file "$DIFF" \
  --max-diff-bytes 1 \
  --mock-response "$CLEAN" > "$TMP_DIR/too-large.out" 2>&1; then
  echo "expected oversized diff to fail before mock response" >&2
  exit 1
fi

if ! grep -Fq 'The diff was not truncated' "$TMP_DIR/too-large.out"; then
  echo "expected oversized diff output" >&2
  cat "$TMP_DIR/too-large.out" >&2
  exit 1
fi

RESULTS_DIR="$TMP_DIR/results/llm-diff-lint-rule"
mkdir -p "$RESULTS_DIR"
cp "$TMP_DIR/clean.json" "$RESULTS_DIR/result.json"

python3 scripts/llm_diff_lint_comment.py \
  --results-dir "$TMP_DIR/results" \
  --pr-number 123 \
  --pr-url https://github.com/manaflow-ai/cmux/pull/123 \
  --diff-url https://github.com/manaflow-ai/cmux/pull/123.diff \
  --run-url https://github.com/manaflow-ai/cmux/actions/runs/456 \
  --dry-run > "$TMP_DIR/comment.md"

if ! grep -Fq '<!-- cmux-llm-diff-lint -->' "$TMP_DIR/comment.md"; then
  echo "expected stable comment marker" >&2
  cat "$TMP_DIR/comment.md" >&2
  exit 1
fi

if ! grep -Fq '| `rule` | passed | clean |' "$TMP_DIR/comment.md"; then
  echo "expected rule status table" >&2
  cat "$TMP_DIR/comment.md" >&2
  exit 1
fi
