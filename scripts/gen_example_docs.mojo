"""Generates docs/src/examples/*.md from examples/*.mojo -- run as
part of `pixi run docs` (see pixi.toml), before `mojo doc`/`modo
build`, so a new example file automatically gets a docs page without
anyone hand-writing one.

Each page shows the actual grammar-of-graphics pattern (Plot/Theme/
render), not this docs site's own supersampling/file-writing
plumbing every example also needs (see docs/src/_index.md's own
"A first chart" section, and examples/scatter.mojo's own docstring,
for why every example renders at 3x and shrinks back down). Extraction
strategy:

- If the example writes both raster and SVG output (most of them,
  from examples/donut.mojo's own docstring onward), the SVG-path
  construction is used as-is: unlike the raster path, it was never
  supersampled to begin with, so it's already the clean pattern -- no
  stripping needed, just cut the whole raster-specific block out.
- If an example is raster-only (no SVG), the raster block's own
  supersampling is stripped back out in place instead: `Canvas(w *
  _SUPERSAMPLE, h * _SUPERSAMPLE, ...)` -> `Canvas(w, h, ...)`,
  `scale=Float64(_SUPERSAMPLE)` (or a `var s = Float64(_SUPERSAMPLE)`
  local some examples reuse across several Theme(...) calls instead of
  repeating the inline form) removed from every Theme(...) it appears
  in, downsample()'s own output variable removed once write_bmp/
  write_png (which needed it) are also gone.

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
    d["scatter_svg"] = "Scatter (SVG)"
    d["line"] = "Line"
    d["line_smoothing"] = "Line Smoothing"
    d["bar"] = "Bar"
    d["diverging_bar"] = "Diverging Bar"
    d["grouped_bar"] = "Grouped Bar"
    d["stacked_bar"] = "Stacked Bar"
    d["area"] = "Area"
    d["area_smoothing"] = "Area Smoothing"
    d["pie"] = "Pie"
    d["donut"] = "Donut"
    d["categorical_color"] = "Categorical Color"
    d["bubble"] = "Bubble Chart"
    d["lollipop"] = "Lollipop"
    d["waterfall"] = "Waterfall"
    d["box"] = "Box Plot"
    d["candlestick"] = "Candlestick"
    d["bullet"] = "Bullet"
    d["gantt"] = "Gantt"
    d["histogram"] = "Histogram"
    d["slope"] = "Slope"
    d["facets"] = "Facets"
    d["facets_svg"] = "Facets (SVG)"
    d["layers"] = "Layers"
    d["titles"] = "Titles & Axis Labels"
    d["dynamic_margin"] = "Dynamic Left Margin"
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
    var cats = List[Category]()
    cats.append(Category(
        "Basic marks", "The core chart types -- one mark, default theme.",
        ["scatter", "line", "bar", "area", "pie"],
    ))
    cats.append(Category(
        "Data-driven encoding", "Mapping a data column onto color and/or size, not just position.",
        ["categorical_color", "bubble", "donut"],
    ))
    cats.append(Category(
        "Smoothing", "Catmull-Rom curve smoothing for LINE and AREA marks.",
        ["line_smoothing", "area_smoothing"],
    ))
    cats.append(Category(
        "Categorical business charts", "Chart types built for a categorical x-axis: rankings, timelines, progress.",
        ["lollipop", "waterfall", "gantt", "bullet", "diverging_bar", "grouped_bar", "stacked_bar"],
    ))
    cats.append(Category(
        "Statistical & financial", "Distributions, binned counts, and OHLC price data.",
        ["box", "histogram", "candlestick"],
    ))
    cats.append(Category(
        "Layout & composition", "Multiple plots, titles, and margin behavior beyond a single chart.",
        ["facets", "layers", "titles", "dynamic_margin", "slope"],
    ))
    cats.append(Category(
        "SVG backend", "The same charts rendered through SvgCanvas instead of Canvas.",
        ["scatter_svg", "facets_svg"],
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


def _strip_supersample(line: String) -> List[String]:
    """Returns a 0-length list to mean "drop this line entirely", or a
    1-length list holding the (possibly rewritten) line to keep --
    Mojo has no Optional[String] convenience used elsewhere in this
    file, and this reads just as clearly at each call site.
    """
    var stripped = line.strip()
    if stripped == "scale=Float64(_SUPERSAMPLE)," or stripped == "scale=s,":
        return List[String]()

    var l = line.replace(" * _SUPERSAMPLE", "")
    l = l.replace(", scale=Float64(_SUPERSAMPLE))", ")")
    l = l.replace(", scale=s)", ")")
    l = l.replace("(scale=Float64(_SUPERSAMPLE))", "()")
    l = l.replace("(scale=s)", "()")
    return [l]


def _extract_clean_body(source: String) -> List[String]:
    var body = _main_body_lines(source)

    var has_svg = False
    for l in body:
        if l.strip().startswith("var svg = SvgCanvas("):
            has_svg = True
            break

    # The raster-specific zone to strip (fully, if a clean SVG-path
    # reconstruction exists below to use instead; in place, if this
    # example has no SVG path at all and the raster block is the only
    # rendering to show). Starts at the earliest line that either
    # builds the supersampled Canvas or references _SUPERSAMPLE at
    # all (covering both the inline `scale=Float64(_SUPERSAMPLE)` and
    # `var s = Float64(_SUPERSAMPLE)` forms -- the latter can precede
    # `var c = Canvas(...)` by several lines, e.g. when it's shared
    # across a facet grid's own several Theme(...) calls). Ends at the
    # last write_bmp/write_png call, which is always this zone's own
    # final line in every example that has one.
    var raster_start = -1
    for i in range(len(body)):
        if body[i].strip().startswith("var c = Canvas(") or "_SUPERSAMPLE" in body[i]:
            raster_start = i
            break

    var raster_end = -1
    if raster_start != -1:
        for i in range(raster_start, len(body)):
            var stripped = body[i].strip()
            if stripped.startswith("write_bmp(") or stripped.startswith("write_png("):
                raster_end = i

    var clean = List[String]()
    if has_svg and raster_start != -1 and raster_end != -1:
        for i in range(0, raster_start):
            clean.append(body[i])
        for i in range(raster_end + 1, len(body)):
            clean.append(body[i])
    elif raster_start != -1 and raster_end != -1:
        # Raster-only example -- clean the zone in place instead of
        # cutting it, since it's the only rendering this page has to
        # show: downsample()'s own output variable removed (nothing
        # downstream needs it once write_bmp/write_png are gone too).
        for i in range(len(body)):
            if i < raster_start or i > raster_end:
                clean.append(body[i])
                continue
            var stripped = body[i].strip()
            if stripped.startswith("var out = downsample(") or stripped.startswith(
                "var s = Float64(_SUPERSAMPLE)"
            ):
                continue
            for l in _strip_supersample(body[i]):
                clean.append(l)
    else:
        clean = body^

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


def _imports_for(body_text: String) -> List[String]:
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

    if _word_in(body_text, "Theme"):
        lines.append("from dataviz_mojo.theme import Theme")
    if _word_in(body_text, "default_categorical_palette"):
        lines.append("from dataviz_mojo.color_scale import default_categorical_palette")
    return lines^


def _build_page(name: String, title: String) raises -> String:
    var source = _read_file(_EXAMPLES_DIR + "/" + name + ".mojo")
    var docstring = _extract_docstring(source)
    var hook = _first_sentence(docstring)
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
        "All of them share one pattern: build a `Plot`, `.encode()` your "
        "data onto it, optionally `.theme()`/`.labels()` it, then hand it "
        "to `render()` (raster) or `render_svg()` (vector)."
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
