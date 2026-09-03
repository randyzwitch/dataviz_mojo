from canvas.geometry import _round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.color_scale import ColorScale
from canvas.text.font_cache import FontCache
from dataviz.heatmap import _draw_grid_axis_frame
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
    _empty_result,
    _finished,
)
from dataviz.scale import _format_fixed
from dataviz.theme import Theme


struct _CorrplotData(Movable):
    """A square correlation matrix over a shared variable list, plus display
    options, for `Mark.CORRPLOT`. See `encode_corrplot()`. Stored on
    `Plot._corrplot`.
    """

    var variables: List[String]
    var matrix: List[List[Float64]]
    var layout: String
    var diag: Bool
    var labels: Bool

    def __init__(out self):
        self.variables = List[String]()
        self.matrix = List[List[Float64]]()
        self.layout = ""
        self.diag = False
        self.labels = False


def _render_corrplot[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.CORRPLOT` plot: `encode_corrplot()`'s square
    correlation `matrix` over `variables`, one bubble per surviving cell
    on `Mark.HEATMAP`'s `_draw_grid_axis_frame` with the same variable
    list on both axes. Bubble radius scales linearly with
    `abs(matrix[row][col])` (`plot._mark_style.corrplot_bubble_fraction`
    of the cell's smaller dimension at +-1.0); bubble color comes from a
    `ColorScale` over the fixed `[-1.0, 1.0]` domain rather than the
    data's range.

    `Plot.mark_corrplot(layout=...)` keeps only the cells `layout` calls
    for: `"full"` (every cell, the default), `"lower"` (row index >= col
    index), or `"upper"` (row index <= col index). `diag=False` drops
    every row-equals-col cell. `labels=True` (the default) draws each
    surviving cell's value to two decimal places, centered in its bubble.

    Every value must be in `[-1.0, 1.0]`, checked at render() time.
    """
    if len(plot._corrplot.matrix) != len(plot._corrplot.variables):
        raise Error(
            "Plot.encode_corrplot(): matrix must have one row per variable"
            " (expected "
            + String(len(plot._corrplot.variables))
            + " rows, got "
            + String(len(plot._corrplot.matrix))
            + ")"
        )
    for row in plot._corrplot.matrix:
        if len(row) != len(plot._corrplot.variables):
            raise Error(
                "Plot.encode_corrplot(): matrix must be square, one value per"
                " variable in every row (expected "
                + String(len(plot._corrplot.variables))
                + ", got "
                + String(len(row))
                + ")"
            )

    var theme = plot._theme
    if len(plot._corrplot.variables) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for row in plot._corrplot.matrix:
        for v in row:
            if v < -1.0 or v > 1.0:
                raise Error(
                    "Plot: Mark.CORRPLOT values must be in [-1.0, 1.0] (got " + String(v) + ")"
                )

    var sc = _Scaled(theme)
    var color_scale = ColorScale.from_theme(theme, -1.0, 1.0)

    # One FontCache for both measurements -- the legend's labels here,
    # then the axis category labels inside _draw_grid_axis_frame.
    var measure_cache = FontCache()

    var legend_reserve = 0
    if theme.show_legend:
        var legend_labels = List[String]()
        legend_labels.append(_format_fixed(color_scale.domain_max, 1))
        legend_labels.append(_format_fixed(color_scale.domain_min, 1))
        legend_reserve = _dynamic_legend_width(
            legend_labels, sc.continuous_legend_bar_width, sc, cache=measure_cache
        )

    var frame = _draw_grid_axis_frame(
        target, plot._corrplot.variables, plot._corrplot.variables, theme, ox0, oy0,
        ox1 - legend_reserve, oy1, cache=measure_cache
    )

    var cell_width = frame.x_scale.bandwidth()
    var cell_height = frame.y_scale.bandwidth()
    var max_radius = min(cell_width, cell_height) / 2.0 * plot._mark_style.corrplot_bubble_fraction
    var n = len(plot._corrplot.variables)

    for row in range(n):
        for col in range(n):
            if row == col and not plot._corrplot.diag:
                continue
            if plot._corrplot.layout == "lower" and col > row:
                continue
            if plot._corrplot.layout == "upper" and col < row:
                continue
            var value = plot._corrplot.matrix[row][col]
            var cx = _round_to_int(frame.x_scale.center(col))
            var cy = _round_to_int(frame.y_scale.center(row))
            var radius = _round_to_int(max_radius * abs(value))
            target.fill_circle_aa(cx, cy, radius, color_scale.color_at(value))
            if plot._corrplot.labels:
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
    bubble_fraction: Float64 = 0.42,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A correlation plot.

    `Mark.CORRPLOT`: one bubble per cell of a square correlation `matrix`
    over `variables`, sized by `abs` and colored by sign of each pairwise
    correlation. `layout` (`"full"`, `"lower"`, `"upper"`) and `diag`
    match ECharts.jl's `corrplot()` keyword names. See `_render_corrplot`.

    Args:
        variables: One row and one column per entry -- `matrix` must
            be this length square.
        matrix: The square pairwise-correlation matrix, each value in
            `[-1.0, 1.0]`.
        layout: Which triangle of `matrix` to draw -- `"full"` (the
            default), `"lower"`, or `"upper"`.
        diag: Whether to draw the diagonal cells (`variables[i]`
            against itself); defaults to `True`.
        labels: Whether to draw `variables`' names along the axes;
            defaults to `True`.
        bubble_fraction: Each bubble's maximum radius as a fraction of the cell's
            smaller dimension; defaults to `0.42`.
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
        from dataviz import corrplot
        from dataviz.plot import save

        def main() raises:
            var variables: List[String] = ["Horsepower", "MPG", "Weight", "Price"]
            var matrix: List[List[Float64]] = [
                [1.0, -0.78, 0.66, 0.72],
                [-0.78, 1.0, -0.83, -0.55],
                [0.66, -0.83, 1.0, 0.48],
                [0.72, -0.55, 0.48, 1.0],
            ]

            var c = corrplot(variables, matrix, layout="upper", diag=False)
            save(c, "docs/src/examples/out_corrplot.svg")
        ```
    """
    var plot = Plot().mark_corrplot(layout=layout, diag=diag, labels=labels, bubble_fraction=bubble_fraction).encode_corrplot(
        variables=variables, matrix=matrix
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def corrplot[
    dtype: DType
](
    variables: List[String],
    matrix: List[List[Scalar[dtype]]],
    layout: String = "full",
    diag: Bool = True,
    labels: Bool = True,
    bubble_fraction: Float64 = 0.42,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`corrplot()` generalized over numeric element type for `matrix`, via
    `_materialize_nested_scalar_list` (array_like.mojo); see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return corrplot(
        variables, _materialize_nested_scalar_list(matrix), layout=layout, diag=diag, labels=labels,
        bubble_fraction=bubble_fraction, theme=theme, width=width, height=height, title=title, subtitle=subtitle, x_title=x_title,
        y_title=y_title,
    )
