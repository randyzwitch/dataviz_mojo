"""Generates docs/src/examples/*.md and docs/src/cookbook/*.md: Examples
from dataviz/*.mojo's docstrings, Cookbook from
docs/cookbook_recipes/ (self-contained contributed files; see that
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
`docs/cookbook_recipes/`.

A Mojo script rather than Python, using `.strip()`/`.startswith()`/
`.find()`/`in` in place of regexes.
"""

from std.collections import Dict
from std.os import listdir, makedirs

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
    _validate_page,
    _write_file,
)

comptime _OUT_DIR = "docs/src/examples"
comptime _COOKBOOK_OUT_DIR = "docs/src/cookbook"
comptime _RECIPES_DIR = "docs/cookbook_recipes"


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
    d["boxenplot"] = "Letter-Value Plot"
    d["candlestick"] = "Candlestick"
    d["bullet"] = "Bullet"
    d["gantt"] = "Gantt"
    d["population_pyramid"] = "Population Pyramid"
    d["heatmap"] = "Heatmap"
    d["chord"] = "Chord"
    d["single_axis"] = "Single Axis"
    d["effect_scatter"] = "Effect Scatter"
    d["eventplot"] = "Event Plot"
    d["funnel"] = "Funnel"
    d["bump"] = "Bump"
    d["streamgraph"] = "Streamgraph"
    d["stacked_area"] = "Stacked Area"
    d["beeswarm"] = "Beeswarm"
    d["violin"] = "Violin"
    d["ridgeline"] = "Ridgeline"
    d["nightingale"] = "Nightingale Rose"
    d["polarbar"] = "Polar Bar"
    d["radialbar"] = "Radial Bar"
    d["polar"] = "Polar"
    d["radar"] = "Radar"
    d["gauge"] = "Gauge"
    d["parallel"] = "Parallel Coordinates"
    d["span_chart"] = "Span Chart"
    d["calendar_heatmap"] = "Calendar Heatmap"
    d["corrplot"] = "Correlation Plot"
    d["punchcard"] = "Punchcard"
    d["barbs"] = "Wind Barbs"
    d["quiver"] = "Vector Arrows"
    d["streamplot"] = "Streamlines"
    d["contour"] = "Contour"
    d["contourf"] = "Filled Contour"
    d["imshow"] = "Image"
    d["pcolormesh"] = "Quadrilateral Mesh"
    d["hist2d"] = "2D Histogram"
    d["hexbin"] = "Hexagonal Bins"
    d["tricontour"] = "Scattered Contour"
    d["tricontourf"] = "Scattered Contour (Filled)"
    d["triplot"] = "Triangular Mesh"
    d["tripcolor"] = "Triangular Mesh (Colored)"
    d["ecdf"] = "ECDF"
    d["residplot"] = "Residual Plot"
    d["barplot"] = "Estimate Bars"
    d["lineplot"] = "Estimate Line"
    d["pairplot"] = "Pair Plot"
    d["jointplot"] = "Joint Plot"
    d["clustermap"] = "Clustered Heatmap"
    d["dendrogram"] = "Dendrogram"
    d["scatter3d"] = "3D Scatter"
    d["plot3d"] = "3D Line"
    d["surface3d"] = "3D Surface"
    d["wire3d"] = "3D Wireframe"
    d["trisurf3d"] = "3D Triangulated Surface"
    d["bar3d"] = "3D Bars"
    d["voxels"] = "Voxels"
    d["stem3d"] = "3D Stems"
    d["quiver3d"] = "3D Arrows"
    d["fill_between3d"] = "3D Ribbon"
    d["pointplot"] = "Estimate Points"
    d["kdeplot"] = "Density Curve"
    d["rugplot"] = "Rug"
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
    var slug: String
    """The folder under `docs/src/examples/` this section's pages live
    in, and so their URL segment; a Hextra sidebar group. Empty for
    the Cookbook's task categories, whose pages stay flat."""

    def __init__(
        out self,
        title: String,
        blurb: String,
        var names: List[String],
        slug: String = "",
    ):
        self.title = title
        self.blurb = blurb
        self.names = names^
        self.slug = slug


