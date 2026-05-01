#!/usr/bin/env python3
"""Run one LLM lint rule against a complete pull request diff."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import textwrap
import urllib.error
import urllib.request
from typing import Any


DEFAULT_BASE_URL = "https://api.deepseek.com"
DEFAULT_MODEL = "deepseek-v4-pro"
DEFAULT_MAX_TOKENS = 4096
DEFAULT_MAX_DIFF_BYTES = 5_000_000
SECRET_PATTERNS = (
    (re.compile(r"sk-[A-Za-z0-9][A-Za-z0-9_-]{16,}"), "sk-REDACTED"),
    (re.compile(r"gh[pousr]_[A-Za-z0-9_]{20,}"), "gh_REDACTED"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AKIA_REDACTED"),
    (re.compile(r"(?i)(api[_-]?key|token|secret|password)(\s*[:=]\s*)([\"']?)[^\"'\s]+"), r"\1\2\3REDACTED"),
    (
        re.compile(
            r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----",
            re.DOTALL,
        ),
        "-----BEGIN PRIVATE KEY-----REDACTED-----END PRIVATE KEY-----",
    ),
)


def github_escape(value: Any, *, property_value: bool = False) -> str:
    text = str(value)
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    if property_value:
        text = text.replace(":", "%3A").replace(",", "%2C")
    return text


def notice(message: str) -> None:
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::notice::{github_escape(message)}")
    else:
        print(message)


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def load_diff(args: argparse.Namespace) -> str:
    if args.diff_file:
        return read_text(args.diff_file)

    command = ["git", "diff", "--no-ext-diff", "--unified=80", f"{args.base}...{args.head}"]
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as exc:
        print(exc.stderr, file=sys.stderr)
        raise SystemExit(exc.returncode) from exc


def redact_secrets(text: str) -> str:
    redacted = text
    for pattern, replacement in SECRET_PATTERNS:
        redacted = pattern.sub(replacement, redacted)
    return redacted


def changed_files(diff: str) -> list[str]:
    files: list[str] = []
    for match in re.finditer(r"^diff --git a/(.*?) b/(.*?)$", diff, flags=re.MULTILINE):
        files.append(match.group(2))
    return sorted(set(files))


def build_prompt(rule_id: str, rule_text: str, diff: str, source_label: str) -> list[dict[str, str]]:
    files = changed_files(diff)
    file_summary = "\n".join(f"- {path}" for path in files[:200]) or "- No changed files found in diff."
    if len(files) > 200:
        file_summary += f"\n- ... {len(files) - 200} more file(s)"

    system = textwrap.dedent(
        """
        You are a strict CI lint reviewer. You receive one lint rule and one complete unified PR diff.
        Decide whether the PR introduces or materially worsens a violation of that single rule.

        Review only the requested rule. Use unchanged context only to understand behavior.
        Ignore pre-existing issues unless an added or modified line makes them worse.
        Prefer no finding over a speculative finding. Report at most 5 findings.
        Return only valid JSON. Do not include markdown or prose outside the JSON object.
        """
    ).strip()

    user = textwrap.dedent(
        f"""
        Rule id: {rule_id}

        Rule:
        {rule_text.strip()}

        Output schema:
        {{
          "rule_id": "{rule_id}",
          "violated": true | false,
          "severity": "none" | "warning" | "failure",
          "summary": "one short sentence",
          "findings": [
            {{
              "file": "repo-relative path",
              "line": 123,
              "excerpt": "short changed-code excerpt",
              "why": "why this violates the rule",
              "confidence": "low" | "medium" | "high"
            }}
          ]
        }}

        Severity policy:
        - Use "failure" only for clear violations that should fail CI.
        - Use "warning" for suspicious cases that need human review but should not fail CI.
        - Use "none" when violated is false.

        Diff source: {source_label}
        Changed files:
        {file_summary}

        Complete unified diff:
        ```diff
        {diff}
        ```
        """
    ).strip()
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def chat_completion(
    *,
    api_key: str,
    base_url: str,
    model: str,
    messages: list[dict[str, str]],
    max_tokens: int,
    timeout: int,
    thinking: str,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "temperature": 0,
        "max_tokens": max_tokens,
        "response_format": {"type": "json_object"},
    }
    if thinking != "omit":
        body["thinking"] = {"type": thinking}

    endpoint = base_url.rstrip("/") + "/chat/completions"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body_text = exc.read().decode("utf-8", errors="replace")
        print(f"DeepSeek API request failed with HTTP {exc.code}: {body_text}", file=sys.stderr)
        raise SystemExit(2) from exc
    except urllib.error.URLError as exc:
        print(f"DeepSeek API request failed: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc


def parse_json_object(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = re.sub(r"^```(?:json)?\s*", "", stripped)
        stripped = re.sub(r"\s*```$", "", stripped)
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        start = stripped.find("{")
        end = stripped.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise
        parsed = json.loads(stripped[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError("model response was not a JSON object")
    return parsed


def normalize_result(rule_id: str, parsed: dict[str, Any]) -> dict[str, Any]:
    violated = bool(parsed.get("violated", False))
    severity = str(parsed.get("severity") or ("failure" if violated else "none")).lower()
    if severity not in {"none", "warning", "failure"}:
        severity = "failure" if violated else "none"
    if not violated:
        severity = "none"

    findings = parsed.get("findings", [])
    if not isinstance(findings, list):
        findings = []
    normalized_findings: list[dict[str, Any]] = []
    for finding in findings[:5]:
        if not isinstance(finding, dict):
            continue
        normalized_findings.append(
            {
                "file": str(finding.get("file") or ""),
                "line": finding.get("line") if isinstance(finding.get("line"), int) else None,
                "excerpt": str(finding.get("excerpt") or ""),
                "why": str(finding.get("why") or ""),
                "confidence": str(finding.get("confidence") or "medium").lower(),
            }
        )

    return {
        "rule_id": str(parsed.get("rule_id") or rule_id),
        "violated": violated,
        "severity": severity,
        "summary": str(parsed.get("summary") or ("Rule violated." if violated else "No violation found.")),
        "findings": normalized_findings,
    }


def print_annotations(result: dict[str, Any]) -> None:
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return

    command = "warning" if result["severity"] == "warning" else "error"
    for finding in result["findings"]:
        props = [f"title={github_escape(result['rule_id'], property_value=True)}"]
        if finding["file"]:
            props.append(f"file={github_escape(finding['file'], property_value=True)}")
        if finding["line"] is not None:
            props.append(f"line={finding['line']}")
        message = finding["why"] or result["summary"]
        if finding["excerpt"]:
            message = f"{message}\n\n{finding['excerpt']}"
        print(f"::{command} {','.join(props)}::{github_escape(message)}")


def summary_markdown(result: dict[str, Any], rule_path: pathlib.Path, diff_bytes: int, model: str) -> str:
    status = "failed" if result["severity"] == "failure" else "warning" if result["severity"] == "warning" else "passed"
    lines = [
        f"### LLM diff lint: `{result['rule_id']}`",
        "",
        f"- Status: {status}",
        f"- Model: `{model}`",
        f"- Rule file: `{rule_path.as_posix()}`",
        f"- Diff bytes reviewed: {diff_bytes}",
        f"- Summary: {result['summary']}",
    ]
    if result["findings"]:
        lines.extend(["", "Findings:"])
        for finding in result["findings"]:
            location = finding["file"]
            if finding["line"] is not None:
                location += f":{finding['line']}"
            lines.append(f"- `{location}` ({finding['confidence']}): {finding['why']}")
    return "\n".join(lines) + "\n"


def write_step_summary(markdown: str) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(markdown)
            handle.write("\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rule", required=True, type=pathlib.Path, help="Markdown rule file")
    parser.add_argument("--diff-file", type=pathlib.Path, help="Unified diff file")
    parser.add_argument("--base", default="origin/main", help="Git diff base when --diff-file is not used")
    parser.add_argument("--head", default="HEAD", help="Git diff head when --diff-file is not used")
    parser.add_argument("--source-label", default="pull request", help="Human-readable diff source label")
    parser.add_argument("--base-url", default=os.environ.get("DEEPSEEK_BASE_URL", DEFAULT_BASE_URL))
    parser.add_argument("--model", default=os.environ.get("DEEPSEEK_MODEL", DEFAULT_MODEL))
    parser.add_argument("--max-tokens", default=int(os.environ.get("DEEPSEEK_MAX_TOKENS", DEFAULT_MAX_TOKENS)), type=int)
    parser.add_argument("--timeout", default=int(os.environ.get("DEEPSEEK_TIMEOUT", "240")), type=int)
    parser.add_argument(
        "--thinking",
        default=os.environ.get("DEEPSEEK_THINKING", "disabled"),
        choices=("enabled", "disabled", "omit"),
        help="DeepSeek thinking mode. Use omit for compatibility with older aliases.",
    )
    parser.add_argument(
        "--max-diff-bytes",
        default=int(os.environ.get("LLM_DIFF_LINT_MAX_DIFF_BYTES", DEFAULT_MAX_DIFF_BYTES)),
        type=int,
        help="Fail instead of truncating when the diff is larger than this. Use 0 for no limit.",
    )
    parser.add_argument("--skip-if-missing-key", action="store_true")
    parser.add_argument("--mock-response", help="JSON response for tests and dry runs")
    args = parser.parse_args(argv)

    rule_path = args.rule.resolve(strict=False)
    if not rule_path.exists():
        print(f"Missing rule file: {rule_path}", file=sys.stderr)
        return 2

    rule_id = rule_path.stem
    rule_text = read_text(rule_path)
    diff = load_diff(args)
    if not diff.strip():
        notice(f"{rule_id}: empty diff, skipping")
        return 0

    diff = redact_secrets(diff)
    diff_bytes = len(diff.encode("utf-8"))
    if args.max_diff_bytes and diff_bytes > args.max_diff_bytes:
        print(
            f"{rule_id}: diff is {diff_bytes} bytes, above limit {args.max_diff_bytes}. "
            "Increase LLM_DIFF_LINT_MAX_DIFF_BYTES or split the PR. The diff was not truncated.",
            file=sys.stderr,
        )
        return 2

    if args.mock_response:
        parsed = parse_json_object(args.mock_response)
    else:
        api_key = os.environ.get("DEEPSEEK_API_KEY")
        if not api_key:
            if args.skip_if_missing_key:
                notice(f"{rule_id}: DEEPSEEK_API_KEY is not set, skipping LLM diff lint")
                return 0
            print("DEEPSEEK_API_KEY is required", file=sys.stderr)
            return 2

        response = chat_completion(
            api_key=api_key,
            base_url=args.base_url,
            model=args.model,
            messages=build_prompt(rule_id, rule_text, diff, args.source_label),
            max_tokens=args.max_tokens,
            timeout=args.timeout,
            thinking=args.thinking,
        )
        choice = response.get("choices", [{}])[0]
        finish_reason = choice.get("finish_reason")
        content = choice.get("message", {}).get("content")
        if finish_reason == "length":
            print(f"{rule_id}: model response hit max_tokens before producing a complete result", file=sys.stderr)
            return 2
        if not isinstance(content, str) or not content.strip():
            print(f"{rule_id}: model response did not include message content", file=sys.stderr)
            return 2
        try:
            parsed = parse_json_object(content)
        except (json.JSONDecodeError, ValueError) as exc:
            print(f"{rule_id}: failed to parse model JSON: {exc}", file=sys.stderr)
            print(content[:2000], file=sys.stderr)
            return 2

    result = normalize_result(rule_id, parsed)
    print(json.dumps(result, indent=2, sort_keys=True))
    print_annotations(result)
    write_step_summary(summary_markdown(result, rule_path, diff_bytes, args.model))

    if result["severity"] == "failure":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
