"""Generates docs/src/examples/*.md and docs/src/cookbook/*.md: Examples
from dataviz/*.mojo's docstrings, Cookbook from
docs/src/cookbook_recipes/ (self-contained contributed files; see that
directory's README.md). Run as part of `pixi run docs` (pixi.toml),
before `mojo doc`/`modo build`.

The per-function docstring parsing (`_pages()`, `_quickplot_hook()`,
`_extract_args_lines()`, `_extract_example_blocks()`) lives in
`_example_docstrings.mojo`, shared with
`extract_docstring_examples.mojo`, which compiles and runs the same
`Example:` blocks this file only reads.

This file holds the hand-curated title/category metadata
(`_titles()`/`_categories()`/`_cookbook()`), the page builders
(`_build_page()` for a docstring-sourced page,
`_build_contributed_page()` for a recipe file), and `main()`, which
assembles both into the Examples and Cookbook pages plus their
`_index.md`.

Adding an Example: add the function's `Example:` section, then add it
to `_example_docstrings.mojo`'s `_pages()`, to `_titles()`, and to
exactly one category in `_categories()` (or `_cookbook()`'s list, not
both); `main()`'s assertions catch a missing or doubly placed entry.
Adding a Cookbook recipe needs none of that: drop a file in
`docs/src/cookbook_recipes/`.

A Mojo script rather than Python, using `.strip()`/`.startswith()`/
`.find()`/`in` in place of regexes.
"""

from std.collections import Dict
from std.os import listdir

from _example_docstrings import (
    ExamplePage,
    _ExampleBlock,
    _extract_args_lines,
    _extract_docstring,
    _extract_example_blocks,
    _first_sentence,
    _hook_overrides,
    _output_svg_name,
    _pages,
    _quickplot_hook,
    _read_file,
    _write_file,
)

