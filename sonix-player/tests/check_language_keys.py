#!/usr/bin/env python3
"""Check that every language file carries the same keys as English.

The player shows the raw tag when a translation is missing, so a key that only
exists in English is a visible defect in every other language. The files are
plain INI by design; this is the cheap gate that keeps them in step without the
deleted string extractor.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TREES = [
    REPO / "sonix-packer/assets/R1/usr/resource/sonix/language",
    REPO / "sonix-packer/assets/R3PII/usr/resource/sonix/language",
]

FORMAT = re.compile(r"%(?:[-+#0]*\d*(?:\.\d+)?[diouxXeEfgGcs%])|\{\d+\}")


def load(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        text = line.strip()
        if not text or text[0] in "#;[" or "=" not in text:
            continue
        key, value = text.split("=", 1)
        entries[key.strip()] = value.strip()
    return entries


def formats(value: str) -> list[str]:
    return sorted(FORMAT.findall(value))


def check_tree(tree: Path) -> list[str]:
    english_path = tree / "English.ini"
    if not english_path.is_file():
        return [f"{tree}: English.ini is missing"]

    english = load(english_path)
    errors: list[str] = []

    for key, value in english.items():
        if not value:
            errors.append(f"English.ini: {key} is empty")

    for path in sorted(tree.glob("*.ini")):
        if path.name == "English.ini":
            continue
        other = load(path)
        missing = sorted(set(english) - set(other))
        extra = sorted(set(other) - set(english))
        if missing:
            errors.append(f"{path.name}: missing {', '.join(missing)}")
        if extra:
            errors.append(f"{path.name}: extra {', '.join(extra)}")
        for key in sorted(set(english) & set(other)):
            if not other[key]:
                errors.append(f"{path.name}: {key} is empty")
            elif formats(english[key]) != formats(other[key]):
                errors.append(
                    f"{path.name}: {key} formats {formats(other[key])} != English {formats(english[key])}"
                )

    return errors


def main() -> int:
    errors: list[str] = []
    for tree in TREES:
        errors.extend(check_tree(tree))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"language keys: {len(TREES)} trees complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
