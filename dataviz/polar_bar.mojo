from std.math import pi

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _LegendLayout,
    _draw_legend_at,
    _legend_layout,
    _finished,
    _validate_categorical_encoding,
    _require_non_negative,
    _require_some_positive,
)
from dataviz.theme import Theme


def _render_polar_bar[
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
    """Render a `Mark.POLAR_BAR` plot: bars radiating outward from the
    center of a circle (ECharts.jl's `polarbar`). One bar per category
    (`encode_categorical`'s `x`) in an equal-width angular slot
    (`2*pi/N`), bar length proportional to `value / max(values)`, always
    linear (no `NIGHTINGALE`-style area mode).
    `plot._mark_style.polar_bar_padding` carves a gap out of each slot,
    split evenly on both sides, so bars read as separated columns.

    Shares `NIGHTINGALE`'s validation (non-negative values, at least one
    positive), palette, legend, and margin-box layout, but has its own
    render path because the padding changes the angle math.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.POLAR_BAR")
    var max_v = _require_some_positive(plot.y_data, "Mark.POLAR_BAR")

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend = _legend_layout(
        plot.x_categories,
        sc.legend_swatch_size,
        sc,
        theme,
        ox1 - ox0,
        cache=cache,
    ) if show_legend else _LegendLayout()

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = (
        Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    )

    var palette = default_categorical_palette()
    var n = len(plot.x_categories)
    var slot = 2.0 * pi / Float64(n)
    var gap = slot * plot._mark_style.polar_bar_padding
    var slot_start = -pi / 2.0
    for i in range(n):
        var start = slot_start + gap / 2.0
        var end = slot_start + slot - gap / 2.0
        var radius = max_radius * (plot.y_data[i] / max_v)
        var color = palette[i % len(palette)]
        target.fill_arc_aa(cx, cy, radius, start, end, color)
        slot_start += slot

    if show_legend:
        _draw_legend_at(
            target,
            text_requests,
            plot.x_categories,
            palette,
            legend,
            plot_x0,
            plot_y0,
            plot_x1,
            plot_y1,
            theme,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def polarbar(
    categories: List[String],
    values: List[Float64],
    padding: Float64 = 0.2,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A circular column chart: `bar()`'s categorical bars bent around a
    circle instead of a straight baseline, trading precise length
    comparison for a compact, radial layout.

    `Mark.POLAR_BAR` over a categorical `x` and continuous `y` (the same
    shape `bar()`/`pie()` take; values must be non-negative, with at least
    one positive). Bars radiate from the center, one equal-width angular
    slot per category, length proportional to `value / max(values)`. See
    `_render_polar_bar` for how this differs from `nightingale()`.

    Args:
        categories: One equal-width angular slot per entry, in the
            given order.
        values: Each bar's length, proportional to `value /
            max(values)`; every value must be non-negative, and at
            least one positive.
        padding: Gap taken out of each bar's angular slot; defaults to
            `0.2`.
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
        from dataviz import polarbar
        from dataviz.plot import save

        def main() raises:
            var months: List[String] = [
                "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
            ]
            var rainfall: List[Float64] = [2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3]

            var c = polarbar(months, rainfall)
            save(c, "docs/src/examples/out_polarbar.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_polar_bar(padding=padding)
        .encode_categorical(x=categories, y=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def polarbar[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    padding: Float64 = 0.2,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`polarbar()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return polarbar(
        categories,
        _materialize_scalar_list(values),
        padding=padding,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
