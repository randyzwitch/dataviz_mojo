"""Generates docs/src/examples/*.md from examples/*.mojo -- run as
part of `pixi run docs` (see pixi.toml), before `mojo doc`/`modo
build`, so a new example file automatically gets a docs page without
anyone hand-writing one.

Each page shows the actual grammar-of-graphics pattern -- every
example's raster output is built via a one-call convenience function
now (`bar()`, `scatter()`, ...; see plot.mojo's own module docstring
for what these are, and dataviz_mojo/__init__.mojo's own docstring for
why every one is imported from the package itself rather than the
mark file it happens to live in), each already the cleanest possible
reconstruction of "how would I actually write this" -- not this docs
site's own file-writing plumbing every example also needs, and not
even the supersampling every one of these functions bakes into its
own output now (see dataviz_mojo.plot._rendered's own docstring):
there's nothing left to strip out of the shown snippet on that front
at all, unlike when every example spelled its own `_SUPERSAMPLE`
handling out by hand. Extraction strategy:

- The example's raster output is always built via a one-call
  convenience function (`var c = bar(...)`, `var c = scatter(...)`,
  ...) -- that call is the snippet shown, verbatim (see
  `_quickplot_call_start()`). Everything after that call's own closing
  `)` -- write_bmp/png, any separate SvgCanvas/render_svg() block -- is
  cut entirely, not shown.

A Mojo script, not Python -- this repo's own tooling stays in the
language it's showcasing, string-matching primitives (`.strip()`,
`.startswith()`, `.replace()`, `.find()`, `in`) doing the same job
Python's `re` module did in an earlier version of this file, without
needing Mojo to have its own regex module (it doesn't, as of this
writing).

Adding a new example: add it to both `_titles()` and exactly one
category in `_categories()` below -- `main()`'s own assertions catch a
missing entry either way (a real .mojo file with no category, or a
category referencing a name that doesn't exist) rather than silently
skipping it or crashing deep in string formatting.
"""

from std.collections import Dict
from std.os import listdir

comptime _REPO = "."
comptime _EXAMPLES_DIR = "examples"
comptime _OUT_DIR = "docs/src/examples"
comptime _WORD_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"


def _titles() -> Dict[String, String]:
    var d = Dict[String, String]()
    d["scatter"] = "Scatter"
    d["line"] = "Line"
    d["bar"] = "Bar"
    d["diverging_bar"] = "Diverging Bar"
    d["grouped_bar"] = "Grouped Bar"
    d["stacked_bar"] = "Stacked Bar"
    d["area"] = "Area"
    d["pie"] = "Pie"
    d["donut"] = "Donut"
    d["lollipop"] = "Lollipop"
    d["waterfall"] = "Waterfall"
    d["box"] = "Box Plot"
    d["candlestick"] = "Candlestick"
    d["bullet"] = "Bullet"
    d["gantt"] = "Gantt"
    d["population_pyramid"] = "Population Pyramid"
    d["heatmap"] = "Heatmap"
    d["chord"] = "Chord"
    d["single_axis"] = "Single Axis"
    d["effect_scatter"] = "Effect Scatter"
    d["funnel"] = "Funnel"
    d["bump"] = "Bump"
    d["streamgraph"] = "Streamgraph"
    d["beeswarm"] = "Beeswarm"
    d["violin"] = "Violin"
    d["ridgeline"] = "Ridgeline"
    d["nightingale"] = "Nightingale Rose"
    d["polarbar"] = "Polar Bar"
    d["polar"] = "Polar"
    d["radar"] = "Radar"
    d["gauge"] = "Gauge"
    d["histogram"] = "Histogram"
    d["slope"] = "Slope"
    return d^


struct Category(Copyable, Movable):
    var title: String
    var blurb: String
    var names: List[String]

    def __init__(out self, title: String, blurb: String, var names: List[String]):
        self.title = title
        self.blurb = blurb
        self.names = names^


