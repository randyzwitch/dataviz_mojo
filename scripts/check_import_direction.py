#!/usr/bin/env python3
"""Fail if a module under dataviz/core/ imports from a dataviz module
outside dataviz.core (#824), or if anything imports from dataviz.plot a
name plot.mojo does not define (#825).

Core is the layer that knows nothing about charts: scales, themes,
text, frames, legends, validation over channel structs. Marks depend
on it, and the builder and renderer depend on marks. An import the
other way (core reaching up for `Plot`, a renderer, or a mark's
helper) compiles fine, since Mojo resolves circular imports within a
package, so nothing but this check notices when one comes back.

Mojo re-exports every name a module imports, so `from dataviz.plot
import _Orientation` resolves as long as plot.mojo imports it, and the
file that defines nothing but `Plot` was the package's import hub for
about 90 names. The second rule keeps every import naming the module
that defines the name.

Run from the repository root; `pixi run format-check` runs it.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "dataviz" / "core"
PLOT = ROOT / "dataviz" / "plot.mojo"
UPWARD = re.compile(r"^\s*(?:from|import)\s+dataviz\.(?!core\b)([\w.]+)")
DEFINITION = re.compile(r"^(?:def|struct|trait|comptime|alias) (\w+)", re.M)
# One branch, so a docstring left open cannot make this backtrack.
DOCSTRING = re.compile(r'"""[^"]*(?:"(?!"")[^"]*)*"""')
HUB_START = re.compile(r"^from dataviz\.plot import\s*(\(?)(.*)$")
SOURCE_DIRS = [
    "dataviz",
    "tests",
    "scripts",
    "benchmarks",
    "docs/cookbook_recipes",
    "docs/src/examples/quickstart",
]


def hub_imports(path: Path, allowed: set) -> list:
    """Names imported from dataviz.plot that plot.mojo does not define,
    with the line each appears on."""
    found = []
    lines = path.read_text().splitlines()
    number = 0
    while number < len(lines):
        match = HUB_START.match(lines[number])
        start = number
        number += 1
        if not match:
            continue
        body = match.group(2)
        if match.group(1) == "(":
            while ")" not in body:
                body += " " + lines[number]
                number += 1
        for name in re.findall(r"[A-Za-z_]\w*", body.split(")")[0]):
            if name not in allowed:
                found.append((start + 1, name))
    return found


def main() -> int:
    offenders = []
    for path in sorted(CORE.glob("*.mojo")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            match = UPWARD.match(line)
            if match:
                rel = path.relative_to(ROOT)
                offenders.append(f"  {rel}:{number}: {line.strip()}")
    if offenders:
        print(
            "check_import_direction: dataviz/core/ must not import from"
            " the rest of dataviz, but these lines do:",
            file=sys.stderr,
        )
        print("\n".join(offenders), file=sys.stderr)
        print(
            "Move the definition into core, or narrow the function to"
            " the values it reads (#824).",
            file=sys.stderr,
        )
        return 1
    code = DOCSTRING.sub("", PLOT.read_text())
    allowed = set(DEFINITION.findall(code))
    hub = []
    for directory in SOURCE_DIRS:
        for path in sorted((ROOT / directory).rglob("*.mojo")):
            if path == PLOT:
                continue
            for number, name in hub_imports(path, allowed):
                rel = path.relative_to(ROOT)
                hub.append(f"  {rel}:{number}: {name}")
    if hub:
        print(
            "check_import_direction: dataviz.plot defines only "
            + ", ".join(sorted(allowed))
            + ", but these lines import something else through it:",
            file=sys.stderr,
        )
        print("\n".join(hub), file=sys.stderr)
        print(
            "Import the name from the module that defines it (#825).",
            file=sys.stderr,
        )
        return 1
    print(
        "check_import_direction: dataviz/core/ imports only from"
        " dataviz.core, and dataviz.plot exports only what it defines"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
