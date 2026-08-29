"""`pixi run example`'s own script -- extracts every `Example:` block
this package's docstrings declare (`_example_docstrings.mojo`'s
`_pages()`) into a real, standalone `.mojo` file under docs/src/
examples/ (already entirely generated/gitignored, same as the .md
pages gen_example_docs.mojo writes there and the .svg/.png/.bmp images
each extracted program's own save() call writes there too -- one
generated-docs-content location, not a second, separately-gitignored
build directory for no real benefit), so `scripts/run_parallel.sh` can
compile and run every one of them for real, same as `examples/*.mojo`
used to. This is what makes an `Example:` section a load-bearing test,
not just documentation text: a broken one fails to compile or run
here, the same way a broken `examples/*.mojo` file always did.

Deduplicated by (`file`, `fn_name`) -- `line`'s and `slope`'s pages
both come from `line()`'s own docstring (`slope` shows only one of its
two `Example:` blocks, `line` shows both, see `ExamplePage.block`'s
docstring), so extracting once per unique function, every block it
has, covers both pages' needs without compiling the same program
twice under two different pages' names. One temp file per block,
named `<fn_name>[_<slug of its own heading>].mojo`.
"""

from _example_docstrings import _extract_example_blocks, _pages, _write_file

comptime _OUT_DIR = "docs/src/examples"


def _slug(heading: String) -> String:
    """A plain filename-safe fragment out of an `Example (<heading>):`
    block's own heading text -- lowercased, every run of non-alphanumeric
    characters collapsed to one underscore, so "Diverging bars
    (color_by_sign)" becomes "diverging_bars_color_by_sign"."""
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
