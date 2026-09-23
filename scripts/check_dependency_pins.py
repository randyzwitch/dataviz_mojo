#!/usr/bin/env python3
"""Require matching Mojo and canvas_mojo pins in every dependency section."""

import sys
import tomllib
from pathlib import Path


SECTIONS = (
    ("[dependencies]", ("dependencies",)),
    ("[package.host-dependencies]", ("package", "host-dependencies")),
    ("[package.run-dependencies]", ("package", "run-dependencies")),
)


def main() -> int:
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("pixi.toml")
    if len(sys.argv) > 2:
        print("usage: check_dependency_pins.py [pixi.toml]", file=sys.stderr)
        return 2

    with manifest.open("rb") as source:
        data = tomllib.load(source)

    failed = False
    for dependency in ("mojo", "canvas_mojo"):
        values = []
        for section_name, path in SECTIONS:
            section = data
            for key in path:
                section = section.get(key, {})
            values.append((section_name, section.get(dependency)))

        if any(value is None for _, value in values) or any(
            value != values[0][1] for _, value in values[1:]
        ):
            failed = True
            print(f"check_dependency_pins: {dependency} differs across sections:")
            for section_name, value in values:
                print(f"  {section_name}: {value!r}")

    if not failed:
        print("check_dependency_pins: mojo and canvas_mojo agree across all three sections")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
