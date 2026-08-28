from canvas_mojo.color import Color
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas
from canvas_mojo.text.render import TextAlign

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
    _finished,
)
from dataviz_mojo.scale import _min_max
from dataviz_mojo.theme import Theme


struct _ParallelData(Movable):
    """
    Mark.PARALLEL only -- one named axis per dimension, one named row
    per observation, one value per (row, dimension) pair. See
    encode_parallel()'s docstring.

    Grouped onto `Plot._parallel` -- see `Plot`'s docstring.
    """

    var dims: List[String]
    var row_names: List[String]
    var data: List[List[Float64]]

    def __init__(out self):
        self.dims = List[String]()
        self.row_names = List[String]()
        self.data = List[List[Float64]]()



def _axis_x(plot_x0: Int, plot_x1: Int, n: Int, d: Int) -> Float64:
    """The pixel x of dimension `d`'s vertical axis -- `n` axes
    evenly spaced with the first pinned to `plot_x0` and the last to
    `plot_x1` (a single-axis plot, `n == 1`, is a degenerate case with
    no "spacing" to speak of, so it just centers)."""
    if n == 1:
        return Float64(plot_x0 + plot_x1) / 2.0
    return Float64(plot_x0) + Float64(d) * Float64(plot_x1 - plot_x0) / Float64(n - 1)


def _value_y(plot_y0: Int, plot_y1: Int, dim_min: Float64, dim_max: Float64, value: Float64) -> Float64:
    """`value`'s pixel y along one dimension's axis -- top
    (`plot_y0`) is that dimension's max, bottom (`plot_y1`) its min, the same "more/bigger is up" convention every y-axis in
    this package already uses. A zero-span dimension (every row
    identical on this one) places `value` at the axis's vertical
    center rather than dividing by zero."""
    var span = dim_max - dim_min
    var frac = 0.5
    if span != 0.0:
        frac = (value - dim_min) / span
    return Float64(plot_y1) - frac * Float64(plot_y1 - plot_y0)


def _render_parallel[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.PARALLEL` plot: `encode_parallel()`'s `dims`
    (one vertical axis each, evenly spaced left to right -- the first
    axis at the plot's left edge, the last at its right edge,
    matching every real parallel-coordinates chart's layout, not
    `Mark.RADAR`'s "spokes radiate from a shared center" arrangement)
    and one row per `row_names` entry (`data[row]`, one value per
    dimension), each drawn as a straight polyline connecting its per-dimension positions left to right.

    Each dimension gets its *own* independent domain (`_min_max` over
    that column across every row -- unpadded, the same choice
    `_data_extent` makes for continuous color/size domains), unlike
    `Mark.RADAR`'s caller-supplied `max_values`:
    ECharts.jl's `parallel()` has no per-dimension max parameter
    either, and different dimensions here are typically wildly
    differently scaled (horsepower vs. price vs. 0-60 time, the
    chart type's classic use), so auto-scaling each axis to its column is the only sensible default. A zero-span column (every
    row has the identical value on that dimension) places every row at
    that axis's vertical center rather than dividing by zero.

    No axis tick labels beyond each dimension's name at the
    bottom -- the same simplification `Mark.POLAR`'s `_draw_polar_grid`
    makes for numeric axis readout. Legend keyed by `row_names` (always drawn, even for one
    row -- the same "`Theme.show_legend` is the only real toggle"
    convention every other legend-bearing mark here follows).
    """
    if len(plot._parallel.dims) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = (
        _dynamic_legend_width(plot._parallel.row_names, sc.legend_swatch_size, sc) if show_legend else 0
    )

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var n = len(plot._parallel.dims)

    # Each dimension's [min, max] across every row -- one _min_max
    # per column, not per row (the whole point of a parallel-
    # coordinates axis is comparing every row *on that one dimension's
    # own scale*).
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
                    x, plot_y1 + sc.label_gap + Int(sc.font_size), plot._parallel.dims[d],
                    theme.text_color, sc.font_size, TextAlign.CENTER, theme.font_family,
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
            target, text_requests, plot._parallel.row_names, palette, plot_x1 + sc.margin_right, plot_y0, theme
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
    """A parallel-coordinates chart -- `Mark.PARALLEL`, one row per
    `row_names` entry (`data[row]`, one value per `dims` entry) drawn
    as a polyline across evenly spaced vertical axes, each
    independently scaled to its column's `[min, max]`.
    `row_names` is required, unlike ECharts.jl's `parallel(data,
    dims)` (which auto-numbers rows) -- every other named-series
    `encode_*` in this package takes its names explicitly rather
    than generating them, and this stays consistent with that. See
    `_render_parallel`'s docstring for the full reasoning.

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
    """
    var plot = Plot().mark_parallel().encode_parallel(dims=dims, row_names=row_names, data=data)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
