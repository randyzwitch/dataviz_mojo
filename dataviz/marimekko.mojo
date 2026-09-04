from canvas.geometry import _round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _finished,
    _require_non_empty,
)
from dataviz.theme import Theme


struct _MarimekkoData(Movable):
    """Categories (columns), subcategories (stacked rows), and a value per
    (subcategory, category) pair, for `Mark.MARIMEKKO`. See
    `encode_marimekko()`. Stored on `Plot._marimekko`.
    """

    var categories: List[String]
    var subcategories: List[String]
    var values: List[List[Float64]]

    def __init__(out self):
        self.categories = List[String]()
        self.subcategories = List[String]()
        self.values = List[List[Float64]]()



def _render_marimekko[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.MARIMEKKO` plot (a mosaic chart): `encode_marimekko()`'s
    `categories` (one column each) and `subcategories` (one stacked
    segment each; `values[sub][cat]`, rows are subcategories and columns
    are categories, matching ECharts.jl's matrix convention). Column
    widths are each category's share of the grand total; segment heights
    are each value's share of its own column's total, so every column is
    a full-height 0-100% stack.

    No `OrdinalScale` x-axis: column positions and widths come directly
    from each category's share of `grand_total`. No numeric y-axis;
    category names label each column along the bottom, and the legend is
    keyed by `subcategories`.

    Every value must be non-negative, and `grand_total` must be positive.
    """
    if len(plot._marimekko.values) != len(plot._marimekko.subcategories):
        raise Error(
            "Plot.encode_marimekko(): values must have one row per subcategory"
            " (expected "
            + String(len(plot._marimekko.subcategories))
            + " rows, got "
            + String(len(plot._marimekko.values))
            + ")"
        )
    for row in plot._marimekko.values:
        if len(row) != len(plot._marimekko.categories):
            raise Error(
                "Plot.encode_marimekko(): every row in values must have one"
                " value per category (expected "
                + String(len(plot._marimekko.categories))
                + ", got "
                + String(len(row))
                + ")"
            )

    var theme = plot._theme
    _require_non_empty(
        len(plot._marimekko.categories), "Plot.encode_marimekko()"
    )
    _require_non_empty(
        len(plot._marimekko.subcategories), "Plot.encode_marimekko()"
    )
    for row in plot._marimekko.values:
        for v in row:
            if v < 0.0:
                raise Error("Plot: Mark.MARIMEKKO values must be non-negative (got " + String(v) + ")")

    var n_cats = len(plot._marimekko.categories)
    var n_subs = len(plot._marimekko.subcategories)
    var col_totals = List[Float64]()
    var grand_total = 0.0
    for j in range(n_cats):
        var total = 0.0
        for i in range(n_subs):
            total += plot._marimekko.values[i][j]
        col_totals.append(total)
        grand_total += total
    if grand_total <= 0.0:
        raise Error(
            "Plot: Mark.MARIMEKKO requires at least one positive value"
            " (grand total was "
            + String(grand_total)
            + ")"
        )

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = (
        _dynamic_legend_width(plot._marimekko.subcategories, sc.legend_swatch_size, sc) if show_legend else 0
    )

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var text_requests = List[_TextRequest]()
    var palette = default_categorical_palette()
    var plot_width = Float64(plot_x1 - plot_x0)
    var plot_height = Float64(plot_y1 - plot_y0)

    # Every rect boundary (column edges and segment edges) is the rounded
    # *cumulative* position, never an independently rounded width/height,
    # so adjacent shapes share the exact same pixel boundary with no
    # hairline gap or overlap. Same pattern as `_render_stacked_bar`'s
    # `_axis_pixel` on each running total.
    var x_cum = 0.0
    for j in range(n_cats):
        var col_x0 = _round_to_int(Float64(plot_x0) + x_cum)
        x_cum += plot_width * (col_totals[j] / grand_total)
        var col_x1 = _round_to_int(Float64(plot_x0) + x_cum)

        if col_totals[j] > 0.0:
            var y_cum = 0.0
            for i in range(n_subs):
                var seg_bottom = _round_to_int(Float64(plot_y1) - y_cum)
                y_cum += plot_height * (plot._marimekko.values[i][j] / col_totals[j])
                var seg_top = _round_to_int(Float64(plot_y1) - y_cum)
                target.fill_rect(
                    col_x0, seg_top, col_x1 - col_x0, seg_bottom - seg_top, palette[i % len(palette)]
                )

        text_requests.append(
            _TextRequest(
                (col_x0 + col_x1) // 2,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                plot._marimekko.categories[j],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    if show_legend:
        _draw_legend(
            target, text_requests, plot._marimekko.subcategories, palette, plot_x1 + sc.margin_right, plot_y0, theme
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def marimekko(
    categories: List[String],
    subcategories: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A Marimekko/mosaic chart.

    `Mark.MARIMEKKO`: column widths proportional to each category's share
    of the grand total, stacked segment heights showing each column's
    subcategory composition. `values[i][j]` is `subcategories[i]`'s value
    for `categories[j]` (rows are subcategories, columns are categories,
    matching ECharts.jl's `marimekko()`). See `_render_marimekko`.

    Args:
        categories: One column per entry, its width proportional to
            its share of the grand total.
        subcategories: One stacked segment per entry, used as the
            legend key.
        values: `values[i][j]` is `subcategories[i]`'s value for
            `categories[j]` (rows are subcategories, columns are
            categories).
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import marimekko
        from dataviz.plot import save

        def main() raises:
            var regions: List[String] = ["Northeast", "Midwest", "South", "West"]
            var sources: List[String] = ["Coal", "Gas", "Renewables"]
            var generation: List[List[Int]] = [
                [5, 20, 15, 3],
                [30, 35, 50, 20],
                [10, 15, 10, 27],
            ]

            var c = marimekko(regions, sources, generation)
            save(c, "docs/src/examples/out_marimekko.svg")
        ```
    """
    var plot = Plot().mark_marimekko().encode_marimekko(
        categories=categories, subcategories=subcategories, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def marimekko[
    dtype: DType
](
    categories: List[String],
    subcategories: List[String],
    values: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`marimekko()` generalized over numeric element type for `values`, via
    `_materialize_nested_scalar_list` (array_like.mojo); see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return marimekko(
        categories, subcategories, _materialize_nested_scalar_list(values), theme=theme, width=width,
        height=height, title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
