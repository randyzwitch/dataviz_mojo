"""Extract registered docstring examples into runnable Mojo programs.

Functions are deduplicated by file and name. Each example block is written as
`<function>[_<heading-slug>].mojo` under `docs/src/examples`.
"""

from _example_docstrings import _extract_example_blocks, _pages, _write_file

comptime _OUT_DIR = "docs/src/examples"


def _slug(heading: String) -> String:
    """Convert an example heading to a lowercase filename fragment."""
    var out = String("")
    var prev_was_sep = True  # Drop leading separators.
    for ch in heading.lower():
        if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
            out += ch
            prev_was_sep = False
        elif not prev_was_sep:
            out += "_"
            prev_was_sep = True
    return String(out.rstrip("_"))


def main() raises:
    var pages = _pages()

    var seen = List[String]()  # Extracted "<file>::<fn_name>" pairs.
    var written = 0
    for p in pages:
        var key = p.file + "::" + p.fn_name
        if key in seen:
            continue
        seen.append(key)

        var blocks = _extract_example_blocks(p.fn_name, p.file, p.is_method)
        for block in blocks:
            var suffix = ("_" + _slug(block.heading)) if block.heading else ""
            var path = _OUT_DIR + "/" + p.fn_name + suffix + ".mojo"
            _write_file(path, String("\n").join(block.lines))
            written += 1

    print("Wrote", written, "docstring-example programs to", _OUT_DIR)