comptime _OUT_DIR = "docs/src/examples"
comptime _COOKBOOK_OUT_DIR = "docs/src/cookbook"
comptime _RECIPES_DIR = "docs/src/cookbook_recipes"


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
    # Cookbook titles come from each recipe's filename or its `# title:`
    # override (see cookbook_recipes/README.md), not from here.
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
    # Every example here is a distinct chart type; feature demos (facets,
    # layers, annotations, ...) live in the Cookbook instead.
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
    """The Cookbook page's docstring-sourced list, empty now that every
    recipe lives in `docs/src/cookbook_recipes/` (see its README.md).
    Kept as a working mechanism so a future recipe that documents one
    function's API has a place to go, and so `main()`'s placement
    assertions still cover it. A `Category` like the rest, since `main()`
    builds an `_index.md` from it the same way.
    """
    return Category(
        "Cookbook",
        "One-off techniques for customizing a plot you already have -- not chart types of their own,"
        " so each is filed by what it does rather than what it looks like.",
        [],
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


def _title_case_filename(stem: String) -> String:
    """`bold_points` -> `"Bold Points"`: a Cookbook recipe's title when it
    has no `# title:` override. Each underscore-separated word gets its
    first letter uppercased and the rest lowercased; no acronym table.
    """
    var words = stem.split("_")
    var out = List[String]()
    for w in words:
        if w.byte_length() == 0:
            continue
        var first = String(w[byte=0:1]).upper()
        var rest = String(w[byte=1:]).lower()
        out.append(first + rest)
    return String(" ").join(out)


def _title_override(content: String) -> String:
    """A recipe file's optional `# title: <text>` first line, or `""` when
    absent (the caller then falls back to `_title_case_filename()`).
    Covers titles the plain rule can't produce: acronyms ("SVG
    Accessibility"), reordered words, hyphens, lowercase prepositions. A
    leading `#` comment before the module docstring is valid Mojo.
    """
    var first_line_end = content.find("\n")
    var first_line = String(content[byte=0:first_line_end]) if first_line_end != -1 else content
    var prefix = "# title: "
    if first_line.startswith(prefix):
        return String(String(first_line[byte = prefix.byte_length() :]).strip())
    return ""


def _build_contributed_page(title: String, content: String) raises -> String:
    """A `docs/src/cookbook_recipes/*.mojo` file turned into the same
    markdown shape `_build_page()` produces (title/hook/image/Usage),
    minus an `Args:` section and named-variant support: one recipe file
    is one page with one code block.

    `content` must start with a `\"\"\"...\"\"\"` module docstring; its
    first sentence (`_first_sentence()`) becomes the hook, and everything
    after the closing `\"\"\"` is shown verbatim as the Usage code block,
    since a recipe is already a complete runnable program.
    """
    var doc_start = content.find('"""')
    if doc_start == -1:
        raise Error("gen_example_docs: cookbook recipe has no leading docstring (see cookbook_recipes/README.md)")
    var doc_content_start = doc_start + 3
    var doc_end = content.find('"""', doc_content_start)
    if doc_end == -1:
        raise Error("gen_example_docs: cookbook recipe's leading docstring is never closed")
    var hook = _first_sentence(_extract_docstring(content))
    var code = String(content[byte = doc_end + 3 :]).strip()

    var out = List[String]()
    out.append("---")
    out.append("title: " + title)
    out.append("---")
    out.append("")
    out.append(hook)
    out.append("")

    var code_lines = List[String]()
    for l in code.split("\n"):
        code_lines.append(String(l))
    var image = "../../examples/" + _output_svg_name(code_lines)
    out.append("![" + title + "](" + image + ")")
    out.append("")
    out.append("## Usage")
    out.append("")
    out.append("```mojo")
    for l in code_lines:
        out.append(l)
    out.append("```")
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
            # Cookbook pages live under docs/src/cookbook/, but their rendered
            # .svg files land under docs/src/examples/out_*.svg (the path is
            # hardcoded in each Example's save() call), so the image reference
            # needs a relative prefix. Two levels because a cookbook page's URL is
            # /cookbook/<name>/, two segments below the site root.
            var page_md = _build_page(p.name, titles[p.name], p, image_prefix="../../examples/")
            _write_file(_COOKBOOK_OUT_DIR + "/" + p.name + ".md", page_md)
        else:
            var page_md = _build_page(p.name, titles[p.name], p)
            _write_file(_OUT_DIR + "/" + p.name + ".md", page_md)

    # Community Cookbook recipes -- every *.mojo file in _RECIPES_DIR,
    # discovered fresh each run (std.os.listdir), not a hand-maintained
    # list the way _pages() is: the whole point of this directory is
    # that a contributor doesn't touch any *.mojo file under scripts/
    # at all. Raises the same "don't silently overwrite" way `main()`'s
    # own docstring-page assertions already do, extended to cover a
    # recipe's name colliding with an existing Examples/Cookbook page
    # -- both land in a flat name -> file namespace across the whole
    # site, so a collision either way would otherwise silently clobber
    # one page with another.
    var recipe_entries = listdir(_RECIPES_DIR)
    sort(recipe_entries)
    var recipe_names = List[String]()
    var recipe_titles = Dict[String, String]()
    for e in recipe_entries:
        if not e.endswith(".mojo"):
            continue
        var stem = String(e[byte = 0 : e.byte_length() - 5])
        if stem in all_names:
            raise Error(
                "gen_example_docs: cookbook_recipes/" + e + " collides with an existing Examples/Cookbook"
                " page name '" + stem + "' -- rename the file"
            )
        var content = _read_file(_RECIPES_DIR + "/" + e)
        var override = _title_override(content)
        var title = override if override else _title_case_filename(stem)
        var page_md = _build_contributed_page(title, content)
        _write_file(_COOKBOOK_OUT_DIR + "/" + stem + ".md", page_md)
        recipe_names.append(stem)
        recipe_titles[stem] = title

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
        "`Example:` docstring section in this repo's `dataviz/` "
        "source -- each page shows the actual grammar-of-graphics "
        "pattern next to its actual rendered output, so you can see "
        "exactly what it takes to produce that chart."
    )
    idx.append("")
    idx.append(
        "Most reach for a single one-call convenience function -- "
        "`bar(categories, values)`, `scatter(x, y)`, and so on, one per "
        "mark, imported straight from `dataviz` -- built on top of "
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

    # Weight 300 sits between Examples (200) and modo's API reference
    # (400), placing Cookbook after Examples in the sidebar/top nav.
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
        "these apply to, or `docs/src/cookbook_recipes/`'s own README.md "
        "in the repo to contribute one yourself -- a Cookbook recipe "
        "doesn't need to be tied to one function the way an Example does."
    )
    cookbook_idx.append("")
    for n in cookbook.names:
        cookbook_idx.append("- [" + titles[n] + "](" + n + "/)")
    for n in recipe_names:
        cookbook_idx.append("- [" + recipe_titles[n] + "](" + n + "/)")
    cookbook_idx.append("")
    _write_file(_COOKBOOK_OUT_DIR + "/_index.md", String("\n").join(cookbook_idx))

    print(
        "Wrote", len(all_names), "example pages,", len(recipe_names),
        "contributed cookbook recipes, + _index.md to", _OUT_DIR, "and", _COOKBOOK_OUT_DIR,
    )