def _categories() -> List[Category]:
    # Feature demos live in the Cookbook; this list contains chart types.
    # Each is a folder under docs/src/examples/ and a sidebar group, in
    # this order (#671); a function's other Example blocks show as
    # sections of its own page, not as pages of their own.
    var cats = List[Category]()
    cats.append(
        Category(
            "Basic",
            (
                "The core chart types -- one mark, default theme. Line's page"
                " also shows its step and time-axis forms, area's its stepped"
                " form, and pie's its donut ring."
            ),
            [
                "scatter",
                "line",
                "area",
                "bar",
                "pie",
                "single_axis",
                "effect_scatter",
            ],
            slug="basic",
        )
    )
    cats.append(
        Category(
            "Categorical",
            (
                "Chart types built around one categorical dimension:"
                " rankings, timelines, progress, period-over-period"
                " comparisons, process stages, and OHLC price data per"
                " period."
            ),
            [
                "lollipop",
                "grouped_bar",
                "stacked_bar",
                "waterfall",
                "bullet",
                "funnel",
                "slope",
                "bump",
                "population_pyramid",
                "gantt",
                "span_chart",
                "streamgraph",
                "stacked_area",
                "candlestick",
            ],
            slug="categorical",
        )
    )
    cats.append(
        Category(
            "Distributions",
            (
                "The shape of one or two numeric variables: binned counts,"
                " summaries of spread, density estimates, and event times."
                " Histogram's page also shows shared bins, automatic bins, a"
                " density curve, and the horizontal form."
            ),
            [
                "histogram",
                "box",
                "boxenplot",
                "violin",
                "beeswarm",
                "ridgeline",
                "kdeplot",
                "rugplot",
                "ecdf",
                "eventplot",
                "hist2d",
                "hexbin",
            ],
            slug="distributions",
        )
    )
    cats.append(
        Category(
            "Estimates & compositions",
            (
                "Charts that summarize or combine other charts: a bar, line,"
                " or point per group with an aggregate and its error, the"
                " residuals of a fit, and figures assembled from several"
                " panels."
            ),
            [
                "barplot",
                "lineplot",
                "pointplot",
                "residplot",
                "jointplot",
                "pairplot",
                "clustermap",
            ],
            slug="estimates",
        )
    )
    cats.append(
        Category(
            "Grid & matrix",
            (
                "A value per cell of a grid. Mostly two categorical"
                " dimensions; imshow and pcolormesh are the continuous-axis"
                " pair, for an array rather than a table."
            ),
            [
                "heatmap",
                "imshow",
                "pcolormesh",
                "calendar_heatmap",
                "corrplot",
                "punchcard",
                "marimekko",
            ],
            slug="grid",
        )
    )
    cats.append(
        Category(
            "Relationships & flows",
            "Weighted connections between entities, not a value per category.",
            [
                "chord",
                "arc_diagram",
                "graph",
                "sankey",
            ],
            slug="relationships",
        )
    )
    cats.append(
        Category(
            "Hierarchical",
            (
                "A tree, not a value per category -- one flattened"
                " id/parent_id/value row per node (see"
                " Plot.encode_hierarchy()), or a clustering's merge tree."
            ),
            [
                "sunburst",
                "tree",
                "treemap",
                "dendrogram",
            ],
            slug="hierarchical",
        )
    )
    cats.append(
        Category(
            "Radial & polar",
            (
                "Chart types built on a polar (angle + radius) coordinate"
                " system instead of a cartesian one."
            ),
            [
                "nightingale",
                "polarbar",
                "radialbar",
                "polar",
                "radar",
                "gauge",
            ],
            slug="radial",
        )
    )
    cats.append(
        Category(
            "Fields & multivariate",
            (
                "Several numeric dimensions on one shared layout, or a value"
                " defined over a plane: vector fields, contours, and"
                " triangulated meshes."
            ),
            [
                "parallel",
                "barbs",
                "quiver",
                "streamplot",
                "contour",
                "contourf",
                "tricontour",
                "tricontourf",
                "triplot",
                "tripcolor",
            ],
            slug="fields",
        )
    )
    cats.append(
        Category(
            "Three dimensions",
            (
                "A third axis projected onto the page. Orthographic, so"
                " parallel stays parallel and a tick spacing means one thing"
                " across the whole picture -- but a single view still"
                " collapses three dimensions onto two, and two points that"
                " look adjacent may be far apart along the view direction."
                " Where the question is about two variables, the 2D charts"
                " above answer it better."
            ),
            [
                "scatter3d",
                "plot3d",
                "surface3d",
                "wire3d",
                "trisurf3d",
                "bar3d",
                "voxels",
                "stem3d",
                "quiver3d",
                "fill_between3d",
            ],
            slug="three_d",
        )
    )
    return cats^


