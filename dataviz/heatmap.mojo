from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from dataviz.pixel_snap import _snap_pixel_edge
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _categorical_indices,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
    _max_label_width,
    _min_max,
    _finished,
    _require_non_empty,
)
from dataviz.scale import _format_fixed
from dataviz.theme import Theme


struct _HeatmapData(Copyable, Movable):
    """One (x category, y category, value) row per grid cell, for
    `Mark.HEATMAP`. See `encode_heatmap()`. Stored on `Plot._heatmap`.
    """

    var x: List[String]
    var y: List[String]
    var value: List[Float64]

    def __init__(out self):
        self.x = List[String]()
        self.y = List[String]()
        self.value = List[Float64]()


struct _GridFrame(Movable):
    """`_draw_grid_axis_frame`'s finished layout: the two-categorical-axis
    analog of `_CategoricalFrame`/`_HorizontalCategoricalFrame` (both
    `x_scale` and `y_scale` are `OrdinalScale`s), shared by
    `Mark.HEATMAP`/`CORRPLOT`/`PUNCHCARD`. `px0`/`py0`/`px1`/`py1` are the
    inner plot rect, as in `_CategoricalFrame`.
    """

    var x_scale: OrdinalScale
    var y_scale: OrdinalScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self,
        var x_scale: OrdinalScale,
        var y_scale: OrdinalScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
    ):
        self.x_scale = x_scale^
        self.y_scale = y_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1

    def result(self) -> _RenderResult:
        """This frame as the `_RenderResult` `_render_heatmap` returns; mirrors
        `_CategoricalFrame.result`.
        """
        return _RenderResult(
            self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1
        )


