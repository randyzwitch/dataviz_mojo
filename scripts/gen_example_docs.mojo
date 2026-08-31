"""Generates docs/src/examples/*.md and docs/src/cookbook/*.md straight
from dataviz_mojo/*.mojo's own docstrings -- run as part of `pixi run
docs` (see pixi.toml), before `mojo doc`/`modo build`, so a new
`Example:` docstring section automatically gets a docs page without
anyone hand-writing one.

The actual per-function docstring parsing (`_pages()`'s master list,
`_quickplot_hook()`, `_extract_args_lines()`, `_extract_example_
blocks()`) lives in `_example_docstrings.mojo`, shared with
`extract_docstring_examples.mojo` (the `pixi run example` companion
that compiles and runs every one of the same `Example:` blocks this
file only reads) -- see that module's own docstring for the full
picture of how a page's content maps back to one function's docstring.

This file itself only does two things: `_titles()`/`_categories()`/
`_cookbook()` below, the hand-curated title/navigation-grouping
metadata every docs page needs beyond what any docstring could
reasonably say about itself, and `_build_page()`/`main()`, which
assemble that metadata plus `_example_docstrings.mojo`'s extracted
content into the final markdown -- two top-level pages' worth
(Examples' own many categories, Cookbook's one flat list), not just
one, see `_cookbook()`'s own docstring for why a whole separate page
rather than a category on Examples.

Adding a new example: add its function's own `Example:` section, then
add it to `_example_docstrings.mojo`'s `_pages()`, to `_titles()`
below, and to exactly one category in `_categories()` below OR to
`_cookbook()`'s own list (not both) -- `main()`'s own assertions catch
a missing/misplaced entry either way (a function placed nowhere, in
two places at once, or a category/cookbook entry referencing a name
that doesn't exist) rather than silently skipping it or crashing deep
in string formatting.

A Mojo script, not Python -- this repo's own tooling stays in the
language it's showcasing, string-matching primitives (`.strip()`,
`.startswith()`, `.find()`, `in`) doing the job Python's `re` module
did in an earlier version of this file, without needing Mojo to have
its own regex module (it doesn't, as of this writing).
"""

from std.collections import Dict

from _example_docstrings import (
    ExamplePage,
    _ExampleBlock,
    _extract_args_lines,
    _extract_example_blocks,
    _hook_overrides,
    _output_svg_name,
    _pages,
    _quickplot_hook,
    _write_file,
)

