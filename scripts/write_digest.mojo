"""Regenerate `tests/output_digest.txt`.

Run with `pixi run digest-update`, after a rendering change you meant to
make, and read the diff before committing it. See
`tests/test_output_digest.mojo` for why the file exists (#570).
"""

from test_output_digest import _digest_lines
from _digest_provenance import _provenance_line


def main() raises:
    var lines = _digest_lines()
    var out = String(
        "# One line per figure: name, raster digest, svg bytes, svg"
        " digest.\n"
        "# Every Mark first, then the compositions, which are"
        " hand-maintained\n"
        "# in tests/_composition_registry.mojo.\n"
        "# Regenerate with `pixi run digest-update`; see"
        " tests/test_output_digest.mojo.\n"
        + _provenance_line()
        + "\n"
    )
    for line in lines:
        out += line + "\n"
    var f = open("tests/output_digest.txt", "w")
    f.write(out)
    f.close()
    print("wrote", len(lines), "digests to tests/output_digest.txt")
