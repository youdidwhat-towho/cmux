#!/usr/bin/env python3
"""Create or update the LLM diff lint pull request comment."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request
from typing import Any


MARKER = "<!-- cmux-llm-diff-lint -->"


def load_results(results_dir: pathlib.Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    if not results_dir.exists():
        return results
    for path in sorted(results_dir.rglob("*.json")):
        try:
            parsed = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict) and "rule_id" in parsed:
            results.append(parsed)
    return results


def status_for(result: dict[str, Any]) -> str:
    severity = str(result.get("severity") or "none")
    if severity == "failure":
        return "failed"
    if severity == "warning":
        return "warning"
    return "passed"


def markdown_escape_cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", "<br>")


def build_body(
    *,
    results: list[dict[str, Any]],
    pr_url: str,
    run_url: str,
    diff_url: str,
) -> str:
    failures = sum(1 for result in results if result.get("severity") == "failure")
    warnings = sum(1 for result in results if result.get("severity") == "warning")
    passed = sum(1 for result in results if result.get("severity") == "none")

    lines = [
        MARKER,
        "### LLM diff lint",
        "",
        f"PR: {pr_url}",
        f"Run: {run_url}",
        f"Diff: {diff_url}",
        "",
        f"Result: {failures} failed, {warnings} warning, {passed} passed.",
        "",
        "| Rule | Status | Summary |",
        "| --- | --- | --- |",
    ]

    if results:
        for result in sorted(results, key=lambda item: str(item.get("rule_id") or "")):
            lines.append(
                "| {rule} | {status} | {summary} |".format(
                    rule=markdown_escape_cell(f"`{result.get('rule_id', '')}`"),
                    status=markdown_escape_cell(status_for(result)),
                    summary=markdown_escape_cell(result.get("summary", "")),
                )
            )
    else:
        lines.append("| none | failed | No LLM diff lint result artifacts were found. |")

    finding_lines: list[str] = []
    for result in sorted(results, key=lambda item: str(item.get("rule_id") or "")):
        findings = result.get("findings")
        if not isinstance(findings, list) or not findings:
            continue
        finding_lines.extend(["", f"#### `{result.get('rule_id', '')}`"])
        for finding in findings:
            if not isinstance(finding, dict):
                continue
            location = str(finding.get("file") or "unknown")
            if isinstance(finding.get("line"), int):
                location += f":{finding['line']}"
            why = str(finding.get("why") or result.get("summary") or "Violation found.")
            finding_lines.append(f"- `{location}`: {why}")

    if finding_lines:
        lines.extend(["", "Findings:"])
        lines.extend(finding_lines)

    return "\n".join(lines) + "\n"


def github_request(method: str, path: str, token: str, data: dict[str, Any] | None = None) -> Any:
    url = f"https://api.github.com{path}"
    body = None if data is None else json.dumps(data).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = response.read().decode("utf-8")
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as exc:
        print(exc.read().decode("utf-8", errors="replace"), file=sys.stderr)
        raise SystemExit(exc.code) from exc


def upsert_comment(repo: str, pr_number: str, token: str, body: str) -> str:
    comments = github_request("GET", f"/repos/{repo}/issues/{pr_number}/comments?per_page=100", token)
    if isinstance(comments, list):
        for comment in comments:
            if isinstance(comment, dict) and MARKER in str(comment.get("body") or ""):
                updated = github_request("PATCH", f"/repos/{repo}/issues/comments/{comment['id']}", token, {"body": body})
                return str(updated.get("html_url") if isinstance(updated, dict) else "")
    created = github_request("POST", f"/repos/{repo}/issues/{pr_number}/comments", token, {"body": body})
    return str(created.get("html_url") if isinstance(created, dict) else "")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results-dir", required=True, type=pathlib.Path)
    parser.add_argument("--pr-number", required=True)
    parser.add_argument("--pr-url", required=True)
    parser.add_argument("--diff-url", required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    repo = os.environ.get("GITHUB_REPOSITORY")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    body = build_body(
        results=load_results(args.results_dir),
        pr_url=args.pr_url,
        run_url=args.run_url,
        diff_url=args.diff_url,
    )

    if args.dry_run:
        print(body)
        return 0

    if not repo:
        print("GITHUB_REPOSITORY is required", file=sys.stderr)
        return 2
    if not token:
        print("GH_TOKEN or GITHUB_TOKEN is required", file=sys.stderr)
        return 2

    comment_url = upsert_comment(repo, args.pr_number, token, body)
    print(comment_url)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
