#!/usr/bin/env python3
"""Reject destructive OpenTofu production plans and emit a compact summary."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


SAFE_ACTIONS = {
    ("no-op",),
    ("read",),
    ("create",),
    ("update",),
}


def analyze(plan: dict[str, Any]) -> tuple[Counter[str], list[dict[str, Any]]]:
    counts: Counter[str] = Counter()
    blocked: list[dict[str, Any]] = []

    for resource in plan.get("resource_changes", []):
        actions = tuple(resource.get("change", {}).get("actions", []))
        label = "+".join(actions) if actions else "unknown"
        counts[label] += 1
        if actions not in SAFE_ACTIONS:
            blocked.append(
                {
                    "address": resource.get("address", "<unknown>"),
                    "actions": list(actions),
                }
            )

    return counts, blocked


def markdown_summary(
    counts: Counter[str], blocked: list[dict[str, Any]]
) -> str:
    lines = ["### OpenTofu Plan", "", "| Actions | Resources |", "| --- | ---: |"]
    if counts:
        lines.extend(f"| `{actions}` | {count} |" for actions, count in sorted(counts.items()))
    else:
        lines.append("| `no changes` | 0 |")

    if blocked:
        lines.extend(["", "Destructive changes blocked:"])
        lines.extend(
            f"- `{item['address']}`: `{'+'.join(item['actions']) or 'unknown'}`"
            for item in blocked
        )
    else:
        lines.extend(["", "No deletions or replacements detected."])
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan", type=Path, help="JSON output from tofu show -json")
    parser.add_argument(
        "--summary",
        type=Path,
        help="Append Markdown results to this file, such as GITHUB_STEP_SUMMARY.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    counts, blocked = analyze(plan)
    summary = markdown_summary(counts, blocked)
    sys.stdout.write(summary)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write(summary)
    if blocked:
        sys.stderr.write("Production plan contains destructive changes.\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