def _cookbook() -> Category:
    """The Cookbook page's docstring-sourced list, empty now that every
    recipe lives in `docs/cookbook_recipes/` (see its README.md).
    Kept as a working mechanism so a future recipe that documents one
    function's API has a place to go, and so `main()`'s placement
    assertions still cover it. A `Category` like the rest, since `main()`
    builds an `_index.md` from it the same way.
    """
    return Category(
        "Cookbook",
        (
            "One-off techniques for customizing a plot you already have -- not"
            " chart types of their own, so each is filed by what it does rather"
            " than what it looks like."
        ),
        [],
    )


def _cookbook_categories() -> List[Category]:
    """Cookbook recipes grouped by the task a reader wants to perform."""
    var cats = List[Category]()
    cats.append(
        Category(
            "Annotations and labels",
            "Call out values, ranges, trends, and individual observations.",
            [
                "annotate_line",
                "annotate_vline",
                "annotate_area",
                "annotate_band",
                "annotate_point",
                "annotate_arrow",
                "annotation_colors",
                "data_labels",
                "point_labels",
                "math_labels",
            ],
        )
    )
    cats.append(
        Category(
            "Axes, scales, and orientation",
            "Control domains, axis furniture, ordering, and chart direction.",
            [
                "log_scale_x",
                "log_scale_y",
                "indexed_100",
                "percent_stacked_bar",
                "step_interpolation",
                "sorted_bar",
                "horizontal_bar",
                "horizontal_grouped_bar",
                "horizontal_stacked_bar",
                "horizontal_lollipop",
                "horizontal_box",
                "horizontal_violin",
                "horizontal_beeswarm",
                "despine",
                "full_axis_box",
                "axes_through_zero",
                "bar_zero_baseline",
                "compact_axis_chrome",
                "custom_margins",
                "margin_buffer",
                "data_label_margin",
            ],
        )
    )
    cats.append(
        Category(
            "Color and accessibility",
            "Encode values with color and keep charts legible across contexts.",
            [
                "color_categorical",
                "color_continuous",
                "color_map",
                "diverging_color_scale",
                "diverging_bar",
                "custom_diverging_colors",
                "centered_diverging_scale",
                "shared_color_domain",
                "shared_semantic_mapping",
                "shape_by_category",
                "high_contrast_theme",
                "print_safe_theme",
                "dark_theme",
                "minimal_theme",
                "svg_accessibility",
            ],
        )
    )
    cats.append(
        Category(
            "Layout, facets, and layers",
            "Combine plots, coordinate scales, and explain layered series.",
            [
                "combo_chart",
                "bar_line_combo",
                "dual_axis",
                "layer_legend",
                "isolines_over_a_field",
                "facets",
                "shared_facet_scale",
            ],
        )
    )
    cats.append(
        Category(
            "Statistics and uncertainty",
            (
                "Show estimates, uncertainty, distributions, and dense"
                " relationships."
            ),
            [
                "best_fit_line",
                "error_bars",
                "error_bars_asymmetric",
                "error_bars_on_line",
                "error_bar_cap_width",
                "bubble_size",
                "bubble_size_range",
                "kde_comparison",
                "narrow_violins",
                "violin_bandwidth",
                "violin_scale_by_count",
                "ridgeline_overlap",
                "dense_corrplot",
            ],
        )
    )
    cats.append(
        Category(
            "Export and presentation",
            "Tune chart appearance and produce output for its destination.",
            [
                "export_formats",
                "high_dpi_export",
                "typography",
                "subtitle_axis_title_styling",
                "bold_points",
                "line_smoothing",
                "legend_sizing",
                "continuous_legend_size",
                "bullet_styling",
                "compact_gauge",
                "effect_scatter_halo",
                "radar_fill_alpha",
                "radialbar_styling",
                "sankey_node_width",
                "waterfall_colors",
            ],
        )
    )
    cats.append(
        Category(
            "External and custom data",
            "Use numeric types, Python arrays, and custom Mojo containers.",
            [
                "numeric_types",
                "numpy_pandas_data",
                "array_like_data",
                "categorical_array_like",
            ],
        )
    )
    return cats^


