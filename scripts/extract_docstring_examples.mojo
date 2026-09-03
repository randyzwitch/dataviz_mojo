"""`pixi run example`'s extraction step: writes every `Example:` block
the package's docstrings declare (`_example_docstrings.mojo`'s
`_pages()`) into a standalone `.mojo` file under docs/src/examples/
(generated and gitignored, alongside the .md pages and rendered
images), so `scripts/run_parallel.sh` can compile and run each one. A
broken `Example:` section therefore fails the build.

Deduplicated by (`file`, `fn_name`): `line`'s and `slope`'s pages both
come from `line()`'s docstring, so each unique function is extracted
once with every block it has. One file per block, named
`<fn_name>[_<slug of its heading>].mojo`.
"""

from _example_docstrings import _extract_example_blocks, _pages, _write_file

comptime _OUT_DIR = "docs/src/examples"


def _slug(heading: String) -> String:
    """A filename-safe fragment from an `Example (<heading>):` heading:
    lowercased, every run of non-alphanumeric characters collapsed to one
    underscore, so "Diverging bars (color_by_sign)" becomes
    "diverging_bars_color_by_sign".
    """
    var out = String("")
    var prev_was_sep = True  # leading separators are dropped, same as trailing ones below
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

    var seen = List[String]()  # "<file>::<fn_name>" pairs already extracted
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
