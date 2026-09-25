from dataviz.chart import Chart
from dataviz.marks import Corrplot
from dataviz.core.plot_fields import _MarkStyle
from dataviz.core.chart_settings import _ChartSettings
from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from std.utils.numerics import isnan
from std.collections import Dict
from dataframe import DataFrame

from dataviz.core.array_like import _materialize_nested_scalar_list
from dataviz.core.color_scale import ColorScale, _color_scale_for
from dataviz.core.frame_input import _frame_floats
from dataviz.core.stats import _pearson_correlation
from dataviz.grid.heatmap import _draw_grid_axis_frame
from dataviz.core.mark import Mark
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.tooltip_labels import _cell_tooltip_label
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.legend import (
    _continuous_color_legend_layout,
    _draw_continuous_color_legend_at,
)
from dataviz.core.validate import _require_non_empty
from dataviz.core.scale import _format_fixed
from dataviz.core.theme import Theme
from dataviz.core.mark import _require_mark


struct _CorrplotData(Copyable, Movable):
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
](
    mut target: T,
    corrplot: _CorrplotData,
    style: _MarkStyle,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a square correlation matrix as sized, colored bubbles.

    Bubble radius uses absolute correlation and color uses a fixed `[-1, 1]`
    scale. Layout selects the full, lower, or upper triangle; diagonal cells
    and value labels are optional.
    """
    if len(corrplot.matrix) != len(corrplot.variables):
        raise Error(
            "Plot.encode_corrplot(): matrix must have one row per variable"
            " (expected "
            + String(len(corrplot.variables))
            + " rows, got "
            + String(len(corrplot.matrix))
            + ")"
        )
    for row in corrplot.matrix:
        if len(row) != len(corrplot.variables):
            raise Error(
                "Plot.encode_corrplot(): matrix must be square, one value per"
                " variable in every row (expected "
                + String(len(corrplot.variables))
                + ", got "
                + String(len(row))
                + ")"
            )

    var theme = settings.theme
    _require_non_empty(len(corrplot.variables), "Plot.encode_corrplot()")
    for row in corrplot.matrix:
        for v in row:
            if v < -1.0 or v > 1.0:
                raise Error(
                    "Plot: Mark.CORRPLOT values must be in [-1.0, 1.0] (got "
                    + String(v)
                    + ")"
                )

    var sc = _Scaled(theme)
    var color_scale = _color_scale_for(theme, settings.color_domain, -1.0, 1.0)

    # Reuse the cache for legend and axis-label measurement.

    var legend = _continuous_color_legend_layout(
        color_scale, theme, sc, cache=cache
    )

    var frame = _draw_grid_axis_frame(
        target,
        corrplot.variables,
        corrplot.variables,
        theme,
        ox0 + legend.left,
        oy0 + legend.top,
        ox1 - legend.right,
        oy1 - legend.bottom,
        cache=cache,
    )

    var cell_width = frame.x_scale.bandwidth()
    var cell_height = frame.y_scale.bandwidth()
    var max_radius = (
        min(cell_width, cell_height) / 2.0 * style.corrplot_bubble_fraction
    )
    var n = len(corrplot.variables)

    var tooltips_on = settings.tooltips_on(n * n)
    for row in range(n):
        for col in range(n):
            if row == col and not corrplot.diag:
                continue
            if corrplot.layout == "lower" and col > row:
                continue
            if corrplot.layout == "upper" and col < row:
                continue
            var value = corrplot.matrix[row][col]
            # Neither the center nor the radius rounds. A disk is
            # antialiased on every side wherever it sits, so rounding
            # its center bought no crispness -- and rounding the radius
            # was destroying the encoding this chart exists for. The
            # number of circle sizes a corrplot could draw was
            # max_radius + 1, and max_radius is only 0.21 of a cell: a
            # 15-variable matrix on a 640px canvas had about six
            # distinct sizes, so correlations of 0.50 and 0.65 came out
            # the same circle.
            var cx = frame.x_scale.center(col)
            var cy = frame.y_scale.center(row)
            var radius = max_radius * abs(value)
            if tooltips_on:
                target.begin_annotated_group(
                    _cell_tooltip_label(
                        corrplot.variables[row],
                        corrplot.variables[col],
                        value,
                    )
                )
            # A missing correlation is left blank rather than drawn at
            # one end of the ramp (#367).
            if isnan(value):
                continue
            target.fill_circle_aa(cx, cy, radius, color_scale.color_at(value))
            if tooltips_on:
                target.end_annotated_group()
            if corrplot.labels:
                frame.text_requests.append(
                    _TextRequest(
                        round_to_int(cx),
                        round_to_int(cy) + Int(sc.font_size * 0.35),
                        _format_fixed(value, 2),
                        theme.text_color,
                        sc.font_size,
                        TextAlign.CENTER,
                        theme.font_family,
                    )
                )

    _draw_continuous_color_legend_at(
        target,
        frame.text_requests,
        color_scale,
        legend,
        frame.px0,
        frame.py0,
        frame.px1,
        frame.py1,
        theme,
        cache=cache,
    )

    return frame.result()


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
) raises -> Chart[Corrplot]:
    """A correlation plot: one bubble per cell of a correlation matrix,
    sized and colored by strength, for spotting which variable pairs
    move together across a dataset too large to read as a table of
    numbers.

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
        The finished chart -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import corrplot
        from dataviz import save

        def main() raises:
            # Illustrative correlations across electric-vehicle specifications.
            # Six variables reveal clusters and tradeoffs that a tiny matrix hides.
            var variables: List[String] = [
                "Price", "Range", "Efficiency", "Charge time", "Cargo", "0-60 time",
            ]
            var matrix: List[List[Float64]] = [
                [1.0, 0.72, 0.18, -0.25, 0.48, -0.63],
                [0.72, 1.0, -0.22, 0.35, 0.51, -0.40],
                [0.18, -0.22, 1.0, -0.44, -0.58, 0.36],
                [-0.25, 0.35, -0.44, 1.0, 0.18, 0.22],
                [0.48, 0.51, -0.58, 0.18, 1.0, -0.15],
                [-0.63, -0.40, 0.36, 0.22, -0.15, 1.0],
            ]

            var c = corrplot(
                variables,
                matrix,
                layout="upper",
                diag=False,
                title="Illustrative EV Metric Correlations",
            )
            save(c, "docs/src/examples/out_corrplot.svg")
        ```
    """
    var matrix_f = _materialize_nested_scalar_list(matrix)
    var plot = (
        Plot()
        .mark_corrplot(
            layout=layout,
            diag=diag,
            labels=labels,
            bubble_fraction=bubble_fraction,
        )
        .encode_corrplot(variables=variables, matrix=matrix_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def corrplot(
    df: DataFrame,
    columns: List[String],
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
) raises -> Chart[Corrplot]:
    """Correlation plot computed from named numeric DataFrame columns.

    Pearson correlations use rows where both columns are present. At least
    two complete rows with variation in each column are required for each
    pair. `Theme(missing=Missing.RAISE)` rejects nulls on read instead.

    Args:
        df: Observations, one row per sample.
        columns: Numeric column names, in plot order.
        layout: See the matrix overload.
        diag: See the matrix overload.
        labels: See the matrix overload.
        bubble_fraction: See the matrix overload.
        theme: See the matrix overload.
        width: See the matrix overload.
        height: See the matrix overload.
        title: See the matrix overload.
        subtitle: See the matrix overload.
        x_title: See the matrix overload.
        y_title: See the matrix overload.

    Returns:
        The finished `Plot`.

    Raises:
        Error: A column is missing, nonnumeric, repeated, constant, or
            has too few paired observations with another column.
    """
    if len(columns) == 0:
        raise Error("corrplot(): columns must not be empty")
    var seen = Dict[String, Int]()
    var values = List[List[Float64]]()
    for i in range(len(columns)):
        var name = columns[i]
        if name in seen:
            raise Error('corrplot(): duplicate column "' + name + '"')
        seen[name] = i
        values.append(_frame_floats(df, name, "corrplot()", theme.missing))
    var matrix = List[List[Float64]]()
    for row in range(len(columns)):
        var correlations = List[Float64]()
        for col in range(len(columns)):
            try:
                correlations.append(
                    _pearson_correlation(values[row], values[col])
                )
            except e:
                raise Error(
                    'corrplot(): columns "'
                    + columns[row]
                    + '" and "'
                    + columns[col]
                    + '": '
                    + String(e)
                )
        matrix.append(correlations^)
    return corrplot(
        columns,
        matrix,
        layout=layout,
        diag=diag,
        labels=labels,
        bubble_fraction=bubble_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def _encode_corrplot(
    mark: Mark,
    mut corrplot: _CorrplotData,
    variables: List[String],
    matrix: List[List[Float64]],
) raises:
    """`Plot.encode_corrplot()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(mark, "encode_corrplot", "mark_corrplot()", Mark.CORRPLOT)
    corrplot.variables = variables.copy()
    corrplot.matrix = matrix.copy()