def _categories() -> List[Category]:
    # Every example here is a distinct, recognizable chart type -- no
    # feature demos (facets, layers, titles, dynamic margins, color/
    # size encoding, line/area smoothing, a bare SVG-backend page)
    # mixed in among them; those are real dataviz_mojo capabilities,
    # just not chart types of their own, so they live in the wiki/API
    # reference instead of the Examples gallery.
    var cats = List[Category]()
    cats.append(Category(
        "Basic marks", "The core chart types -- one mark, default theme (donut is pie's own ring variant).",
        ["scatter", "line", "bar", "area", "pie", "donut", "single_axis", "effect_scatter"],
    ))
    cats.append(Category(
        "Categorical business charts",
        "Chart types built around one categorical dimension: rankings, timelines, progress,"
        " period-over-period comparisons, and process stages.",
        [
            "lollipop", "waterfall", "gantt", "population_pyramid", "bullet", "diverging_bar",
            "grouped_bar", "stacked_bar", "slope", "funnel", "bump", "streamgraph",
        ],
    ))
    cats.append(Category(
        "Statistical & financial", "Distributions, binned counts, grid/matrix data, and OHLC price data.",
        ["box", "histogram", "heatmap", "candlestick", "beeswarm", "violin", "ridgeline"],
    ))
    cats.append(Category(
        "Relationships & flows", "Weighted connections between entities, not a value per category.",
        ["chord"],
    ))
    cats.append(Category(
        "Radial & polar",
        "Chart types built on a polar (angle + radius) coordinate system instead of a cartesian one.",
        ["nightingale", "polarbar", "polar", "radar", "gauge"],
    ))
    return cats^


def _read_file(path: String) raises -> String:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    return content


def _write_file(path: String, content: String) raises:
    var f = open(path, "w")
    f.write(content)
    f.close()


def _extract_docstring(source: String) -> String:
    var start = source.find('"""')
    if start == -1:
        return ""
    var content_start = start + 3
    var end = source.find('"""', content_start)
    if end == -1:
        return ""
    var raw = String(source[byte=content_start:end])
    return String(raw.strip())


def _first_sentence(docstring: String) -> String:
    # Every docstring here starts "Demo: <one-line hook> -- <detail>".
    # Collapse hand-wrapped newlines within the first paragraph into a
    # single flowing line, then cut at the first " -- " boundary (the
    # hook) if there is one, else keep the whole first sentence.
    var para_end = docstring.find("\n\n")
    var first_para = String(docstring[byte=0:para_end]) if para_end != -1 else docstring

    var words = List[String]()
    for line in first_para.split("\n"):
        var stripped = String(line.strip())
        if stripped:
            words.append(stripped)
    var flat = String(" ").join(words)

    if flat.startswith("Demo: "):
        var without_prefix = String(flat[byte=6:])  # 6 == len("Demo: ")
        flat = without_prefix

    var idx = flat.find(" -- ")
    var sentence = String(flat[byte=0:idx]) if idx != -1 else flat
    var trimmed = String(sentence.strip())
    sentence = trimmed
    if sentence.endswith("."):
        var without_dot = String(sentence[byte=0 : sentence.byte_length() - 1])
        sentence = without_dot
    sentence = sentence + "."

    var first_char = String(sentence[byte=0:1]).upper()
    return first_char + String(sentence[byte=1:])


def _has_call(source: String, func_name: String) -> Bool:
    return (func_name + "(") in source


def _main_body_lines(source: String) -> List[String]:
    var lines = source.split("\n")
    var start = -1
    for i in range(len(lines)):
        if lines[i].startswith("def main("):
            start = i
            break
    var body = List[String]()
    for i in range(start + 1, len(lines)):
        body.append(String(lines[i]))
    while len(body) > 0 and not body[len(body) - 1].strip():
        _ = body.pop()
    return body^


def _strip_indent(lines: List[String]) -> List[String]:
    """Body lines come indented 4 spaces under `def main()`; the
    snippet stands alone, so drop that one level uniformly."""
    var out = List[String]()
    for l in lines:
        out.append(String(l[byte=4:]) if l.startswith("    ") else l)
    return out^


def _word_in(text: String, word: String) -> Bool:
    """Whether `word` occurs in `text` as a whole identifier, not just
    a substring -- Mojo has no regex \\b, so this checks the
    characters immediately surrounding every match by hand. Needed
    because several of this file's own symbols are prefixes of others
    (`render` of `render_svg`/`render_facets`/...), and a plain
    substring `in` check would wrongly count a file that only calls
    `render_svg(...)` as also using bare `render`.
    """
    var start = 0
    while True:
        var idx = text.find(word, start)
        if idx == -1:
            return False
        var before_ok = idx == 0 or (text[byte = idx - 1 : idx] not in _WORD_CHARS)
        var after = idx + word.byte_length()
        var after_ok = after >= text.byte_length() or (text[byte=after : after + 1] not in _WORD_CHARS)
        if before_ok and after_ok:
            return True
        start = idx + 1


