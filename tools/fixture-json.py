#!/usr/bin/env python3
"""Turn a captured quickfix fixture into the JSON the Rust core emits.

Every field this adds is constant for the Vim9 analyzer: it reports
ghosts alone, in Vim9 alone, always at column 1. The summary counts are
left out on purpose, because the old analyzer's `unresolved` number
counts its own regex scanner's accidental matches and is not a contract.

License: GNU GPL 3.0
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

LINE = re.compile(r"^(?P<file>.+):(?P<line>\d+):(?P<col>\d+):\[ghost\] (?P<kind>.+?) (?P<name>\S+)$")


def findings(text: str) -> list[dict[str, object]]:
    out = []
    for raw in text.splitlines():
        if not raw.strip():
            continue
        m = LINE.match(raw)
        if not m:
            raise SystemExit(f"fixture line not understood: {raw}")
        out.append({
            "class": "ghost",
            "kind": m["kind"],
            "name": m["name"],
            "file": m["file"],
            "line": int(m["line"]),
            "col": int(m["col"]),
            "lang": "vim9",
        })
    return out


def main() -> int:
    txt, root = Path(sys.argv[1]), sys.argv[2]
    report = {
        "schema": 1,
        "root": root,
        "findings": findings(txt.read_text(encoding="utf-8")),
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
