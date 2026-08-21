from canvas_mojo.geometry import _round_to_int
from canvas_mojo.text.render import TextAlign
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import ColorScale
from dataviz_mojo.heatmap import _draw_grid_axis_frame
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
    _empty_result,
    _rendered,
)
from dataviz_mojo.scale import _format_fixed
from dataviz_mojo.theme import Theme

# A bubble's own max radius, as a fraction of its cell's own smaller
# dimension -- a correlation of exactly +-1.0 fills this much of the
# cell, everything weaker scales down from there. Fixed, not a Theme
# field, the same "no concrete need for a knob yet" reasoning every
# other fixed layout constant here follows.
comptime _CORRPLOT_BUBBLE_FRACTION = 0.42


def _render_corrplot[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.CORRPLOT` plot: `encode_corrplot()`'s own square
    correlation `matrix` over `variables`, one bubble per surviving
    cell on `Mark.HEATMAP`'s own `_draw_grid_axis_frame` -- the same
    variable list on *both* axes (a correlation matrix is always
    square), unlike `HEATMAP`'s own two independent category domains.
    Bubble radius scales linearly with `abs(matrix[row][col])`
    (`_CORRPLOT_BUBBLE_FRACTION` of the cell's own smaller dimension at
    exactly +-1.0), bubble color through the same continuous
    `ColorScale` vocabulary `HEATMAP` uses, but spanning the fixed
    `[-1.0, 1.0]` correlation domain (not the data's own [min, max] --
    a correlation matrix's own domain is always exactly that range by
    definition, so there's nothing to derive from the data the way
    `HEATMAP`'s own value domain has to be).

    `Plot.mark_corrplot(layout=...)` keeps only the cells a given
    `layout` calls for: `"full"` (every cell, the default), `"lower"`
    (row index >= col index, into `variables`' own given order), or
    `"upper"` (row index <= col index) -- the same lower/upper-
    triangle convention ECharts.jl's own `corrplot()` uses, since a
    correlation matrix is symmetric and showing both triangles is
    often pure redundancy. `diag=False` additionally drops every
    row-equals-col cell (always 1.0 for a real correlation matrix,
    rarely informative). `labels=True` (the default) draws each
    surviving cell's own value, formatted to two decimal places,
    centered inside its own bubble.

    Every value must be in `[-1.0, 1.0]` -- checked at render() time,
    the same "raise, don't silently misrepresent" stance every other
    value-validated mark here takes; a real correlation coefficient is
    mathematically bounded to that range by definition, so anything
    outside it means the caller handed this something that isn't
    actually a correlation matrix.
    """
    if len(plot._corrplot_matrix) != len(plot._corrplot_variables):
        raise Error(
            "Plot.encode_corrplot(): matrix must have one row per variable"
            " (expected "
            + String(len(plot._corrplot_variables))
            + " rows, got "
            + String(len(plot._corrplot_matrix))
            + ")"
        )
    for row in plot._corrplot_matrix:
        if len(row) != len(plot._corrplot_variables):
            raise Error(
                "Plot.encode_corrplot(): matrix must be square, one value per"
                " variable in every row (expected "
                + String(len(plot._corrplot_variables))
                + ", got "
                + String(len(row))
                + ")"
            )

    var theme = plot._theme
    if len(plot._corrplot_variables) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for row in plot._corrplot_matrix:
        for v in row:
            if v < -1.0 or v > 1.0:
                raise Error(
                    "Plot: Mark.CORRPLOT values must be in [-1.0, 1.0] (got " + String(v) + ")"
                )

    var sc = _Scaled(theme)
    var color_scale = ColorScale(-1.0, 1.0)
    color_scale.add_stop(0.0, theme.color_scale_low)
    color_scale.add_stop(1.0, theme.color_scale_high)

    var legend_reserve = 0
    if theme.show_legend:
        var legend_labels = List[String]()
        legend_labels.append(_format_fixed(color_scale.domain_max, 1))
        legend_labels.append(_format_fixed(color_scale.domain_min, 1))
        legend_reserve = _dynamic_legend_width(legend_labels, sc.continuous_legend_bar_width, sc)

    var frame = _draw_grid_axis_frame(
        target, plot._corrplot_variables, plot._corrplot_variables, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var cell_width = frame.x_scale.bandwidth()
    var cell_height = frame.y_scale.bandwidth()
    var max_radius = min(cell_width, cell_height) / 2.0 * _CORRPLOT_BUBBLE_FRACTION
    var n = len(plot._corrplot_variables)

    for row in range(n):
        for col in range(n):
            if row == col and not plot._corrplot_diag:
                continue
            if plot._corrplot_layout == "lower" and col > row:
                continue
            if plot._corrplot_layout == "upper" and col < row:
                continue
            var value = plot._corrplot_matrix[row][col]
            var cx = _round_to_int(frame.x_scale.center(col))
            var cy = _round_to_int(frame.y_scale.center(row))
            var radius = _round_to_int(max_radius * abs(value))
            target.fill_circle_aa(cx, cy, radius, color_scale.color_at(value))
            if plot._corrplot_labels:
                frame.text_requests.append(
                    _TextRequest(
                        cx, cy + Int(sc.font_size * 0.35), _format_fixed(value, 2), theme.text_color,
                        sc.font_size, TextAlign.CENTER, theme.font_family,
                    )
                )

    if theme.show_legend:
        _ = _draw_continuous_color_legend(
            target,
            frame.text_requests,
            color_scale,
            _round_to_int(frame.x_scale.range_max) + sc.margin_right,
            frame.py0,
            theme,
        )

    return frame.result()


def corrplot(
    variables: List[String],
    matrix: List[List[Float64]],
    layout: String = "full",
    diag: Bool = True,
    labels: Bool = True,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A correlation plot -- `Mark.CORRPLOT`, one bubble per cell of a
    square correlation `matrix` over `variables`, sized and colored by
    `abs`/sign of each pairwise correlation. `layout` ("full" (the
    default), "lower", or "upper") and `diag` (default True) match
    ECharts.jl's own `corrplot()` keyword names. See `_render_corrplot`'s
    own docstring for the full reasoning."""
    var plot = Plot().mark_corrplot(layout=layout, diag=diag, labels=labels).encode_corrplot(
        variables=variables, matrix=matrix
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