def _quickplot_names() -> List[String]:
    """Every one-call convenience function's own name -- each lives in
    its own mark's file now (see plot.mojo's own module docstring), not
    one shared quickplot.mojo, but every one is still imported the same
    way (`from dataviz_mojo import <name>`, see dataviz_mojo/__init__.
    mojo's own docstring), which is all this list-of-names approach
    ever needed to be true. Kept as one list both `_quickplot_call_
    start()` (does this example build its raster output via one of
    these?) and `_imports_for()` (does the clean snippet need `from
    dataviz_mojo import <name>`?) share, so a 14th one only needs adding
    here."""
    return [
        "scatter", "line", "area", "bar", "pie", "lollipop", "waterfall",
        "box", "candlestick", "bullet", "gantt", "grouped_bar", "stacked_bar",
        "histogram", "population_pyramid", "heatmap", "chord", "single_axis", "effect_scatter",
        "funnel", "bump", "streamgraph", "beeswarm", "violin", "ridgeline", "nightingale", "polarbar", "polar", "radar", "gauge",
    ]


def _color_constant_names() raises -> List[String]:
    """Every `dataviz_mojo.colors` constant's own name, parsed directly
    out of colors.mojo itself (`comptime NAME = Color(...)`) rather
    than hardcoded a second time here the way `_quickplot_names()`
    is -- that list is short and hand-curated on purpose (a 14th
    quickplot function is a real, deliberate addition worth a line of
    its own); colors.mojo's own ~148 names are a fixed, already-
    standard vocabulary sourced from the CSS spec once (see that
    file's own docstring), and re-typing all of them a second time
    here would just be a second place they could drift out of sync.
    """
    var names = List[String]()
    var source = _read_file("dataviz_mojo/colors.mojo")
    for line in source.split("\n"):
        var stripped = String(line.strip())
        if stripped.startswith("comptime "):
            var after = String(stripped[byte=9:])  # 9 == len("comptime ")
            var eq = after.find(" = ")
            if eq != -1:
                names.append(String(after[byte=0:eq]))
    return names^


def _quickplot_call_start(body: List[String]) -> Int:
    """The line index of `var c = <quickplot fn>(...`, or -1 if this
    example doesn't build its raster output that way. Written either
    as one line (`var c = scatter(x, y)`, whenever the call is short
    enough) or, once there's enough kwargs to want one per line, the
    multi-line shape (the opening line ends `(`, one argument per
    line, a lone `)` closes it -- see any of examples/bar.mojo/
    scatter.mojo/etc. for either). Either way the call's own function
    name sits right after `var c = ` and before its own first `(`, so
    matching that is enough regardless of which shape follows;
    `_quickplot_call_end()` finds wherever the call itself actually
    closes."""
    var names = _quickplot_names()
    for i in range(len(body)):
        var stripped = body[i].strip()
        if not stripped.startswith("var c = "):
            continue
        var after = String(stripped[byte=8:])  # 8 == len("var c = ")
        var paren = after.find("(")
        if paren == -1:
            continue
        var name = String(after[byte=0:paren])
        if name in names:
            return i
    return -1


def _quickplot_call_end(body: List[String], start: Int) -> Int:
    """`start`'s own line already closes the call (a single-line
    `var c = scatter(x, y)`) if it ends with `)` -- checked before
    scanning further, since a multi-line call's own opening line never
    does (it always ends `(`, per `_quickplot_call_start`'s own
    docstring). Otherwise, the matching close is the first line below
    `start` that's a lone `)` with nothing else on it."""
    if body[start].strip().endswith(")"):
        return start
    for i in range(start + 1, len(body)):
        if body[i].strip() == ")":
            return i
    return -1


