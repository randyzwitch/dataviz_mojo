"""Generates docs/src/examples/*.md and docs/src/cookbook/*.md --
Examples straight from dataviz_mojo/*.mojo's own docstrings, Cookbook
from docs/src/cookbook_recipes/ (community-contributed, self-contained
files -- see that directory's own README.md for the contributor-facing
side of this). Every Cookbook page used to be docstring-sourced too,
the same mechanism Examples still uses -- all migrated away (see
`_cookbook()`'s own docstring for why, and why that path is kept
working rather than deleted). Run as part of `pixi run docs` (see
pixi.toml), before `mojo doc`/`modo build`.

The actual per-function docstring parsing (`_pages()`'s master list,
`_quickplot_hook()`, `_extract_args_lines()`, `_extract_example_
blocks()`) lives in `_example_docstrings.mojo`, shared with
`extract_docstring_examples.mojo` (the `pixi run example` companion
that compiles and runs every one of the same `Example:` blocks this
file only reads) -- see that module's own docstring for the full
picture of how a page's content maps back to one function's docstring.

This file itself does three things: `_titles()`/`_categories()`/
`_cookbook()` below, the hand-curated title/navigation-grouping
metadata every *docstring-sourced* page needs beyond what any
docstring could reasonably say about itself; `_build_page()`/
`_build_contributed_page()`, which turn a docstring-sourced page or a
`docs/src/cookbook_recipes/` file (respectively) into markdown; and
`main()`, which discovers/assembles both kinds into the final Examples
and Cookbook pages -- see `_cookbook()`'s own docstring for why
Cookbook is a whole separate top-level page rather than a category on
Examples, and `_build_contributed_page()`'s own docstring for why a
Cookbook recipe doesn't need a docstring host the way an Example does.

Adding a new *Example*: add its function's own `Example:` section,
then add it to `_example_docstrings.mojo`'s `_pages()`, to `_titles()`
below, and to exactly one category in `_categories()` below OR to
`_cookbook()`'s own list (not both) -- `main()`'s own assertions catch
a missing/misplaced entry either way (a function placed nowhere, in
two places at once, or a category/cookbook entry referencing a name
that doesn't exist) rather than silently skipping it or crashing deep
in string formatting. Adding a new *Cookbook recipe* needs none of
that -- drop a file in `docs/src/cookbook_recipes/`; see its own
README.md.

A Mojo script, not Python -- this repo's own tooling stays in the
language it's showcasing, string-matching primitives (`.strip()`,
`.startswith()`, `.find()`, `in`) doing the job Python's `re` module
did in an earlier version of this file, without needing Mojo to have
its own regex module (it doesn't, as of this writing).
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
    # Every Cookbook title used to be listed here too -- migrated to
    # docs/src/cookbook_recipes/ (title comes from each recipe's own
    # filename or its optional `# title:` override, see that
    # directory's README.md), so there's nothing left to add here.
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
    """The Cookbook page's own docstring-sourced list -- always empty
    now (see `main()`'s own comment next to where this is called):
    every one-off technique for customizing a plot you already have
    (a reference line/band/point marker, a second y-axis, accessible
    SVG output, a grid of several independent plots, color/size
    encoding, theme overrides, layered-combo recipes, ...) migrated to
    `docs/src/cookbook_recipes/` -- see that directory's own README.md
    for why a Cookbook recipe doesn't need a docstring host the way an
    Example does, and `main()`'s own recipe-discovery block for how
    those pages actually get built now.

    Kept as a real, working mechanism rather than deleted outright --
    `main()`'s own assertions still catch a docstring-sourced page
    placed nowhere or in both a category and here, and a future recipe
    that genuinely is about documenting one function's own API (the
    way an Example is) has a place to go without re-inventing this.
    Still a `Category` like the rest of `_categories()`'s list, not a
    distinct type, since `main()` builds an `_index.md` from one
    exactly the same way either page needs.
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
    """`bold_points` -> `"Bold Points"` -- a Cookbook recipe's title,
    for the one kind of page that has no docstring-sourced `_titles()`
    entry to look up (see `_build_contributed_page()`'s own
    docstring). Every underscore-separated word gets its first letter
    uppercased, everything else lowercased -- a deliberately plain
    rule (no acronym table, no manual override map) so a contributor
    never needs to touch this file at all; a recipe wanting different
    capitalization (an acronym like "SVG") can still get it by simply
    naming the file that way (`svg_something.mojo` won't title-case
    "SVG" correctly on its own, but a contributor who cares can spell
    a word in a way this function happens to preserve, or a maintainer
    can rename the file post-hoc -- not worth a config knob for the
    rare case)."""
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
    """A recipe file's own optional `# title: <text>` first line --
    `""` (no override) if the file's first line doesn't start with
    that exact prefix, in which case the caller falls back to
    `_title_case_filename()`. Exists because that plain per-word-
    capitalize rule can't produce every real title on its own -- an
    acronym ("SVG Accessibility"), a deliberately different word order
    ("Smoothed Line" from `line_smoothing.mojo`), a hyphenated
    compound ("High-DPI Export"), or a lowercase preposition ("Color
    by Category") -- without forcing a contributor to pick a filename
    that happens to title-case correctly instead of the name they
    actually want. A plain leading comment line, not a second
    docstring or a structured header, so it costs nothing when unused
    (the common case, see `bold_points.mojo`) and doesn't complicate
    the docstring/code split `_build_contributed_page()` does
    (a `#` comment before the module docstring is ordinary, valid
    Mojo, confirmed directly rather than assumed)."""
    var first_line_end = content.find("\n")
    var first_line = String(content[byte=0:first_line_end]) if first_line_end != -1 else content
    var prefix = "# title: "
    if first_line.startswith(prefix):
        return String(String(first_line[byte = prefix.byte_length() :]).strip())
    return ""


def _build_contributed_page(title: String, content: String) raises -> String:
    """A `docs/src/cookbook_recipes/*.mojo` file's own content, turned
    into the same markdown shape `_build_page()` produces for a
    docstring-sourced page -- title/hook/image/Usage, minus an `Args:`
    section (there's no host function's own parameter docs to pull one
    from; a recipe is a technique, not one function's own API
    surface, see that directory's README.md for why this path exists
    at all) and minus any named-variant support (`_extract_example_
    blocks()`'s `Example (<heading>):` mechanism -- one recipe file is
    always exactly one page, one code block).

    `content` must have a leading `\"\"\"...\"\"\"` module docstring
    (`_extract_docstring()`, the exact same primitive `_quickplot_
    hook()` already uses on a function's docstring, just pointed at a
    whole file's leading one instead) -- its first sentence
    (`_first_sentence()`) becomes the hook line, everything else in
    the docstring is for the contributor's own benefit and never
    reaches the page. Everything *after* that docstring's closing
    `\"\"\"` is shown verbatim as the page's own Usage code block --
    already a complete, real, runnable program by the README's own
    contract, so there's no fenced-block extraction to do the way
    `_extract_example_blocks()` needs for a block embedded inside a
    larger function's docstring.
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
