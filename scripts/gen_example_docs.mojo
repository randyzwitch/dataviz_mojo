"""Generates docs/src/examples/*.md from examples/*.mojo -- run as
part of `pixi run docs` (see pixi.toml), before `mojo doc`/`modo
build`, so a new example file automatically gets a docs page without
anyone hand-writing one.

Each page shows the actual grammar-of-graphics pattern -- most
examples build their `Plot` via a one-call convenience function
(`bar()`, `scatter()`, ...; see plot.mojo's own module docstring for
what these are, and dataviz_mojo/__init__.mojo's own docstring for why
every one is imported from the package itself rather than the mark
file it happens to live in). That call returns a plain, un-rendered
`Plot` (dataviz_mojo.plot._finished's docstring) -- rendering and
supersampling only happen inside `render()`/`save()` themselves (see
`_RASTER_SUPERSAMPLE`'s docstring, plot.mojo), automatically, for any
`Plot` regardless of how it was built, so there's nothing to strip out
of the shown snippet on that front at all. Extraction strategy:

- The example's `Plot` is usually built via a one-call convenience
  function (`var c = bar(...)`, `var c = scatter(...)`, ...) -- that
  call is the snippet shown, verbatim (see `_quickplot_call_starts()`).
  Everything after that call's own closing `)` -- the `save()` calls
  that actually write it out -- is cut entirely, not shown. An example
  file with more than one such call (examples/bar.mojo's own
  diverging-bars variant, alongside its plain bar chart) gets one
  section per call on its own page instead of a page each -- see
  `_build_sections()`.

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
    d["grouped_bar"] = "Grouped Bar"
    d["stacked_bar"] = "Stacked Bar"
    d["area"] = "Area"
    d["pie"] = "Pie/Donut"
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
    d["radialbar"] = "Radial Bar"
    d["polar"] = "Polar"
    d["polar_series"] = "Polar (Multi-Series)"
    d["radar"] = "Radar"
    d["gauge"] = "Gauge"
    d["parallel"] = "Parallel Coordinates"
    d["span_chart"] = "Span Chart"
    d["calendar_heatmap"] = "Calendar Heatmap"
    d["corrplot"] = "Correlation Plot"
    d["punchcard"] = "Punchcard"
    d["marimekko"] = "Marimekko"
    d["sunburst"] = "Sunburst"
    d["tree"] = "Tree"
    d["treemap"] = "Treemap"
    d["arc_diagram"] = "Arc Diagram"
    d["graph"] = "Graph"
    d["sankey"] = "Sankey"
    d["histogram"] = "Histogram"
    d["slope"] = "Slope"
    d["annotate_line"] = "Reference Line"
    d["svg_accessibility"] = "SVG Accessibility"
    d["annotate_area"] = "Reference Band"
    d["dual_axis"] = "Dual Y-Axis"
    d["annotate_vline_point"] = "Vertical Line & Point"
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
    # reference instead of the Examples gallery. annotate_line,
    # svg_accessibility, annotate_area, dual_axis, and annotate_vline_
    # point are the five exceptions: unlike facets/layers/titles, none
    # has a simpler existing example to piggyback on -- none of Plot.
    # annotate_line(), Plot.annotate_area(), Plot.annotate_vline(),
    # Plot.annotate_point(), or Plot.secondary_axis() is exposed on any
    # quickplot function, and accessible_svg_string()/write_accessible_
    # svg() are a standalone SVG-writing utility with no Plot method of
    # their own at all (see each one's own docstring) -- so there's no
    # other "how do I use this" page anywhere else in these docs. Each
    # is filed under whichever category its own example's mark belongs
    # to instead -- "Categorical business charts" for annotate_line
    # (Mark.BAR), "Basic marks" for svg_accessibility (its own bar-chart
    # data is incidental -- the feature works with any mark), annotate_
    # area, and annotate_vline_point (both Mark.LINE), "Multivariate"
    # for dual_axis (a layered Mark.AREA + Mark.LINE combo) -- rather
    # than getting a category of its own.
    var cats = List[Category]()
    cats.append(Category(
        "Basic marks", "The core chart types -- one mark, default theme (donut is pie's own ring variant).",
        [
            "scatter", "line", "bar", "area", "pie", "single_axis", "effect_scatter",
            "svg_accessibility", "annotate_area", "annotate_vline_point",
        ],
    ))
    cats.append(Category(
        "Categorical business charts",
        "Chart types built around one categorical dimension: rankings, timelines, progress,"
        " period-over-period comparisons, and process stages.",
        [
            "lollipop", "waterfall", "gantt", "span_chart", "population_pyramid", "bullet",
            "grouped_bar", "stacked_bar", "slope", "funnel", "bump", "streamgraph", "annotate_line",
        ],
    ))
    cats.append(Category(
        "Statistical & financial", "Distributions, binned counts, grid/matrix data, and OHLC price data.",
        ["box", "histogram", "heatmap", "candlestick", "beeswarm", "violin", "ridgeline"],
    ))
    cats.append(Category(
        "Relationships & flows", "Weighted connections between entities, not a value per category.",
        ["chord", "arc_diagram", "graph", "sankey"],
    ))
    cats.append(Category(
        "Radial & polar",
        "Chart types built on a polar (angle + radius) coordinate system instead of a cartesian one.",
        ["nightingale", "polarbar", "radialbar", "polar", "polar_series", "radar", "gauge"],
    ))
    cats.append(Category(
        "Multivariate",
        "Several numeric dimensions compared at once on one shared layout, not a single value per category.",
        ["parallel", "dual_axis"],
    ))
    cats.append(Category(
        "Grid & matrix",
        "Two categorical dimensions laid out as a grid, extending Mark.HEATMAP's own grid-cell idea.",
        ["calendar_heatmap", "corrplot", "punchcard", "marimekko"],
    ))
    cats.append(Category(
        "Hierarchical data",
        "A tree, not a value per category -- one flattened id/parent_id/value row per node,"
        " see Plot.encode_hierarchy().",
        ["sunburst", "tree", "treemap"],
    ))
    return cats^


def _hooks_from_own_docstring() -> List[String]:
    """Examples whose page-level hook should stay sourced from their
    *own* module docstring instead of the quickplot function's
    (`_build_page()`'s usual default) -- an explicit, hand-maintained
    exception list, the same shape `_titles()`/`_categories()` already
    are, not an automated "are these two sentences different enough"
    heuristic (too fragile to trust for an editorial call like this
    one). `slope` is the one entry today: it calls the general-purpose
    `line()`, but its own docstring explains the specific two-point
    data shape that makes it read as a slope chart at all -- line()'s
    own docstring has no reason to know about that."""
    return ["slope"]


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


def _has_svg_save_call(source: String) -> Bool:
    """Whether any `save(...)`/`save_layers(...)`/`save_facets(...)`
    call in `source` writes a path ending `.svg` -- issue #112's
    `save()` family replaced `write_svg(`/`write_accessible_svg(` as
    how every example actually produces its own SVG output, so `_has_
    call(source, "write_svg")` alone no longer detects it (no example
    calls that directly any more). Checked as a plain per-line
    substring test (one of the three call names, and `.svg"`, both
    present on the same line) rather than a real parse, since every
    such call in examples/*.mojo is single-line."""
    for line in source.split("\n"):
        if '.svg"' not in line:
            continue
        if "save(" in line or "save_layers(" in line or "save_facets(" in line:
            return True
    return False


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
        "funnel", "bump", "streamgraph", "beeswarm", "violin", "ridgeline", "nightingale", "polarbar", "radialbar", "polar", "polar_series", "radar", "gauge", "parallel", "span_chart", "calendar_heatmap", "corrplot", "punchcard", "marimekko", "sunburst", "tree", "treemap", "arc_diagram", "graph", "sankey",
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


def _quickplot_call_starts(body: List[String]) -> List[Int]:
    """Every `var <ident> = <quickplot fn>(...` line's own index, in
    source order -- generalizes the old single-match version (there
    used to be only ever one call per example, so it just returned
    that line's index or -1) now that one example can build more than
    one `Plot` on its own docs page (examples/bar.mojo's own
    diverging-bars variant, assigned to `var c_diverging` rather than
    reusing `c`, so both calls' snippets can show up as separate
    sections on the same page -- see `_build_sections()`). Matches
    `var <ident> = ` generically (any identifier), not the literal
    `var c = ` the single-match version checked, since a second call
    on the same page needs its own, different identifier. Written
    either as one line (`var c = scatter(x, y)`, whenever the call is
    short enough) or, once there's enough kwargs to want one per line,
    the multi-line shape (the opening line ends `(`, one argument per
    line, a lone `)` closes it -- see any of examples/bar.mojo/
    scatter.mojo/etc. for either). Either way the call's own function
    name sits right after `var <ident> = ` and before its own first
    `(`, so matching that is enough regardless of which shape follows;
    `_quickplot_call_end()` finds wherever each call itself actually
    closes."""
    var names = _quickplot_names()
    var starts = List[Int]()
    for i in range(len(body)):
        var stripped = body[i].strip()
        if not stripped.startswith("var "):
            continue
        var after_var = String(stripped[byte=4:])  # 4 == len("var ")
        var eq = after_var.find(" = ")
        if eq == -1:
            continue
        var after_eq = String(after_var[byte = eq + 3 :])  # 3 == len(" = ")
        var paren = after_eq.find("(")
        if paren == -1:
            continue
        var name = String(after_eq[byte=0:paren])
        if name in names:
            starts.append(i)
    return starts^


def _var_ident(line: String) -> String:
    """The `<ident>` out of a `var <ident> = ...` line, or a `var
    <ident>: <type> = ...` one (examples/pie.mojo's own `var browsers:
    List[String] = [...]`, stopping at the `:` rather than swallowing
    the type annotation too) -- "" if the line isn't shaped either
    way. Used both for a confirmed quickplot-call line (`_quickplot_
    call_starts()` already found it, so this just re-extracts its own
    identifier) and, in `_build_sections()`, to test whether some
    earlier plain data-setup line is one a later section's own code
    goes on to reference by name."""
    var stripped = line.strip()
    if not stripped.startswith("var "):
        return ""
    var after_var = String(stripped[byte=4:])  # 4 == len("var ")
    var eq = after_var.find(" = ")
    if eq == -1:
        return ""
    var head = String(after_var[byte=0:eq])
    var colon = head.find(":")
    if colon != -1:
        var untyped = String(head[byte=0:colon])
        head = untyped
    return String(head.strip())


def _quickplot_call_end(body: List[String], start: Int) -> Int:
    """`start`'s own line already closes the call (a single-line
    `var c = scatter(x, y)`) if it ends with `)` -- checked before
    scanning further, since a multi-line call's own opening line never
    does (it always ends `(`, per `_quickplot_call_starts`'s own
    docstring). Otherwise, the matching close is the first line below
    `start` that's a lone `)` with nothing else on it."""
    if body[start].strip().endswith(")"):
        return start
    for i in range(start + 1, len(body)):
        if body[i].strip() == ")":
            return i
    return -1


def _quickplot_fn_name(line: String) -> String:
    """The `<fn>` name out of a `var <ident> = <fn>(...` line already
    confirmed by `_quickplot_call_starts()` -- re-extracts it the same
    way that function's own match already did, so `_build_sections()`
    can look up that function's own docstring for its Args section."""
    var stripped = line.strip()
    var after_var = String(stripped[byte=4:])  # 4 == len("var ")
    var eq = after_var.find(" = ")
    var after_eq = String(after_var[byte = eq + 3 :])  # 3 == len(" = ")
    var paren = after_eq.find("(")
    return String(after_eq[byte=0:paren])


def _quickplot_file_for(fn_name: String) raises -> String:
    """Which dataviz_mojo/<file>.mojo defines `fn_name`, per __init__.
    mojo's own `from dataviz_mojo.<file> import ...` re-export block --
    the package's single source of truth for this mapping, not a
    second one invented here. Each `from` block is either one line
    (`from dataviz_mojo.arc import pie`) or, once there's more than a
    couple of names, a parenthesized multi-line shape (`dataviz_mojo.
    plot`'s own block) -- both handled the same way `_quickplot_call_
    end()` already handles a quickplot *call*'s own single-line-vs-
    multi-line shape."""
    var lines = _read_file("dataviz_mojo/__init__.mojo").split("\n")
    var i = 0
    while i < len(lines):
        var stripped = lines[i].strip()
        if not stripped.startswith("from dataviz_mojo."):
            i += 1
            continue
        var after_prefix = String(stripped[byte=18:])  # 18 == len("from dataviz_mojo.")
        var dot = after_prefix.find(" import")
        var file = String(after_prefix[byte=0:dot])
        var block_end = i
        if stripped.endswith("("):
            var j = i + 1
            while j < len(lines) and not (lines[j].strip() == ")"):
                j += 1
            block_end = j
        if _word_in(String("\n").join(lines[i : block_end + 1]), fn_name):
            return file
        i = block_end + 1
    raise Error("gen_example_docs: no dataviz_mojo/__init__.mojo import found defining " + fn_name)


def _quickplot_hook(fn_name: String, file: String) raises -> String:
    """The one-line "what is this chart" hook shown at the top of a
    docs page, pulled from `fn_name`'s own docstring in dataviz_mojo/
    <file>.mojo via the same `_extract_docstring()`/`_first_sentence()`
    already used for an example's *own* module docstring -- reusing
    the quickplot function's docstring here too (instead of a second,
    separately hand-maintained sentence living in examples/<name>.mojo)
    means there's exactly one place describing what a chart type is."""
    var source = _read_file("dataviz_mojo/" + file + ".mojo")
    var def_idx = source.find("\ndef " + fn_name + "(")
    if def_idx == -1:
        raise Error("gen_example_docs: no `def " + fn_name + "(` found in dataviz_mojo/" + file + ".mojo")
    return _first_sentence(_extract_docstring(String(source[byte=def_idx:])))


def _extract_args_lines(fn_name: String, file: String) raises -> List[String]:
    """The `Args:` section's own bullet lines out of `fn_name`'s
    docstring in dataviz_mojo/<file>.mojo, formatted as markdown --
    `[]` if that function has no `Args:` section (every quickplot
    function does, per #122, but this degrades gracefully rather than
    raising for one that doesn't). Every docstring added by #122 shares
    one consistent indent (8 spaces for a bullet's `name: description`
    line, 12 for a continuation -- confirmed across every quickplot
    function's own docstring, not assumed), so that's what this parses
    against rather than a more general (and more fragile) indent-
    detection scheme. Skips the type annotation entirely -- reliably
    parsing each argument's real type back out of the function's own
    multi-line signature (`Theme`'s own giant default-value literal,
    `List[Float64]`, ...) isn't worth it for what the snippet's own
    real usage, shown right above, already makes clear."""
    var lines = _read_file("dataviz_mojo/" + file + ".mojo").split("\n")
    var def_idx = -1
    for i in range(len(lines)):
        if lines[i].startswith("def " + fn_name + "("):
            def_idx = i
            break
    if def_idx == -1:
        raise Error("gen_example_docs: no `def " + fn_name + "(` found in dataviz_mojo/" + file + ".mojo")

    var args_idx = -1
    var end_idx = -1
    for i in range(def_idx, len(lines)):
        var stripped = lines[i].strip()
        if stripped == "Args:":
            args_idx = i
        elif args_idx != -1 and (stripped == "Returns:" or stripped == '"""'):
            end_idx = i
            break
    if args_idx == -1:
        return List[String]()
    if end_idx == -1:
        end_idx = len(lines)

    var result = List[String]()
    for i in range(args_idx + 1, end_idx):
        var raw = lines[i]
        if raw.strip() == "":
            continue
        if raw.startswith("        ") and not raw.startswith("         "):  # exactly 8 spaces -- a new bullet
            var colon = raw.find(": ")
            var arg_name = String(raw[byte=8:colon])
            var desc = String(raw[byte = colon + 2 :])
            result.append("- `" + arg_name + "`: " + desc)
        else:
            result.append("  " + raw.strip())
    return result^


def _accessible_svg_call_index(body: List[String]) -> Int:
    """The line index of the bare `write_accessible_svg(...)` call --
    examples/svg_accessibility.mojo's own anchor, and the one remaining
    exception to this file's "the render/save call is boilerplate to
    cut" rule: that example's *whole point* is this call's own title/
    description arguments, not the `render_svg()`/`save()` line just
    above it -- cutting there the way `_finish_clean_body()` strips
    every other example's I/O calls would throw away the one line the
    page exists to show. -1 if this example doesn't call it at all
    (every hand-built example but that one)."""
    for i in range(len(body)):
        if body[i].strip().startswith("write_accessible_svg("):
            return i
    return -1


def _has_save_call(body: List[String]) -> Bool:
    """Whether this example writes its output via `save()`/`save_
    layers()`/`save_facets()` -- the shape every hand-built example but
    svg_accessibility.mojo now uses (issue #112: one `Plot`/`List[Plot]`,
    one or more plain-I/O `save*()` calls, no separate raster/SVG
    `Plot` chains left to find an anchor to cut *before* -- see
    `_build_sections()`'s docstring for why that changes how this
    file's second shape works)."""
    for i in range(len(body)):
        var stripped = body[i].strip()
        if (
            stripped.startswith("save(")
            or stripped.startswith("save_layers(")
            or stripped.startswith("save_facets(")
        ):
            return True
    return False


struct PageSection(Copyable, Movable):
    """One shown image + code snippet on a docs page. Almost every
    example produces exactly one of these (`heading` empty, since
    there's nothing to distinguish it from); an example whose file
    builds more than one quickplot `Plot` (examples/bar.mojo's own
    diverging-bars variant) produces one per call instead, each with
    its own image and its own `### <heading>` subsection -- see
    `_build_sections()`. `fn_name` is the quickplot function this
    section's snippet calls (`""` for a hand-built-`Plot`/`write_
    accessible_svg` section, which has no single function's Args to
    show) -- `_build_page()` uses it to append that function's own
    `Args:` section (`_extract_args_lines()`) below the snippet."""
    var body: List[String]
    var image: String
    var heading: String
    var fn_name: String

    def __init__(out self, var body: List[String], image: String, heading: String, fn_name: String = ""):
        self.body = body^
        self.image = image
        self.heading = heading
        self.fn_name = fn_name


def _segment_heading(segment: List[String]) -> String:
    """A non-first section's own subheading, pulled from its own
    leading `# ...` comment line if it has one (see examples/bar.mojo's
    `# Diverging variant: ...` line, right above its own `var
    c_diverging = bar(...)` call) -- falls back to "Variant" if it
    doesn't, so a future multi-call example that skips the comment
    still gets a real (if generic) subsection rather than an empty
    one."""
    for l in segment:
        var stripped = l.strip()
        if stripped.startswith("# "):
            return String(stripped[byte=2:])
        if stripped.startswith("#"):
            return String(stripped[byte=1:])
    return "Variant"


def _build_sections(name: String, source: String, writes_svg: Bool) raises -> List[PageSection]:
    """Every section this example's docs page shows, in source order.
    Most examples build their raster output via a one-call convenience
    function (see this file's own module docstring): each `var <ident>
    = <fn>(...)` call found by `_quickplot_call_starts()` becomes its
    own section, its own snippet shown verbatim with nothing stripped
    out of it -- everything since the previous call (or the start of
    `main()`, for the first) kept, everything from its own closing `)`
    onward (write_bmp/png, any separate SvgCanvas/render_svg() block)
    cut. A later call's own section also gets any earlier data-setup
    line (`var <ident> = ...`, not itself a previous quickplot call)
    prepended, but only ones its own code actually goes on to
    reference by name -- examples/pie.mojo's own donut variant reuses
    the exact same `browsers`/`share` its pie call above already
    declared rather than redeclaring them, so its own snippet needs
    that declaration to stand alone; examples/bar.mojo's diverging
    variant never references its own first chart's `categories`/
    `values` at all, so nothing gets pulled in for it. The first
    call's own section reuses this example's plain `out_<name>` image
    (matching every single-call example's existing page); each one
    after it gets its own `out_<name>_<suffix>` image (`<suffix>`
    being its own identifier with a leading `c_` stripped, e.g.
    `c_diverging` -> `diverging`) and its own `### <heading>`
    subsection (see `_segment_heading()`).

    A second, rarer shape (examples/annotate_area.mojo, annotate_line.
    mojo, annotate_vline_point.mojo, and dual_axis.mojo, currently) has
    no quickplot function to call at all -- built by hand via `Plot()`/
    `List[Plot]` and one or more `save()`/`save_layers()`/`save_
    facets()` calls instead (`_has_save_call()`). Unlike the quickplot
    shape above, there's no second call to cut *before* here -- every
    one of these examples now builds exactly one `Plot`/`List[Plot]`
    and writes every format from it, so the whole `main()` body (minus
    the `save*()`/`print()` I/O lines `_finish_clean_body()` already
    strips) *is* the one section. `write_accessible_svg(...)` (svg_
    accessibility.mojo) is a third, narrower shape still needing its
    own anchor-and-cut treatment -- see `_accessible_svg_call_index()`'s
    docstring for why. Raises rather than silently falling back to
    showing the whole file (which used to be this function's own
    fallback, back when a raster-only-no-quickplot example was a real,
    expected shape) -- a future example that fits none of these three
    needs a real decision about how its own page should look, not a
    silently-wrong one.
    """
    var body = _main_body_lines(source)
    var ext = ".svg" if writes_svg else ".png"

    var qp_starts = _quickplot_call_starts(body)
    if len(qp_starts) > 0:
        var sections = List[PageSection]()
        var seg_start = 0
        for idx in range(len(qp_starts)):
            var qp_start = qp_starts[idx]
            var qp_end = _quickplot_call_end(body, qp_start)
            var own_lines = List[String]()
            for i in range(seg_start, qp_end + 1):
                own_lines.append(body[i])

            var raw_seg = List[String]()
            if idx > 0:
                var own_text = String("\n").join(own_lines)
                for i in range(0, seg_start):
                    if i in qp_starts:
                        continue  # a previous call's own start line, not data setup
                    var ident = _var_ident(body[i])
                    if ident and _word_in(own_text, ident):
                        raw_seg.append(body[i])
            for l in own_lines:
                raw_seg.append(l)
            var clean_seg = _finish_clean_body(raw_seg)

            var image: String
            var heading: String
            if idx == 0:
                image = "out_" + name + ext
                heading = ""
            else:
                var ident = _var_ident(body[qp_start])
                var suffix = String(ident[byte=2:]) if ident.startswith("c_") else ident  # 2 == len("c_")
                image = "out_" + name + "_" + suffix + ext
                heading = _segment_heading(clean_seg)

            sections.append(PageSection(clean_seg^, image, heading, _quickplot_fn_name(body[qp_start])))
            seg_start = qp_end + 1
        return sections^

    var accessible_idx = _accessible_svg_call_index(body)
    if accessible_idx != -1:
        # Reuses _quickplot_call_end's own single-line-vs-multi-line
        # closing logic -- write_accessible_svg(...) is a real
        # multi-line call needing it.
        var accessible_end = _quickplot_call_end(body, accessible_idx)
        var clean = List[String]()
        for i in range(0, accessible_end + 1):
            clean.append(body[i])
        var sections = List[PageSection]()
        sections.append(PageSection(_finish_clean_body(clean), "out_" + name + ext, ""))
        return sections^

    if _has_save_call(body):
        # No anchor line to search for here: every hand-built example
        # but svg_accessibility.mojo now builds one Plot/List[Plot] and
        # writes every format through save()/save_layers()/save_
        # facets() calls -- `_finish_clean_body()` drops the raster
        # (.bmp/.png) ones as boilerplate but keeps the .svg one (see
        # its own docstring for why), the one line demonstrating how to
        # actually write the Plot/List[Plot] this snippet just built.
        # There's no second, near-identical Plot chain left to cut
        # *before* the way the old raster-then-SVG-twin shape needed --
        # the whole main() body, cleaned up, *is* the snippet.
        var sections = List[PageSection]()
        sections.append(PageSection(_finish_clean_body(body), "out_" + name + ext, ""))
        return sections^

    raise Error(
        "gen_example_docs: no one-call convenience function call"
        " (`var <ident> = <fn>(...)`), no save()/save_layers()/save_"
        "facets() call, and no bare write_accessible_svg(...) call"
        " found -- every example's own shown snippet is expected to be"
        " built one of these ways"
    )


def _finish_clean_body(clean: List[String]) -> List[String]:
    """The cleanup every extraction path (quickplot call, SVG-path
    cut, in-place raster desupersampling) shares once its own
    mark-specific work is done: drop leftover write_bmp/write_png/
    write_svg/print() I/O lines and every raster save()/save_layers()/
    save_facets() call, drop a now-empty `.theme(Theme())` method call,
    collapse the blank lines that leaves behind, and undo `def main()`'s
    own 4-space indent.

    A save-family call writing `.svg` is the one exception kept rather
    than dropped -- unlike write_bmp/write_png/write_svg (always
    boilerplate here: the interesting call in that shape is `render()`
    itself, already captured before this function ever sees these
    lines), a hand-built example's own save()/save_layers()/save_
    facets() calls are the *only* place its shown snippet demonstrates
    writing the `Plot` it just built at all -- dropping every one of
    them would leave a snippet that builds a chart and never shows how
    to do anything with it. Keeping the `.svg` call specifically (not
    the `.bmp`/`.png` ones, when an example writes more than one)
    matches this docs site's own "SVG is the preferred display format"
    convention (see `_build_page()`'s comment)."""
    var without_io = List[String]()
    for l in clean:
        var stripped = l.strip()
        var is_save_call = (
            stripped.startswith("save(")
            or stripped.startswith("save_layers(")
            or stripped.startswith("save_facets(")
        )
        if (
            stripped.startswith("write_bmp(")
            or stripped.startswith("write_png(")
            or stripped.startswith("write_svg(")
            or stripped.startswith("print(")
            or (is_save_call and ".svg" not in stripped)
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
        "render_layers", "render_layers_svg", "accessible_svg_string", "write_accessible_svg",
        "save", "save_layers", "save_facets",
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

    # SVG is the preferred display format -- a vector image stays crisp
    # at any zoom/pane size a browser puts it in, unlike a fixed-
    # resolution raster snapshot, and every example now writes one via
    # save() (issue #112). This holds even for a quickplot-built
    # example, whose *shown* snippet only constructs the `Plot` (every
    # `save()` call, `.svg` included, is cut from the snippet entirely
    # -- see _build_sections()'s own docstring): the raster/vector
    # backends render the identical chart from the identical data, so
    # the .svg is still an accurate picture of what the shown snippet's
    # quickplot call produces, just via the file's other (unshown)
    # save() call. Falls back to .png only for an example that doesn't
    # write an .svg at all -- none do today, but a future one demoing
    # raster-only output (PNG/BMP specifically) would land here instead
    # of being forced into a vector image it never builds.
    # `write_accessible_svg(` also counts as "writes an .svg" --
    # examples/svg_accessibility.mojo writes only that (an accessible
    # SVG has no raster equivalent at all -- role/aria-label/title/desc
    # are SVG-only concepts, see that function's own docstring), and
    # neither `_has_svg_save_call()` (looks for `save(`) nor a plain
    # substring check for "write_svg(" matches it.
    var writes_svg = _has_svg_save_call(source) or _has_call(source, "write_accessible_svg")

    var sections = _build_sections(name, source, writes_svg)

    # The page-level hook comes from the first section's own quickplot
    # function's docstring when it has one -- falls back to this
    # example's own module docstring for the 5 hand-built-Plot/
    # write_accessible_svg pages, which have no such function to pull
    # from (see `PageSection.fn_name`'s docstring), and for the small,
    # explicit exception list in `_hooks_from_own_docstring()`.
    var hook: String
    if sections[0].fn_name and name not in _hooks_from_own_docstring():
        hook = _quickplot_hook(sections[0].fn_name, _quickplot_file_for(sections[0].fn_name))
    else:
        hook = _first_sentence(_extract_docstring(source))

    var page = List[String]()
    page.append("---")
    page.append("title: " + title)
    page.append("---")
    page.append("")
    page.append(hook)
    page.append("")

    # Every example so far has exactly one section (`sections[0]`,
    # heading always ""), shown the same way this always has been:
    # image, then "## Usage", then its snippet. An example with more
    # than one quickplot call (examples/bar.mojo's own diverging-bars
    # variant) gets a second section instead of a second page -- its
    # own "### <heading>" (see `_segment_heading()`) followed by its
    # own image and snippet, right below the first's. A second section
    # calling the *same* quickplot function (bar.mojo/pie.mojo's own
    # diverging/donut variants both reuse bar()/pie()) shows the same
    # Args section its first call already did -- skipped rather than
    # repeated verbatim.
    var is_first = True
    var last_args_fn = ""
    for section in sections:
        var body_text = String("\n").join(section.body)
        var import_lines = _imports_for(body_text)

        var indented = List[String]()
        for l in section.body:
            indented.append("    " + l if l.strip() else "")

        var snippet = String("\n").join(import_lines)
        if len(import_lines) > 0:
            snippet += "\n\n"
        snippet += "def main() raises:\n" + String("\n").join(indented)

        if is_first:
            page.append("![" + title + "](" + section.image + ")")
            page.append("")
            page.append("## Usage")
            page.append("")
        else:
            page.append("### " + section.heading)
            page.append("")
            page.append("![" + title + " -- " + section.heading + "](" + section.image + ")")
            page.append("")
        page.append("```mojo")
        page.append(snippet)
        page.append("```")
        page.append("")

        if section.fn_name and section.fn_name != last_args_fn:
            var args_lines = _extract_args_lines(section.fn_name, _quickplot_file_for(section.fn_name))
            if len(args_lines) > 0:
                page.append("**Args:**")
                page.append("")
                for l in args_lines:
                    page.append(l)
                page.append("")
            last_args_fn = section.fn_name

        is_first = False

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