def _extract_clean_body(source: String) raises -> List[String]:
    """Every example's raster output is built via a one-call
    convenience function now (see this file's own module docstring),
    so this has exactly one shape to extract: the `var c = <fn>(...)`
    call verbatim, shown as-is with nothing left to strip out of it --
    everything before it (data setup) kept, everything from its own
    closing `)` onward (write_bmp/png, any separate SvgCanvas/
    render_svg() block) cut. Raises rather than silently falling back
    to showing the whole file (which used to be `_extract_clean_body`'s
    own fallback, back when a raster-only-no-quickplot example was a
    real, expected shape) -- a future example that doesn't fit this
    pattern needs a real decision about how its own page should look,
    not a silently-wrong one.
    """
    var body = _main_body_lines(source)

    var qp_start = _quickplot_call_start(body)
    if qp_start == -1:
        raise Error(
            "gen_example_docs: no one-call convenience function call"
            " (`var c = <fn>(...)`) found -- every example's raster"
            " output is expected to be built that way now"
        )
    var qp_end = _quickplot_call_end(body, qp_start)
    var qp_clean = List[String]()
    for i in range(0, qp_end + 1):
        qp_clean.append(body[i])
    return _finish_clean_body(qp_clean)


def _finish_clean_body(clean: List[String]) -> List[String]:
    """The cleanup every extraction path (quickplot call, SVG-path
    cut, in-place raster desupersampling) shares once its own
    mark-specific work is done: drop leftover write_bmp/write_png/
    write_svg/print() I/O lines, drop a now-empty `.theme(Theme())`
    method call, collapse the blank lines that leaves behind, and undo
    `def main()`'s own 4-space indent."""
    var without_io = List[String]()
    for l in clean:
        var stripped = l.strip()
        if (
            stripped.startswith("write_bmp(")
            or stripped.startswith("write_png(")
            or stripped.startswith("write_svg(")
            or stripped.startswith("print(")
        ):
            continue
        without_io.append(l)

    # Drop a now-fully-empty `.theme()` call entirely if that was a
    # plot's *only* theme customization (Theme() with no args left is
    # a no-op -- not wrong, just noise in a "here's the essential
    # pattern" snippet). A line that existed only to hold that call
    # (its own line in a multi-line builder chain) is dropped outright
    # rather than left behind as an orphaned blank line -- distinct
    # from an already-blank line elsewhere, which is real spacing and
    # stays.
    var theme_stripped = List[String]()
    for l in without_io:
        var new_l = l.replace(".theme(Theme())", "")
        if not new_l.strip() and l.strip():
            continue
        theme_stripped.append(new_l)

    while len(theme_stripped) > 0 and not theme_stripped[0].strip():
        _ = theme_stripped.pop(0)
    while len(theme_stripped) > 0 and not theme_stripped[len(theme_stripped) - 1].strip():
        _ = theme_stripped.pop()
    var collapsed = List[String]()
    for l in theme_stripped:
        if not l.strip() and len(collapsed) > 0 and not collapsed[len(collapsed) - 1].strip():
            continue
        collapsed.append(l)
    return _strip_indent(collapsed)


def _imports_for(body_text: String) raises -> List[String]:
    var lines = List[String]()
    if _word_in(body_text, "Color"):
        lines.append("from canvas_mojo.color import Color")
    if _word_in(body_text, "Canvas"):
        lines.append("from canvas_mojo.buffer import Canvas")
    if _word_in(body_text, "SvgCanvas"):
        lines.append("from canvas_mojo.vector.svg import SvgCanvas")

    var plot_symbols: List[String] = [
        "Plot", "render", "render_svg", "render_facets", "render_facets_svg",
        "render_layers", "render_layers_svg",
    ]
    var used = List[String]()
    for s in plot_symbols:
        if _word_in(body_text, s):
            used.append(s)
    if len(used) > 0:
        lines.append("from dataviz_mojo.plot import " + String(", ").join(used))

    var used_qp = List[String]()
    for n in _quickplot_names():
        if _word_in(body_text, n):
            used_qp.append(n)
    if len(used_qp) > 0:
        lines.append("from dataviz_mojo import " + String(", ").join(used_qp))

    if _word_in(body_text, "Theme"):
        lines.append("from dataviz_mojo.theme import Theme")
    if _word_in(body_text, "default_categorical_palette"):
        lines.append("from dataviz_mojo.color_scale import default_categorical_palette")

    var used_colors = List[String]()
    for n in _color_constant_names():
        if _word_in(body_text, n):
            used_colors.append(n)
    if len(used_colors) > 0:
        lines.append("from dataviz_mojo.colors import " + String(", ").join(used_colors))

    return lines^


