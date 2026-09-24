#!/usr/bin/env python3
"""Fail if a module under dataviz/core/ imports from a dataviz module
outside dataviz.core (#824).

Core is the layer that knows nothing about charts: scales, themes,
text, frames, legends, validation over channel structs. Marks depend
on it, and the builder and renderer depend on marks. An import the
other way (core reaching up for `Plot`, a renderer, or a mark's
helper) compiles fine, since Mojo resolves circular imports within a
package, so nothing but this check notices when one comes back.

Run from the repository root; `pixi run format-check` runs it.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "dataviz" / "core"
UPWARD = re.compile(r"^\s*(?:from|import)\s+dataviz\.(?!core\b)([\w.]+)")


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
    print("check_import_direction: dataviz/core/ imports only from dataviz.core")
    return 0


if __name__ == "__main__":
    sys.exit(main())
