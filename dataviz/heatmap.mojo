from canvas.geometry import _round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale
from canvas.text.font_cache import FontCache
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _categorical_indices,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
    _empty_result,
    _max_label_width,
    _min_max,
    _finished,
)
from dataviz.scale import _format_fixed
from dataviz.theme import Theme


struct _HeatmapData(Movable):
    """
    Mark.HEATMAP only -- one (x category, y category, value) row per
    grid cell. See encode_heatmap()'s docstring.

    Grouped onto `Plot._heatmap` -- see `Plot`'s docstring.
    """

    var x: List[String]
    var y: List[String]
    var value: List[Float64]

    def __init__(out self):
        self.x = List[String]()
        self.y = List[String]()
        self.value = List[Float64]()



struct _GridFrame(Movable):
    """`_draw_grid_axis_frame`'s finished layout -- the two-
    categorical-axis analog of `_CategoricalFrame`/`_HorizontalCategoricalFrame`
    (both `x_scale`/`y_scale` are `OrdinalScale` here, not one continuous
    `LinearScale` -- shared by every mark with no continuous axis at
    all: `Mark.HEATMAP`/`CORRPLOT`/`PUNCHCARD`). See that function's
    docstring for what this computes.

    `px0`/`py0`/`px1`/`py1` -- see `_CategoricalFrame`'s docstring
    for what these are and why they're carried through unchanged."""

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
        """This frame as the `_RenderResult` `_render_heatmap` returns
        -- see `_CategoricalFrame.result`'s docstring, which this
        mirrors exactly."""
        return _RenderResult(self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1)


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
    `x_categories` left-to-right, `y_categories` top-to-bottom (category
    index 0 at the *top* -- the same reading-order convention `_draw_
    horizontal_categorical_axis_frame`'s y-axis uses
    for `Mark.GANTT`/`POPULATION_PYRAMID`, not `_draw_categorical_axis_
    frame`'s reversed one, since there's no zero-baseline-at-bottom
    convention to preserve here -- there's no baseline at all). Its own
    function, not a further generalization of either existing frame
    core -- a two-categorical-axis grid is different enough in shape
    from both (one categorical + one continuous axis apiece) that
    folding it in would need the same kind of orientation branch
    `_draw_horizontal_categorical_axis_frame`'s docstring
    warns against. Shared by three callers today (`Mark.HEATMAP`/
    `CORRPLOT`/`PUNCHCARD`).

    Both `OrdinalScale`s are built with `padding=0.0` (unlike every
    other categorical axis in this package, which defaults to `0.2`) --
    a heatmap's cells are meant to tile the grid edge-to-edge with no
    gap between neighbors, the same "no gap" look every real heatmap
    (a correlation matrix, a calendar heatmap) has, not `Mark.BAR`'s separated bars.

    The dynamic left margin grows to fit `y_categories`' text (the
    raw strings, no `.ticks()`/`.labels()` step) -- the same reasoning
    `_draw_horizontal_categorical_axis_frame`'s docstring gives for
    its identical choice, since `y_categories` here is likewise an
    `OrdinalScale` domain, not numeric tick values.
    """
    var sc = _Scaled(theme)

    var dynamic_left_margin = (
        Int(_max_label_width(y_categories, sc.font_size, cache=cache)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom

    var x_scale = OrdinalScale(x_categories.copy(), Float64(plot_x0), Float64(plot_x1), padding=0.0)
    var y_scale = OrdinalScale(y_categories.copy(), Float64(plot_y0), Float64(plot_y1), padding=0.0)

    target.draw_line_aa(plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale)
    target.draw_line_aa(plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale)

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_categories)):
        var center_py = _round_to_int(y_scale.center(i))
        target.draw_line_aa(plot_x0 - sc.tick_length, center_py, plot_x0, center_py, theme.axis_color, width=sc.scale)
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
        var center_px = _round_to_int(x_scale.center(i))
        target.draw_line_aa(center_px, plot_y1, center_px, plot_y1 + sc.tick_length, theme.axis_color, width=sc.scale)
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

    return _GridFrame(x_scale^, y_scale^, sc^, text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def _render_heatmap[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.HEATMAP` plot: `_draw_grid_axis_frame`'s two-
    categorical-axis grid, one filled cell per `encode_heatmap()` row,
    colored through a continuous `ColorScale` spanning `value`'s [min, max] (`ColorScale.from_theme` -- the exact same three-stop
    gradient `Mark.POINT`'s continuous `color=` channel already
    uses, see `_PointChannels`' construction of one, so a heatmap
    and a continuous-color scatter plot read with the same color
    vocabulary).

    `x`/`y` are deduplicated into each axis's domain via
    `_categorical_indices` (first-seen order, the same helper `Mark.
    POINT`'s categorical color channel resolves its domain through)
    -- a caller gives one row per cell, not a separate axis-category
    list, the same "the data already says what the axis needs" shape
    `encode_categorical()` uses for a single categorical axis.
    A missing (x, y) combination simply isn't drawn (background shows
    through) rather than being treated as an error or a zero -- real
    heatmap data (a sparse calendar, an incomplete matrix) is commonly
    not a dense grid.

    Draws a continuous color legend (`_draw_continuous_color_legend`,
    the same one `Mark.POINT`'s continuous color channel uses) when
    `Theme.show_legend` is on, reserved from the outer `ox1` the same
    "shrink the rect from outside" way every other categorical mark's legend already does.
    """
    if len(plot._heatmap.x) != len(plot._heatmap.y) or len(plot._heatmap.value) != len(plot._heatmap.x):
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
    if len(plot._heatmap.x) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var x_idx = _categorical_indices(plot._heatmap.x)
    var y_idx = _categorical_indices(plot._heatmap.y)

    var sc = _Scaled(theme)
    var value_mm = _min_max(plot._heatmap.value)
    var color_scale = ColorScale.from_theme(theme, value_mm.min, value_mm.max)

    # One FontCache for both measurements this render makes -- the
    # legend's labels here, then the y-axis category labels inside
    # _draw_grid_axis_frame. A fresh cache per call re-pays canvas_
    # mojo's font resolution and TTF parse for a font already loaded.
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
        target, x_idx.domain, y_idx.domain, theme, ox0, oy0, ox1 - legend_reserve, oy1,
        cache=measure_cache
    )

    var cell_width = _round_to_int(frame.x_scale.bandwidth())
    var cell_height = _round_to_int(frame.y_scale.bandwidth())
    for i in range(len(plot._heatmap.x)):
        var cell_x = _round_to_int(frame.x_scale.band_start(x_idx.indices[i]))
        var cell_y = _round_to_int(frame.y_scale.band_start(y_idx.indices[i]))
        var color = color_scale.color_at(plot._heatmap.value[i])
        target.fill_rect(cell_x, cell_y, cell_width, cell_height, color)

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
    """A heatmap -- `Mark.HEATMAP`, one colored grid cell per (x, y)
    pair, colored by `value` through a continuous gradient. See `Plot.
    encode_heatmap()`'s docstring (plot.mojo) for the exact shape.

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
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


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
    """`heatmap()`, generalized over numeric element type -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `heatmap()` above.
    """
    return heatmap(
        x, y, _materialize_scalar_list(value), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
