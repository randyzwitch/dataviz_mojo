from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.frame import _draw_axis_spines, _axis_pixel, _fitting_ticks
from dataviz.plot import Plot, _finished
from dataviz.core.point_channels import _PointChannels
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.extent import _data_extent
from dataviz.basic.continuous import _draw_point_layer
from dataviz.core.legend import (
    _legend_origin_x,
    _legend_origin_y,
    _LegendLayout,
    _legend_reserve_for,
)
from dataviz.core.validate import (
    _require_non_empty,
    _validate_continuous_encoding,
)
from dataviz.core.scale import LinearScale
from dataviz.core.theme import Theme
from dataviz.core.mark import Mark, _require_mark


struct _SingleAxisFrame(Movable):
    """`_draw_single_axis_frame`'s finished layout: one continuous `x_scale`
    and no y-axis. `Mark.SINGLE_AXIS` is the only mark that draws exactly
    one axis.
    """

    var x_scale: LinearScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self,
        var x_scale: LinearScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
    ):
        self.x_scale = x_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1

    def result(self) -> _RenderResult:
        return _RenderResult(
            self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1
        )


def _draw_single_axis_frame[
    T: DrawTarget
](
    mut target: T,
    x_scale: LinearScale,
    theme: Theme,
    legend: _LegendLayout,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _SingleAxisFrame:
    """Draw a continuous bottom axis and no y-axis.

    Points use a fixed row inside the plot so they do not overlap tick marks.
    """
    var sc = _Scaled(theme)

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom

    var out_x_scale = x_scale
    out_x_scale.range_min = Float64(plot_x0)
    out_x_scale.range_max = Float64(plot_x1)

    var x_ticks = _fitting_ticks(
        out_x_scale,
        Float64(plot_x1 - plot_x0),
        True,
        theme.x_tick_format,
        sc,
        theme.font_family,
        cache,
    )
    var x_labels = x_ticks.labels(theme.x_tick_format)

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(out_x_scale, x_ticks.values[i])
            target.draw_line_aa(
                px, plot_y0, px, plot_y1, theme.gridline_color, width=sc.scale
            )

    # No y-axis at all on this mark, so no left or right line whatever
    # the theme says; see `_draw_axis_spines`.
    _draw_axis_spines(
        target,
        theme,
        sc,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
        x_axis_y=plot_y1,
        y_axis_x=plot_x0,
        y_axis_visible=False,
    )

    var text_requests = List[_TextRequest]()
    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(out_x_scale, x_ticks.values[i])
        if theme.show_axis_bottom:
            target.draw_line_aa(
                px,
                plot_y1,
                px,
                plot_y1 + sc.tick_length,
                theme.axis_color,
                width=sc.scale,
            )
        text_requests.append(
            _TextRequest(
                px,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                x_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    return _SingleAxisFrame(
        out_x_scale, sc^, text_requests^, plot_x0, plot_y0, plot_x1, plot_y1
    )


def _render_single_axis[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.SINGLE_AXIS` plot: every point from
    `encode_single_axis()`'s `x` at the plot area's vertical center,
    `(py0 + py1) / 2`, on `_draw_single_axis_frame`'s one-axis frame.
    Reuses `Mark.POINT`'s `_draw_point_layer` (color/size channels,
    legends) unchanged through a degenerate `y_scale` whose
    `range_min == range_max == point_y`: `LinearScale.to_pixel` collapses
    to a constant `range_min` when the range span is zero, so every point
    lands on the same row regardless of `plot._continuous.y[i]`.
    `encode_single_axis()` fills `_continuous.y` with one placeholder `0.0` per
    row so the loop has a same-length list to index.
    """
    _validate_continuous_encoding(
        plot._continuous,
        plot._channels,
        plot._y_err,
        plot._mark,
        "Plot.encode_single_axis()",
    )
    _require_non_empty(len(plot._continuous.x), "Plot.encode_single_axis()")

    var theme = plot._settings.theme

    var sc = _Scaled(theme)
    var ch = _PointChannels(
        plot._channels, plot._settings.theme, plot._settings.color_domain, sc
    )
    var legend_reserve = _legend_reserve_for(
        plot._mark, plot._settings.theme, ch, sc, cache=cache
    )

    var x_scale = _data_extent(plot._continuous.x)
    var frame = _draw_single_axis_frame(
        target,
        x_scale,
        theme,
        legend_reserve,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var point_y = Float64(frame.py0 + frame.py1) / 2.0
    var y_scale = LinearScale(0.0, 1.0, point_y, point_y)

    _ = _draw_point_layer(
        target,
        frame.text_requests,
        plot,
        ch,
        frame.x_scale,
        y_scale,
        _legend_origin_x(legend_reserve, frame.px0, frame.px1, sc),
        _legend_origin_y(legend_reserve, frame.py0, frame.py1, sc),
        legend_horizontal=legend_reserve.position.is_horizontal(),
        cache=cache,
    )

    return frame.result()


def single_axis(
    df: DataFrame,
    x: String,
    color: String = "",
    color_categories: String = "",
    size: String = "",
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
) raises -> Plot:
    """`single_axis()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        x: The numeric column for this channel.
        color: The numeric column for this channel; left empty, the channel is unused.
        color_categories: The string column for this channel; left empty, the channel is unused.
        size: The numeric column for this channel; left empty, the channel is unused.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.
        x_title: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var x_values = _frame_floats(df, x, "single_axis()", theme.missing)
    var color_values = List[Float64]()
    if color.byte_length() > 0:
        color_values = _frame_floats(df, color, "single_axis()", theme.missing)
    var color_categories_values = List[String]()
    if color_categories.byte_length() > 0:
        color_categories_values = _frame_strings(
            df, color_categories, "single_axis()"
        )
    var size_values = List[Float64]()
    if size.byte_length() > 0:
        size_values = _frame_floats(df, size, "single_axis()", theme.missing)
    return single_axis(
        x=x_values,
        color=color_values,
        color_categories=color_categories_values,
        size=size_values,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
    )


def single_axis[
    dtype: DType
](
    x: List[Scalar[dtype]],
    color: List[Float64] = List[Float64](),
    color_categories: List[String] = List[String](),
    size: List[Float64] = List[Float64](),
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
) raises -> Plot:
    """A single-axis chart: every value plotted along one horizontal
    line rather than a full x/y plane, for showing a single variable's
    distribution or spread without the extra axis a scatter plot would
    need.

    `Mark.SINGLE_AXIS`: every value in `x` plotted along one horizontal
    axis with no y-axis, for seeing the distribution of one-dimensional
    data. See `Plot.encode_single_axis()` (plot.mojo) for the optional
    `color`/`color_categories`/`size` channels.

    Args:
        x: The continuous column, one entry per point, plotted along
            the single horizontal axis.
        color: Optional continuous color channel, mapped through a
            gradient spanning its own `[min, max]`; mutually exclusive
            with `color_categories`. Left empty (the default), every
            point uses `Theme.mark_color`.
        color_categories: Optional discrete color channel, palette-
            colored by each value's first-seen order; mutually
            exclusive with `color`. Left empty (the default), every
            point uses `Theme.mark_color`.
        size: Optional point-size channel. Left empty (the default),
            every point uses `Theme.point_radius`.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import single_axis
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Illustrative request latencies: a dense healthy cluster plus a
            # sparse long tail that is easy to spot on a single axis.
            var response_ms: List[Int] = [
                11, 12, 12, 13, 13, 13, 14, 14, 14, 14,
                15, 15, 15, 16, 16, 17, 17, 18, 19, 20,
                22, 24, 27, 31, 38, 46, 59, 73, 91, 128,
            ]

            var c = single_axis(
                response_ms,
                title="Illustrative API Response-Time Distribution",
                x_title="Response time (ms)",
            )
            save(c, "docs/src/examples/out_single_axis.svg")
        ```
    """
    var x_f = _materialize_scalar_list(x)
    var plot = (
        Plot()
        .mark_single_axis()
        .encode_single_axis(
            x=x_f, color=color, color_categories=color_categories, size=size
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, "", subtitle=subtitle
    )


def _encode_single_axis(
    mut plot: Plot,
    x: List[Float64],
    color: List[Float64],
    color_categories: List[String],
    size: List[Float64],
) raises:
    """`Plot.encode_single_axis()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(
        plot._mark,
        "encode_single_axis",
        "mark_single_axis()",
        Mark.SINGLE_AXIS,
    )
    plot._continuous.x = x.copy()
    plot._categorical.x = List[String]()
    plot._continuous.y = List[Float64]()
    for _ in range(len(x)):
        plot._continuous.y.append(0.0)
    plot._channels.color = color.copy()
    plot._channels.color_categories = color_categories.copy()
    plot._channels.size = size.copy()