def _build_page(name: String, title: String) raises -> String:
    var source = _read_file(_EXAMPLES_DIR + "/" + name + ".mojo")
    var docstring = _extract_docstring(source)
    var hook = _first_sentence(docstring)

    # SVG is the preferred display format -- a vector image stays crisp
    # at any zoom/pane size a browser puts it in, unlike a fixed-
    # resolution raster snapshot, and every example now writes one (see
    # examples/*.mojo's own "Writes both a raster ... and a vector ..."
    # docstring paragraph). This holds even for a quickplot-built
    # example, whose *shown* snippet only constructs the raster Canvas
    # (that separate SvgCanvas/render_svg() block is cut from the
    # snippet entirely -- see _extract_clean_body()'s own docstring):
    # the two backends render the identical chart from the identical
    # data, so the .svg is still an accurate picture of what the shown
    # snippet's quickplot call produces, just via the file's other
    # (unshown) render path. Falls back to .png only for an example
    # that doesn't write an .svg at all -- none do today, but a future
    # one demoing raster-only output (PNG/BMP specifically) would land
    # here instead of being forced into a vector image it never builds.
    var image = "out_" + name + ".svg" if _has_call(source, "write_svg") else "out_" + name + ".png"

    var clean_body = _extract_clean_body(source)
    var body_text = String("\n").join(clean_body)
    var import_lines = _imports_for(body_text)

    var indented = List[String]()
    for l in clean_body:
        indented.append("    " + l if l.strip() else "")

    var snippet = String("\n").join(import_lines)
    if len(import_lines) > 0:
        snippet += "\n\n"
    snippet += "def main() raises:\n" + String("\n").join(indented)

    var page = List[String]()
    page.append("---")
    page.append("title: " + title)
    page.append("---")
    page.append("")
    page.append(hook)
    page.append("")
    page.append("![" + title + "](" + image + ")")
    page.append("")
    page.append("## Usage")
    page.append("")
    page.append("```mojo")
    page.append(snippet)
    page.append("```")
    page.append("")
    return String("\n").join(page)


def main() raises:
    var titles = _titles()
    var categories = _categories()

    var all_names = List[String]()
    for entry in listdir(_EXAMPLES_DIR):
        if entry.endswith(".mojo"):
            all_names.append(String(entry[byte=0 : entry.byte_length() - 5]))  # 5 == len(".mojo")
    sort(all_names)

    var categorized = List[String]()
    for cat in categories:
        for n in cat.names:
            categorized.append(n)

    for n in all_names:
        if n not in categorized:
            raise Error("Example not placed in any category: " + n)
    for n in categorized:
        if n not in all_names:
            raise Error("Category references a non-existent example: " + n)
    for n in all_names:
        if n not in titles:
            raise Error("Example has no title: " + n)

    for n in all_names:
        var page = _build_page(n, titles[n])
        _write_file(_OUT_DIR + "/" + n + ".md", page)

    var idx = List[String]()
    idx.append("---")
    idx.append("title: Examples")
    idx.append("type: docs")
    idx.append("weight: 200")
    idx.append("cascade:")
    idx.append("  type: docs")
    idx.append("---")
    idx.append("")
    idx.append(
        "Every example below is a complete, runnable `.mojo` file in this "
        "repo's own `examples/` directory -- each page shows the actual "
        "grammar-of-graphics pattern next to its actual rendered output, "
        "so you can see exactly what it takes to produce that chart."
    )
    idx.append("")
    idx.append(
        "Most reach for a single one-call convenience function -- "
        "`bar(categories, values)`, `scatter(x, y)`, and so on, one per "
        "mark, imported straight from `dataviz_mojo` -- built on top of "
        "the fuller `Plot` builder (`.encode()`/`.theme()`/`.labels()`, "
        "then `render()`) that the rest still use directly, for whatever "
        "these don't cover yet."
    )
    idx.append("")
    for cat in categories:
        idx.append("## " + cat.title)
        idx.append("")
        idx.append(cat.blurb)
        idx.append("")
        for n in cat.names:
            idx.append("- [" + titles[n] + "](" + n + "/)")
        idx.append("")
    _write_file(_OUT_DIR + "/_index.md", String("\n").join(idx))

    print("Wrote", len(all_names), "example pages + _index.md to", _OUT_DIR)
