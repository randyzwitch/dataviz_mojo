from canvas_mojo.geometry import _round_to_int
from canvas_mojo.text.render import TextAlign
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _rendered,
)
from dataviz_mojo.theme import Theme


def _render_marimekko[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.MARIMEKKO` plot (a mosaic/Marimekko chart):
    `encode_marimekko()`'s own `categories` (one column each) and
    `subcategories` (one stacked segment each, `values[sub][cat]` --
    rows are subcategories, columns are categories, matching ECharts.
    jl's own matrix convention), where *both* axes carry real
    proportions -- unlike `Mark.STACKED_BAR`'s own equal-width columns
    with a stacked absolute magnitude, a Marimekko's own column
    *widths* are each category's own share of the grand total, and
    each column's own segment *heights* are that column's own
    subcategory composition (always summing to the column's full
    height, a 0-100% stack -- see below), the two-dimensional
    generalization "every bar chart's width already means something,
    not just its height" the real Marimekko/mosaic-plot convention is
    named for.

    No shared `OrdinalScale` x-axis (every other categorical mark
    here has equal-width bands) -- column x-positions/widths are
    computed directly from each category's own share of `grand_total`
    (the sum of every value in the matrix). Segment heights are each
    value's own share of *its own column's total* (not `grand_total`)
    -- a column with a small share of the grand total still fills its
    own full height with its own subcategory breakdown, the same
    "always reads as a complete 0-100% stack" property `_render_
    stacked_bar`'s own docstring would give if it worked in
    percentages instead of raw magnitudes.

    Every value must be non-negative, and `grand_total` must be
    positive -- the same "raise, don't silently misrepresent" stance
    `Mark.ARC`'s own validation already takes for its own share-of-
    a-whole data. No numeric y-axis (a real, deliberate v1
    simplification, the same kind `Mark.POLAR`'s own ungridded numeric
    readout already is) -- category names label each column along the
    bottom, legend keyed by `subcategories` (the same "series name ->
    color" legend `Mark.STACKED_BAR` already draws).
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
    if len(plot._marimekko.categories) == 0 or len(plot._marimekko.subcategories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

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

    # Every rect boundary below -- both column edges (x) and segment
    # edges (y) -- comes from rounding a *cumulative* continuous
    # position, never an independently-rounded width/height: two
    # adjacent columns/segments share the exact same boundary value in
    # continuous space, so rounding each one where it's used (once as
    # a "this shape's end," once as the next shape's "start") always
    # lands on the same pixel -- no hairline gap or overlap from
    # rounding twice independently. The same "round the boundaries,
    # not the width" pattern `Mark.STACKED_BAR`'s own `_render_
    # stacked_bar` already uses (there via `_axis_pixel` on each
    # segment's own running total).
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
) raises -> Canvas:
    """A Marimekko/mosaic chart -- `Mark.MARIMEKKO`, column widths
    proportional to each category's own share of the grand total,
    stacked segment heights showing each column's own subcategory
    composition. `values[i][j]` is `subcategories[i]`'s own value for
    `categories[j]` (rows are subcategories, columns are categories,
    matching ECharts.jl's own `marimekko()` matrix convention). See
    `_render_marimekko`'s own docstring for the full reasoning."""
    var plot = Plot().mark_marimekko().encode_marimekko(
        categories=categories, subcategories=subcategories, values=values
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
