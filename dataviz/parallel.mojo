from canvas.path import Path
from canvas.vector.draw_target import DrawTarget
from canvas.text.render import TextAlign

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.color_scale import default_categorical_palette
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
from dataviz.scale import _min_max
from dataviz.theme import Theme


struct _ParallelData(Copyable, Movable):
    """One named axis per dimension, one named row per observation, and one
    value per (row, dimension) pair, for `Mark.PARALLEL`. See
    `encode_parallel()`. Stored on `Plot._parallel`.
    """

    var dims: List[String]
    var row_names: List[String]
    var data: List[List[Float64]]

    def __init__(out self):
        self.dims = List[String]()
        self.row_names = List[String]()
        self.data = List[List[Float64]]()


def _axis_x(plot_x0: Int, plot_x1: Int, n: Int, d: Int) -> Float64:
    """The pixel x of dimension `d`'s vertical axis: `n` axes evenly spaced
    with the first at `plot_x0` and the last at `plot_x1`. A single axis
    centers.
    """
    if n == 1:
        return Float64(plot_x0 + plot_x1) / 2.0
    return Float64(plot_x0) + Float64(d) * Float64(plot_x1 - plot_x0) / Float64(
        n - 1
    )


def _value_y(
    plot_y0: Int,
    plot_y1: Int,
    dim_min: Float64,
    dim_max: Float64,
    value: Float64,
) -> Float64:
    """`value`'s pixel y along one dimension's axis: top (`plot_y0`) is the
    dimension's max, bottom (`plot_y1`) its min. A zero-span dimension
    places `value` at the vertical center rather than dividing by zero.
    """
    var span = dim_max - dim_min
    var frac = 0.5
    if span != 0.0:
        frac = (value - dim_min) / span
    return Float64(plot_y1) - frac * Float64(plot_y1 - plot_y0)


def _render_parallel[
    T: DrawTarget
](
    mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _RenderResult:
    """Render a `Mark.PARALLEL` plot: `encode_parallel()`'s `dims` (one
    vertical axis each, evenly spaced from the plot's left edge to its
    right edge) and one row per `row_names` entry (`data[row]`, one value
    per dimension), each drawn as a straight polyline across the axes.

    Each dimension gets its own domain, `_min_max` over that column across
    every row (unpadded), since dimensions are typically differently
    scaled. A zero-span column places every row at that axis's vertical
    center.

    No axis tick labels beyond each dimension's name at the bottom. Legend
    keyed by `row_names`, drawn whenever `Theme.show_legend` is on.
    """
    _require_non_empty(len(plot._parallel.dims), "Plot.encode_parallel()")

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(
        plot._parallel.row_names, sc.legend_swatch_size, sc
    ) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var n = len(plot._parallel.dims)

    # Each dimension's [min, max] across every row: one _min_max per column.
    var dim_min = List[Float64]()
    var dim_max = List[Float64]()
    for d in range(n):
        var column = List[Float64]()
        for row in plot._parallel.data:
            column.append(row[d])
        var mm = _min_max(column)
        dim_min.append(mm.min)
        dim_max.append(mm.max)

    if theme.show_gridlines:
        for d in range(n):
            var x = Int(_axis_x(plot_x0, plot_x1, n, d))
            target.draw_line_aa(x, plot_y0, x, plot_y1, theme.axis_color)
            text_requests.append(
                _TextRequest(
                    x,
                    plot_y1 + sc.label_gap + Int(sc.font_size),
                    plot._parallel.dims[d],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )

    var palette = default_categorical_palette()
    for r in range(len(plot._parallel.data)):
        var row = plot._parallel.data[r].copy()
        var color = palette[r % len(palette)]
        var path = Path()
        for d in range(n):
            var x = _axis_x(plot_x0, plot_x1, n, d)
            var y = _value_y(plot_y0, plot_y1, dim_min[d], dim_max[d], row[d])
            if d == 0:
                path.move_to(x, y)
            else:
                path.line_to(x, y)
        target.stroke_path_aa(path, color, sc.line_width)

    if show_legend:
        _draw_legend(
            target,
            text_requests,
            plot._parallel.row_names,
            palette,
            plot_x1 + sc.margin_right,
            plot_y0,
            theme,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def parallel(
    data: List[List[Float64]],
    dims: List[String],
    row_names: List[String],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A parallel-coordinates chart.

    `Mark.PARALLEL`: one row per `row_names` entry (`data[row]`, one value
    per `dims` entry) drawn as a polyline across evenly spaced vertical
    axes, each independently scaled to its column's `[min, max]`.
    `row_names` is required, unlike ECharts.jl's `parallel(data, dims)`,
    matching every other named-series `encode_*` here. See
    `_render_parallel`.

    Args:
        data: `data[row]` is `row_names[row]`'s polyline, one value
            per `dims` entry.
        dims: One vertical axis per entry, each independently scaled
            to its own column's `[min, max]` across `data`.
        row_names: One polyline per entry, used as the legend key;
            required (not auto-numbered).
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
        from dataviz import parallel
        from dataviz.plot import save

        def main() raises:
            var dims: List[String] = ["Horsepower", "MPG", "Weight (100 lbs)", "0-60 (sec)", "Price ($k)"]
            var row_names: List[String] = ["Sedan", "SUV", "Sports Car"]
            var data: List[List[Float64]] = [
                [180.0, 32.0, 30.0, 8.5, 28.0],
                [280.0, 22.0, 45.0, 6.5, 42.0],
                [450.0, 16.0, 34.0, 3.5, 85.0],
            ]

            var c = parallel(data, dims, row_names)
            save(c, "docs/src/examples/out_parallel.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_parallel()
        .encode_parallel(dims=dims, row_names=row_names, data=data)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def parallel[
    dtype: DType
](
    data: List[List[Scalar[dtype]]],
    dims: List[String],
    row_names: List[String],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`parallel()` generalized over numeric element type for `data`, via
    `_materialize_nested_scalar_list` (array_like.mojo); see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return parallel(
        _materialize_nested_scalar_list(data),
        dims,
        row_names,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