comptime _OUT_DIR = "docs/src/examples"
comptime _COOKBOOK_OUT_DIR = "docs/src/cookbook"


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
    d["annotate_vline"] = "Vertical Reference Line"
    d["annotate_point"] = "Point Marker"
    d["facets"] = "Facets"
    d["log_scale_y"] = "Log Scale (Y-Axis)"
    d["log_scale_x"] = "Log Scale (X-Axis)"
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
    # size encoding, line/area smoothing) mixed in among them; those
    # are real dataviz_mojo capabilities, just not chart types of their
    # own. annotate_line, svg_accessibility, annotate_area, dual_axis,
    # annotate_vline, and annotate_point used to be the exceptions,
    # filed under whichever category their own example's mark happened
    # to belong to (a chart-type category being the only kind that
    # existed yet) -- see `_cookbook()` below for where they live now,
    # and why a whole separate top-level page instead of a category on
    # this one.
    var cats = List[Category]()
    cats.append(Category(
        "Basic marks", "The core chart types -- one mark, default theme (donut is pie's own ring variant).",
        ["scatter", "line", "bar", "area", "pie", "single_axis", "effect_scatter"],
    ))
    cats.append(Category(
        "Categorical business charts",
        "Chart types built around one categorical dimension: rankings, timelines, progress,"
        " period-over-period comparisons, and process stages.",
        [
            "lollipop", "waterfall", "gantt", "span_chart", "population_pyramid", "bullet",
            "grouped_bar", "stacked_bar", "slope", "funnel", "bump", "streamgraph",
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
        ["parallel"],
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


def _cookbook() -> Category:
    """The Cookbook page's own single flat list -- one-off techniques
    for customizing a plot you already have (a reference line/band/
    point marker, a second y-axis, accessible SVG output, a grid of
    several independent plots), not chart types in their own right.
    Used to be a category on the Examples
    page itself, tacked onto whichever chart-type category each
    one's own example happened to fit best -- read as clutter once
    the gallery grew (a scatter/bar/etc. reader expects every entry in
    a chart-type category to be a distinct chart shape, not "how do I
    add a reference line to one of these"), and still didn't read as
    its own *kind* of content the way Examples/API reference/Quickstart
    each do. A full top-level page instead, alongside those three, not
    just its own category on this one -- same `docs/site/hugo.yaml`
    top-nav/left-sidebar treatment as Examples, see `main()` below for
    the `_index.md` it writes.

    A `Category` like the rest of `_categories()`'s list, not a
    distinct type, since `main()` builds an `_index.md` from one
    exactly the same way either page needs -- one category with every
    name, unlike Examples' many.
    """
    return Category(
        "Cookbook",
        "One-off techniques for customizing a plot you already have -- not chart types of their own,"
        " so each is filed by what it does rather than what it looks like.",
        [
            "annotate_line", "annotate_area", "annotate_vline", "annotate_point", "dual_axis",
            "svg_accessibility", "facets", "log_scale_y", "log_scale_x",
        ],
    )


def _build_page(name: String, title: String, page: ExamplePage, image_prefix: String = "") raises -> String:
    var hook_overrides = _hook_overrides()
    var hook: String
    if name in hook_overrides:
        hook = hook_overrides[name]
    else:
        hook = _quickplot_hook(page.fn_name, page.file, page.is_method)

    var args_lines = _extract_args_lines(page.fn_name, page.file, page.is_method)
    var all_blocks = _extract_example_blocks(page.fn_name, page.file, page.is_method)
    var blocks = List[_ExampleBlock]()
    if page.block:
        for b in all_blocks:
            if b.heading == page.block:
                blocks.append(b.copy())
        if len(blocks) == 0:
            raise Error(
                "gen_example_docs: page '" + name + "' wants Example (" + page.block + "): but "
                + page.fn_name + " has no block with that heading"
            )
    else:
        blocks = all_blocks^

    var out = List[String]()
    out.append("---")
    out.append("title: " + title)
    out.append("---")
    out.append("")
    out.append(hook)
    out.append("")

    var is_first = True
    for block in blocks:
        var image = image_prefix + _output_svg_name(block.lines)
        if is_first:
            out.append("![" + title + "](" + image + ")")
            out.append("")
            out.append("## Usage")
            out.append("")
        else:
            var heading = block.heading if block.heading else "Variant"
            out.append("### " + heading)
            out.append("")
            out.append("![" + title + " -- " + heading + "](" + image + ")")
            out.append("")
        out.append("```mojo")
        for l in block.lines:
            out.append(l)
        out.append("```")
        out.append("")
        is_first = False

    if len(args_lines) > 0:
        out.append("**Args:**")
        out.append("")
        for l in args_lines:
            out.append(l)
        out.append("")

    return String("\n").join(out)


def main() raises:
    var titles = _titles()
    var categories = _categories()
    var pages = _pages()

    var all_names = List[String]()
    for p in pages:
        all_names.append(p.name)
    sort(all_names)

    var cookbook = _cookbook()

    var categorized = List[String]()
    for cat in categories:
        for n in cat.names:
            if n in categorized:
                raise Error("Example placed in more than one category: " + n)
            categorized.append(n)
    for n in cookbook.names:
        if n in categorized:
            raise Error("Example placed in both a category and the cookbook: " + n)
        categorized.append(n)

    for n in all_names:
        if n not in categorized:
            raise Error("Example not placed in any category or the cookbook: " + n)
    for n in categorized:
        if n not in all_names:
            raise Error("Category/cookbook references a non-existent example: " + n)
    for n in all_names:
        if n not in titles:
            raise Error("Example has no title: " + n)

    for p in pages:
        if p.name in cookbook.names:
            # Cookbook pages live in their own top-level docs/src/
            # cookbook/ directory (own top-nav/sidebar entry, same
            # treatment as Examples -- see the _index.md written
            # below), but their rendered .svg files still land under
            # docs/src/examples/out_*.svg: that path comes straight
            # from each Example: docstring's own hardcoded save() call
            # in dataviz_mojo/*.mojo (extract_docstring_examples.mojo
            # extracts and runs it verbatim, see pixi.toml's `example`
            # task), unrelated to which docs/src/ directory this
            # script writes the *page* into -- moving the six pages
            # doesn't move those files, so the image reference needs a
            # relative prefix back to them. Two levels, not one: a
            # cookbook page's own published URL is /cookbook/<name>/,
            # two path segments below the site root, vs. quickstart.md
            # (one segment, /quickstart/, correctly just "../examples/"
            # for that page's own images) -- one ".." only pops back to
            # /cookbook/, landing on the non-existent /cookbook/
            # examples/... instead of /examples/... (caught by hand:
            # the wrong path still 404s quietly, an <img> with a dead
            # src doesn't fail the build).
            var page_md = _build_page(p.name, titles[p.name], p, image_prefix="../../examples/")
            _write_file(_COOKBOOK_OUT_DIR + "/" + p.name + ".md", page_md)
        else:
            var page_md = _build_page(p.name, titles[p.name], p)
            _write_file(_OUT_DIR + "/" + p.name + ".md", page_md)

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
        "Every example below comes straight from its chart function's own "
        "`Example:` docstring section in this repo's `dataviz_mojo/` "
        "source -- each page shows the actual grammar-of-graphics "
        "pattern next to its actual rendered output, so you can see "
        "exactly what it takes to produce that chart."
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

    # Weight 300 -- between Examples (200) and modo's own dataviz_mojo/
    # _index.md (400, pinned to title "API Reference" post-build, see
    # pixi.toml's own docs-build task) -- puts Cookbook's left-sidebar/
    # top-nav entry (docs/site/hugo.yaml) right after Examples, ahead of
    # the API reference, the same weight-drives-sidebar-order mechanism
    # Quickstart/Examples/API reference already use (see pixi.toml's
    # own comment next to docs-build for the fuller picture).
    var cookbook_idx = List[String]()
    cookbook_idx.append("---")
    cookbook_idx.append("title: Cookbook")
    cookbook_idx.append("type: docs")
    cookbook_idx.append("weight: 300")
    cookbook_idx.append("cascade:")
    cookbook_idx.append("  type: docs")
    cookbook_idx.append("---")
    cookbook_idx.append("")
    cookbook_idx.append(
        "Techniques for customizing a plot you already have -- a reference "
        "line/band/point marker, a second y-axis, accessible SVG output, a "
        "grid of independent plots -- rather than a distinct chart type of "
        "its own. See [Examples](../examples/) for the chart-type gallery "
        "these apply to."
    )
    cookbook_idx.append("")
    for n in cookbook.names:
        cookbook_idx.append("- [" + titles[n] + "](" + n + "/)")
    cookbook_idx.append("")
    _write_file(_COOKBOOK_OUT_DIR + "/_index.md", String("\n").join(cookbook_idx))

    print("Wrote", len(all_names), "example pages + _index.md to", _OUT_DIR, "and", _COOKBOOK_OUT_DIR)
