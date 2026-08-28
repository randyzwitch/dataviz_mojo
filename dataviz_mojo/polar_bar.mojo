from std.math import pi

from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
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
    _finished,
    _validate_categorical_encoding,
    _require_non_negative,
    _require_some_positive,
)
from dataviz_mojo.theme import Theme


def _render_polar_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.POLAR_BAR` plot: "bars radiate outward from the
    centre of a circle" (ECharts.jl's `polarbar` docs) -- one bar
    per category (`encode_categorical`'s `x`), each its equal-width
    angular slot (`2*pi/N`, `Mark.NIGHTINGALE`'s convention), bar
    length (radius) proportional to `value / max(values)` (always
    linear -- unlike `NIGHTINGALE`, there's no `rose_type="area"`
    equivalent here; ECharts' polarbar has no such mode). The one
    real difference from `NIGHTINGALE`'s wedges: `theme.polar_
    bar_padding` carves a gap out of each bar's angular slot (split
    evenly on both sides), so bars read as separated columns -- the
    same "separated bands vs. edge-to-edge cells" distinction `Mark.
    HEATMAP`'s docstring already draws against `Mark.BAR`, applied
    here to `NIGHTINGALE`'s edge-to-edge sectors instead.

    Shares `NIGHTINGALE`'s identical validation (non-negative values,
    at least one positive), palette, legend, and margin-box layout,
    but needs its own render path: the padding changes the actual
    angle math, not just which primitive draws the result.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.POLAR_BAR")
    var max_v = _require_some_positive(plot.y_data, "Mark.POLAR_BAR")

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(plot.x_categories, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9

    var palette = default_categorical_palette()
    var n = len(plot.x_categories)
    var slot = 2.0 * pi / Float64(n)
    var gap = slot * theme.polar_bar_padding
    var slot_start = -pi / 2.0
    for i in range(n):
        var start = slot_start + gap / 2.0
        var end = slot_start + slot - gap / 2.0
        var radius = max_radius * (plot.y_data[i] / max_v)
        var color = palette[i % len(palette)]
        target.fill_arc_aa(cx, cy, radius, start, end, color)
        slot_start += slot

    if show_legend:
        _draw_legend(
            target, text_requests, plot.x_categories, palette, plot_x1 + sc.margin_right, plot_y0, theme
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def polarbar(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A circular column chart -- `Mark.POLAR_BAR` over a categorical
    `x` and continuous `y` (the same shape `bar()`/`pie()` take; every
    value must be non-negative, and at least one positive). Bars
    radiate outward from the chart's center, one equal-width
    angular slot per category, length proportional to `value /
    max(values)` -- see `_render_polar_bar`'s docstring for how
    this differs from `nightingale()`'s edge-to-edge wedges.

    Args:
        categories: One equal-width angular slot per entry, in the
            given order.
        values: Each bar's length, proportional to `value /
            max(values)`; every value must be non-negative, and at
            least one positive.
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
    var plot = Plot().mark_polar_bar().encode_categorical(x=categories, y=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