def _cookbook_api_links(category: String) -> String:
    """Relevant reference links for a Cookbook task category."""
    if category == "Annotations and labels":
        return "[Plot annotations](../../dataviz/plot/Plot/)"
    if category == "Axes, scales, and orientation":
        return (
            "[Plot](../../dataviz/plot/Plot/) · "
            "[Theme](../../dataviz/core/theme/Theme/)"
        )
    if category == "Color and accessibility":
        return (
            "[Theme](../../dataviz/core/theme/Theme/) · "
            "[Colors](../../dataviz/core/colors/)"
        )
    if category == "Layout, facets, and layers":
        return "[Rendering and composition](../../dataviz/plot/)"
    if category == "Statistics and uncertainty":
        return "[Plot encodings](../../dataviz/plot/Plot/)"
    if category == "Export and presentation":
        return (
            "[Theme](../../dataviz/core/theme/Theme/) · "
            "[OutputFormat](../../dataviz/core/output_format/OutputFormat/)"
        )
    return "[Data shapes](../../data-shapes/)"


def _use_when(hook: String) -> String:
    """Turn an imperative recipe summary into a reader-focused sentence."""
    if hook.byte_length() == 0:
        return hook
    return (
        "**Use this when:** You need to "
        + String(hook[byte=0:1]).lower()
        + String(hook[byte=1:])
    )


def _folded_into(name: String) -> List[String]:
    """The old page names whose content is now a section of `name`'s
    page -- another Example block of the same function (#671) -- so
    their URLs can redirect there."""
    var out = List[String]()
    if name == "line":
        out.append("step")
        out.append("line_time")
    elif name == "area":
        out.append("step_area")
    elif name == "histogram":
        out.append("histogram_shared")
        out.append("histogram_auto")
        out.append("histogram_density")
        out.append("histogram_horizontal")
    return out^


def _example_category(
    name: String, categories: List[Category]
) raises -> Category:
    """Return the single chart-family category containing `name`."""
    for cat in categories:
        if name in cat.names:
            return cat.copy()
    raise Error("Example has no chart-family category: " + name)


def _example_api_link(page: ExamplePage, root: String) -> String:
    """Markdown link from an Example page to its generated API entry;
    `root` is the relative path from the page up to the site root."""
    if page.is_method:
        return (
            "["
            + page.fn_name
            + "]("
            + root
            + "dataviz/"
            + page.file
            + "/Plot/#"
            + page.fn_name
            + ")"
        )
    return (
        "["
        + page.fn_name
        + "]("
        + root
        + "dataviz/"
        + page.file
        + "/"
        + page.fn_name
        + "/)"
    )


def _build_page(
    name: String,
    title: String,
    page: ExamplePage,
    category: Category,
    titles: Dict[String, String],
    image_prefix: String = "",
    root: String = "../../",
    weight: Int = 0,
    aliases: List[String] = List[String](),
) raises -> String:
    """One page's Markdown. `image_prefix` reaches the SVGs from the
    page's content folder (Hextra resolves images against it), `root`
    reaches the site root from the page's URL (plain links resolve
    against that), `weight` orders the page in its sidebar group, and
    `aliases` are old URLs Hugo redirects to this page (#671).
    """
    var hook_overrides = _hook_overrides()
    var hook: String
    if name in hook_overrides:
        hook = hook_overrides[name]
    else:
        hook = _quickplot_hook(page.fn_name, page.file, page.is_method)

    var args_lines = _extract_args_lines(
        page.fn_name, page.file, page.is_method
    )
    var all_blocks = _extract_example_blocks(
        page.fn_name, page.file, page.is_method
    )
    var blocks = List[_ExampleBlock]()
    if page.block:
        for b in all_blocks:
            if b.heading == page.block:
                blocks.append(b.copy())
        if len(blocks) == 0:
            raise Error(
                "gen_example_docs: page '"
                + name
                + "' wants Example ("
                + page.block
                + "): but "
                + page.fn_name
                + " has no block with that heading"
            )
    else:
        blocks = all_blocks^

    var out = List[String]()
    out.append("---")
    out.append("title: " + title)
    if weight > 0:
        out.append("weight: " + String(weight))
    if len(aliases) > 0:
        out.append("aliases:")
        for old_url in aliases:
            out.append("  - " + old_url)
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
        out.append(
            "See [Data shapes]("
            + root
            + "data-shapes/) for shared input conventions."
        )
        out.append("")
        out.append("**Args:**")
        out.append("")
        for l in args_lines:
            out.append(l)
        out.append("")

    var position = -1
    for i in range(len(category.names)):
        if category.names[i] == name:
            position = i
            break
    if position == -1:
        raise Error("Example missing from its chart-family category: " + name)

    out.append("## Related")
    out.append("")
    var related = List[String]()
    if position > 0:
        var previous = category.names[position - 1]
        related.append("[" + titles[previous] + "](../" + previous + "/)")
    if position + 1 < len(category.names):
        var following = category.names[position + 1]
        related.append("[" + titles[following] + "](../" + following + "/)")
    if len(related) > 0:
        out.append("**Related charts:** " + String(" · ").join(related))
        out.append("")
    out.append("**Relevant API:** " + _example_api_link(page, root))
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
    var first_line = (
        String(content[byte=0:first_line_end]) if first_line_end
        != -1 else content
    )
    var prefix = "# title: "
    if first_line.startswith(prefix):
        return String(String(first_line[byte = prefix.byte_length() :]).strip())
    return ""