def _draw_grid_axis_frame[
    T: DrawTarget
](
    mut target: T,
    x_categories: List[String],
    y_categories: List[String],
    theme: Theme,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _GridFrame:
    """`Mark.HEATMAP`'s axis-frame core: two `OrdinalScale` axes,
    `x_categories` left-to-right and `y_categories` top-to-bottom (index
    0 at the top, as in `_draw_horizontal_categorical_axis_frame`; there
    is no baseline to anchor at the bottom). Its own function rather than
    a generalization of either one-categorical-axis frame, shared by
    `Mark.HEATMAP`/`CORRPLOT`/`PUNCHCARD`.

    Both `OrdinalScale`s use `padding=0.0` so cells tile edge-to-edge.
    The dynamic left margin grows to fit `y_categories`' raw strings, as
    `_draw_horizontal_categorical_axis_frame` does for its category names.
    """
    var sc = _Scaled(theme)

    var dynamic_left_margin = (
        Int(_max_label_width(y_categories, sc.font_size, cache=cache))
        + sc.tick_length
        + sc.label_gap
        + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom

    var x_scale = OrdinalScale(
        x_categories.copy(), Float64(plot_x0), Float64(plot_x1), padding=0.0
    )
    var y_scale = OrdinalScale(
        y_categories.copy(), Float64(plot_y0), Float64(plot_y1), padding=0.0
    )

    target.draw_line_aa(
        plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale
    )
    target.draw_line_aa(
        plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale
    )

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_categories)):
        var center_py = round_to_int(y_scale.center(i))
        target.draw_line_aa(
            plot_x0 - sc.tick_length,
            center_py,
            plot_x0,
            center_py,
            theme.axis_color,
            width=sc.scale,
        )
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                center_py + y_label_baseline_offset,
                y_categories[i],
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )

    for i in range(len(x_categories)):
        var center_px = round_to_int(x_scale.center(i))
        target.draw_line_aa(
            center_px,
            plot_y1,
            center_px,
            plot_y1 + sc.tick_length,
            theme.axis_color,
            width=sc.scale,
        )
        text_requests.append(
            _TextRequest(
                center_px,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                x_categories[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    return _GridFrame(
        x_scale^,
        y_scale^,
        sc^,
        text_requests^,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
    )


def _render_heatmap[
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
    """Render a `Mark.HEATMAP` plot: `_draw_grid_axis_frame`'s
    two-categorical-axis grid, one filled cell per `encode_heatmap()` row,
    colored through `ColorScale.from_theme` over `value`'s [min, max] (the
    same three-stop gradient `Mark.POINT`'s continuous `color=` channel
    uses).

    `x`/`y` are deduplicated into each axis's domain via
    `_categorical_indices` (first-seen order). A missing (x, y)
    combination is simply not drawn.

    Draws a continuous color legend (`_draw_continuous_color_legend`)
    when `Theme.show_legend` is on, reserved from the outer `ox1`.
    """
    if len(plot._heatmap.x) != len(plot._heatmap.y) or len(
        plot._heatmap.value
    ) != len(plot._heatmap.x):
        raise Error(
            "Plot.encode_heatmap(): x, y, and value must all have the same"
            " length (got "
            + String(len(plot._heatmap.x))
            + " x values, "
            + String(len(plot._heatmap.y))
            + " y values, "
            + String(len(plot._heatmap.value))
            + " values)"
        )

    var theme = plot._theme
    _require_non_empty(len(plot._heatmap.x), "Plot.encode_heatmap()")
    var x_idx = _categorical_indices(plot._heatmap.x)
    var y_idx = _categorical_indices(plot._heatmap.y)

    var sc = _Scaled(theme)
    var value_mm = _min_max(plot._heatmap.value)
    var color_scale = ColorScale.from_theme(theme, value_mm.min, value_mm.max)

    # The render's shared cache serves both measurements: the legend's labels
    # here, then the y-axis category labels inside _draw_grid_axis_frame.

    var legend_reserve = 0
    if theme.show_legend:
        var legend_labels = List[String]()
        legend_labels.append(_format_fixed(color_scale.domain_max, 1))
        legend_labels.append(_format_fixed(color_scale.domain_min, 1))
        legend_reserve = _dynamic_legend_width(
            legend_labels,
            sc.continuous_legend_bar_width,
            sc,
            cache=cache,
        )

    var frame = _draw_grid_axis_frame(
        target,
        x_idx.domain,
        y_idx.domain,
        theme,
        ox0,
        oy0,
        ox1 - legend_reserve,
        oy1,
        cache=cache,
    )

    # Every cell comes from its own two snapped edges, never from a
    # rounded corner plus one rounded size shared by the whole grid.
    # A shared size cannot tile a fractional band: at 11 columns across
    # 320px the band is 29.09 wide, so the rounded width 29 falls short
    # of the step often enough that one cell's right edge stops a pixel
    # before the next one's left edge begins, and the background shows
    # through as a hairline seam down the middle of the chart.
    #
    # Snapping each edge fixes that by construction: the value that
    # snaps to cell i's right edge is the same value that snaps to cell
    # i+1's left edge, so the two land on the same boundary whatever the
    # fraction was. Cells then vary by a pixel in width, which is the
    # honest way to divide 320 pixels 11 ways.
    # band_start is a pixel index -- the first column the band covers --
    # and a column's geometry starts half a pixel before its index, so
    # the grid's outer edge lines up with the plot rect instead of
    # sitting a pixel inside it.
    var x_band = frame.x_scale.bandwidth()
    var y_band = frame.y_scale.bandwidth()
    for i in range(len(plot._heatmap.x)):
        var x_start = frame.x_scale.band_start(x_idx.indices[i]) - 0.5
        var y_start = frame.y_scale.band_start(y_idx.indices[i]) - 0.5
        var cell_x = _snap_pixel_edge(x_start)
        var cell_y = _snap_pixel_edge(y_start)
        var color = color_scale.color_at(plot._heatmap.value[i])
        target.fill_rect(
            cell_x,
            cell_y,
            _snap_pixel_edge(x_start + x_band) - cell_x,
            _snap_pixel_edge(y_start + y_band) - cell_y,
            color,
        )

    if theme.show_legend:
        _ = _draw_continuous_color_legend(
            target,
            frame.text_requests,
            color_scale,
            round_to_int(frame.x_scale.range_max) + sc.margin_right,
            frame.py0,
            theme,
        )

    return frame.result()


def heatmap(
    x: List[String],
    y: List[String],
    value: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A heatmap: a grid of cells colored by value across two categorical
    axes, for spotting patterns across a large matrix of numbers faster
    than a table of the same data would allow.

    `Mark.HEATMAP`: one colored grid cell per (x, y) pair, colored by
    `value` through a continuous gradient. See `Plot.encode_heatmap()`
    (plot.mojo) for the data shape.

    Args:
        x: Each cell's column category, one entry per row of data.
        y: Each cell's row category, one entry per row of data.
        value: Each cell's value, mapped through a continuous color
            gradient.
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
        from dataviz import heatmap
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var days: List[String] = ["Mon", "Mon", "Mon", "Tue", "Tue", "Tue", "Wed", "Wed", "Wed"]
            var hours: List[String] = ["9am", "1pm", "5pm", "9am", "1pm", "5pm", "9am", "1pm", "5pm"]
            var activity: List[Int] = [3, 8, 5, 4, 9, 6, 2, 7, 10]

            var c = heatmap(days, hours, activity)
            save(c, "docs/src/examples/out_heatmap.svg")
        ```
    """
    var plot = Plot().mark_heatmap().encode_heatmap(x=x, y=y, value=value)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def heatmap[
    dtype: DType
](
    x: List[String],
    y: List[String],
    value: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`heatmap()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.
    """
    return heatmap(
        x,
        y,
        _materialize_scalar_list(value),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
