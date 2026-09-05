from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget
from dataviz.plot import _LazyFontCache

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _PointChannels,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel,
    _data_extent,
    _draw_point_layer,
    _legend_origin_x,
    _legend_origin_y,
    _LegendLayout,
    _legend_reserve_for,
    _finished,
    _require_non_empty,
    _validate_continuous_encoding,
)
from dataviz.scale import LinearScale
from dataviz.theme import Theme


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
) raises -> _SingleAxisFrame:
    """`Mark.SINGLE_AXIS`'s frame: one continuous `x_scale` along the bottom
    (ticks, gridlines, labels, the same x half
    `_draw_continuous_axis_frame` draws) and no y-axis.
    `_render_single_axis` places every point at a fixed pixel row between
    the top and bottom of this frame, not on the axis line, so points
    never merge with tick marks.
    """
    var sc = _Scaled(theme)

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom

    var out_x_scale = x_scale
    out_x_scale.range_min = Float64(plot_x0)
    out_x_scale.range_max = Float64(plot_x1)

    var x_ticks = out_x_scale.ticks()
    var x_labels = x_ticks.labels(theme.x_tick_format)

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(out_x_scale, x_ticks.values[i])
            target.draw_line_aa(
                px, plot_y0, px, plot_y1, theme.gridline_color, width=sc.scale
            )

    target.draw_line_aa(
        plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale
    )

    var text_requests = List[_TextRequest]()
    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(out_x_scale, x_ticks.values[i])
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
    mut cache: _LazyFontCache,
) raises -> _RenderResult:
    """Render a `Mark.SINGLE_AXIS` plot: every point from
    `encode_single_axis()`'s `x` at the plot area's vertical center,
    `(py0 + py1) / 2`, on `_draw_single_axis_frame`'s one-axis frame.
    Reuses `Mark.POINT`'s `_draw_point_layer` (color/size channels,
    legends) unchanged through a degenerate `y_scale` whose
    `range_min == range_max == point_y`: `LinearScale.to_pixel` collapses
    to a constant `range_min` when the range span is zero, so every point
    lands on the same row regardless of `plot.y_data[i]`.
    `encode_single_axis()` fills `y_data` with one placeholder `0.0` per
    row so the loop has a same-length list to index.
    """
    _validate_continuous_encoding(plot, "Plot.encode_single_axis()")
    _require_non_empty(len(plot.x_data), "Plot.encode_single_axis()")

    var theme = plot._theme

    var sc = _Scaled(theme)
    var ch = _PointChannels(plot, sc)
    var legend_reserve = _legend_reserve_for(plot, ch, sc, cache=cache)

    var x_scale = _data_extent(plot.x_data)
    var frame = _draw_single_axis_frame(
        target, x_scale, theme, legend_reserve, ox0, oy0, ox1, oy1
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
    )

    return frame.result()


def single_axis(
    x: List[Float64],
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
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var response_ms: List[Int] = [
                12, 14, 13, 15, 11, 14, 13, 12, 45, 15, 13, 14, 12, 90, 14,
            ]

            var c = single_axis(response_ms)
            save(c, "docs/src/examples/out_single_axis.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_single_axis()
        .encode_single_axis(
            x=x, color=color, color_categories=color_categories, size=size
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, "", subtitle=subtitle
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
    """`single_axis()` generalized over numeric element type for `x`; see
    `scatter()`'s `DType` overload (plot.mojo).
    `color`/`color_categories`/`size` stay concrete, as in
    `Plot.encode()`'s array-like overloads. Delegates to the concrete
    overload above.
    """
    return single_axis(
        _materialize_scalar_list(x),
        color=color,
        color_categories=color_categories,
        size=size,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
    )
