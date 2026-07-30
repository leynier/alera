#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from validate_tofu_plan import analyze


FIXTURES = Path(__file__).parent / "testdata"


class ValidateTofuPlanTest(unittest.TestCase):
    def load(self, name: str) -> dict:
        return json.loads((FIXTURES / f"{name}.json").read_text(encoding="utf-8"))

    def test_create_is_allowed(self) -> None:
        counts, blocked = analyze(self.load("create"))
        self.assertEqual(counts["create"], 1)
        self.assertEqual(blocked, [])

    def test_update_is_allowed(self) -> None:
        counts, blocked = analyze(self.load("update"))
        self.assertEqual(counts["update"], 1)
        self.assertEqual(blocked, [])

    def test_delete_is_blocked(self) -> None:
        _, blocked = analyze(self.load("delete"))
        self.assertEqual(blocked[0]["actions"], ["delete"])

    def test_replacement_is_blocked_in_both_orders(self) -> None:
        _, blocked = analyze(self.load("replace"))
        self.assertEqual(
            [item["actions"] for item in blocked],
            [["delete", "create"], ["create", "delete"]],
        )


if __name__ == "__main__":
    unittest.main()