def _build_contributed_page(
    name: String,
    title: String,
    content: String,
    category: Category,
    recipe_titles: Dict[String, String],
) raises -> String:
    """A `docs/cookbook_recipes/*.mojo` file turned into the same
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
        raise Error(
            "gen_example_docs: cookbook recipe has no leading docstring (see"
            " cookbook_recipes/README.md)"
        )
    var doc_content_start = doc_start + 3
    var doc_end = content.find('"""', doc_content_start)
    if doc_end == -1:
        raise Error(
            "gen_example_docs: cookbook recipe's leading docstring is never"
            " closed"
        )
    var hook = _first_sentence(_extract_docstring(content))
    var code = String(content[byte = doc_end + 3 :]).strip()

    var out = List[String]()
    out.append("---")
    out.append("title: " + title)
    out.append("---")
    out.append("")
    out.append(_use_when(hook))
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

    var position = -1
    for i in range(len(category.names)):
        if category.names[i] == name:
            position = i
            break
    if position == -1:
        raise Error("Cookbook recipe has no task category: " + name)

    out.append("## Related")
    out.append("")
    var related = List[String]()
    if position > 0:
        var previous = category.names[position - 1]
        related.append(
            "[" + recipe_titles[previous] + "](../" + previous + "/)"
        )
    if position + 1 < len(category.names):
        var following = category.names[position + 1]
        related.append(
            "[" + recipe_titles[following] + "](../" + following + "/)"
        )
    if len(related) > 0:
        out.append("**Related recipes:** " + String(" · ").join(related))
        out.append("")
    out.append("**Relevant API:** " + _cookbook_api_links(category.title))
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
            raise Error(
                "Example placed in both a category and the cookbook: " + n
            )
        categorized.append(n)

    for n in all_names:
        if n not in categorized:
            raise Error(
                "Example not placed in any category or the cookbook: " + n
            )
    for n in categorized:
        if n not in all_names:
            raise Error(
                "Category/cookbook references a non-existent example: " + n
            )
    for n in all_names:
        if n not in titles:
            raise Error("Example has no title: " + n)

    for cat in categories:
        makedirs(_OUT_DIR + "/" + cat.slug, exist_ok=True)
    for p in pages:
        _validate_page(p)
        var category = _example_category(p.name, categories)
        if p.name in cookbook.names:
            # Cookbook pages need two parent segments to reach examples SVGs.
            var page_md = _build_page(
                p.name,
                titles[p.name],
                p,
                category,
                titles,
                image_prefix="../../examples/",
            )
            _write_file(_COOKBOOK_OUT_DIR + "/" + p.name + ".md", page_md)
        else:
            var position = 0
            for i in range(len(category.names)):
                if category.names[i] == p.name:
                    position = i + 1
            var aliases = List[String]()
            aliases.append("/examples/" + p.name + "/")
            for old in _folded_into(p.name):
                aliases.append("/examples/" + old + "/")
            var page_md = _build_page(
                p.name,
                titles[p.name],
                p,
                category,
                titles,
                image_prefix="../../",
                root="../../../",
                weight=position,
                aliases=aliases,
            )
            _write_file(
                _OUT_DIR + "/" + category.slug + "/" + p.name + ".md", page_md
            )

    # Discover recipes on each run and reject output-name collisions.
    var recipe_entries = listdir(_RECIPES_DIR)
    sort(recipe_entries)
    var recipe_names = List[String]()
    var recipe_titles = Dict[String, String]()
    var recipe_contents = Dict[String, String]()
    for e in recipe_entries:
        if not e.endswith(".mojo"):
            continue
        var stem = String(e[byte = 0 : e.byte_length() - 5])
        if stem in all_names:
            raise Error(
                "gen_example_docs: cookbook_recipes/"
                + e
                + " collides with an existing Examples/Cookbook page name '"
                + stem
                + "' -- rename the file"
            )
        var content = _read_file(_RECIPES_DIR + "/" + e)
        var override = _title_override(content)
        var title = override if override else _title_case_filename(stem)
        recipe_names.append(stem)
        recipe_titles[stem] = title
        recipe_contents[stem] = content

    var cookbook_categories = _cookbook_categories()
    var placed_recipes = List[String]()
    for cat in cookbook_categories:
        for n in cat.names:
            if n in placed_recipes:
                raise Error("Cookbook recipe placed in two categories: " + n)
            if n not in recipe_names:
                raise Error("Cookbook category references unknown recipe: " + n)
            placed_recipes.append(n)
    for n in recipe_names:
        if n not in placed_recipes:
            raise Error("Cookbook recipe has no task category: " + n)

    for cat in cookbook_categories:
        for n in cat.names:
            var page_md = _build_contributed_page(
                n, recipe_titles[n], recipe_contents[n], cat, recipe_titles
            )
            _write_file(_COOKBOOK_OUT_DIR + "/" + n + ".md", page_md)

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
    idx.append(
        "Not sure how to arrange an input? See [Data shapes](../data-shapes/) "
        "for columns, nested lists, matrices, edges, and hierarchies."
    )
    idx.append("")
    idx.append(
        "For behavior shared across chart types, see the [Guides](../guides/). "
        "The [Glossary](../glossary/) defines chart terminology."
    )
    idx.append("")
    for ci in range(len(categories)):
        ref cat = categories[ci]
        idx.append("## " + cat.title)
        idx.append("")
        idx.append(cat.blurb)
        idx.append("")
        for n in cat.names:
            idx.append("- [" + titles[n] + "](" + cat.slug + "/" + n + "/)")
        idx.append("")
        # The section's own index: what the sidebar group opens to.
        var sec = List[String]()
        sec.append("---")
        sec.append("title: " + cat.title)
        sec.append("weight: " + String(10 * (ci + 1)))
        sec.append("---")
        sec.append("")
        sec.append(cat.blurb)
        sec.append("")
        for n in cat.names:
            sec.append("- [" + titles[n] + "](" + n + "/)")
        _write_file(
            _OUT_DIR + "/" + cat.slug + "/_index.md", String("\n").join(sec)
        )
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
        "Task-focused techniques for customizing, composing, and exporting "
        "charts. See [Examples](../examples/) to choose a chart type first, "
        "or [Guides](../guides/) for concepts that span several APIs."
    )
    cookbook_idx.append("")
    for n in cookbook.names:
        cookbook_idx.append("- [" + titles[n] + "](" + n + "/)")
    for cat in cookbook_categories:
        cookbook_idx.append("## " + cat.title)
        cookbook_idx.append("")
        cookbook_idx.append(cat.blurb)
        cookbook_idx.append("")
        for n in cat.names:
            cookbook_idx.append("- [" + recipe_titles[n] + "](" + n + "/)")
        cookbook_idx.append("")
    _write_file(
        _COOKBOOK_OUT_DIR + "/_index.md", String("\n").join(cookbook_idx)
    )

    print(
        "Wrote",
        len(all_names),
        "example pages,",
        len(recipe_names),
        "contributed cookbook recipes, + _index.md to",
        _OUT_DIR,
        "and",
        _COOKBOOK_OUT_DIR,
    )
