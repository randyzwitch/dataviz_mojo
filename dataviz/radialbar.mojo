from canvas.color import Color
from std.math import pi

from canvas.vector.draw_target import DrawTarget
from dataviz.plot import _LazyFontCache

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


def _render_radialbar[
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
    """Render a `Mark.RADIALBAR` plot: one concentric ring per category
    (`encode_categorical`'s `x`/`y`, the same shape `Mark.ARC`/
    `POLAR_BAR`/`NIGHTINGALE` take), each value drawn as a
    clockwise-from-12-o'clock arc over a full track circle
    (`theme.radialbar_track_color`), swept to `value / max(values)` of the
    way around. Same normalization as `Mark.POLAR_BAR`: against the data's
    max, with no per-category goal.

    The first category's ring is outermost, each later category nesting
    one ring further in (the "primary metric outermost" convention of
    multi-ring progress widgets). This is the opposite of `Mark.SUNBURST`,
    whose ring order encodes hierarchy depth.
    `plot._mark_style.radialbar_ring_gap_fraction` sets the gap between
    rings as a fraction of each ring's slot.

    Same validation as `POLAR_BAR`: every value non-negative, at least one
    positive.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.RADIALBAR")
    var max_v = _require_some_positive(plot.y_data, "Mark.RADIALBAR")

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
    var ring_slot = max_radius / Float64(n)
    var gap = ring_slot * plot._mark_style.radialbar_ring_gap_fraction
    var start_angle = -pi / 2.0
    for i in range(n):
        var outer = max_radius - ring_slot * Float64(i) - gap / 2.0
        var inner = max_radius - ring_slot * Float64(i + 1) + gap / 2.0
        var color = palette[i % len(palette)]
        target.fill_ring_sector_aa(
            cx,
            cy,
            inner,
            outer,
            start_angle,
            start_angle + 2.0 * pi,
            theme.radialbar_track_color,
        )
        var frac = plot.y_data[i] / max_v
        if frac > 0.0:
            target.fill_ring_sector_aa(
                cx,
                cy,
                inner,
                outer,
                start_angle,
                start_angle + 2.0 * pi * frac,
                color,
            )

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


def radialbar(
    categories: List[String],
    values: List[Float64],
    ring_gap_fraction: Float64 = 0.25,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A radial (multi-ring) progress chart: `bar()`'s categorical bars
    bent into concentric rings, each ring's arc length proportional to
    its value, for a compact multi-category progress display.

    `Mark.RADIALBAR` over the same categorical `x` + continuous `y` shape
    `bar()`/`pie()`/`polarbar()` take (values must be non-negative, with
    at least one positive). Each category becomes a concentric ring, swept
    clockwise from 12 o'clock to `value / max(values)` of the way around a
    track, with the first category's ring outermost. See
    `_render_radialbar` for how this differs from `polarbar()`'s radiating
    bars.

    Args:
        categories: One concentric ring per entry -- the first entry
            drawn outermost.
        values: Each ring's sweep, proportional to `value /
            max(values)`; every value must be non-negative, and at
            least one positive.
        ring_gap_fraction: Gap between rings as a fraction of each ring's slot;
            defaults to `0.25`.
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
        from dataviz import radialbar
        from dataviz.plot import save

        def main() raises:
            var teams: List[String] = ["Platform", "Growth", "Data", "Design"]
            var completion: List[Int] = [92, 78, 45, 60]

            var c = radialbar(teams, completion)
            save(c, "docs/src/examples/out_radialbar.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_radialbar(ring_gap_fraction=ring_gap_fraction)
        .encode_categorical(x=categories, y=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def radialbar[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    ring_gap_fraction: Float64 = 0.25,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`radialbar()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return radialbar(
        categories,
        _materialize_scalar_list(values),
        ring_gap_fraction=ring_gap_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
