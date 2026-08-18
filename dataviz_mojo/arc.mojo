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
    _rendered,
)
from dataviz_mojo.theme import Theme


def _render_arc[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.ARC` plot (a pie chart): one wedge per category
    (`encode_categorical`'s `x`), its angular span proportional to its
    own value (`y`) divided by the total. No x/y axis frame at all
    (no ticks, gridlines, or axis lines) -- a pie chart doesn't have a
    coordinate system the way every other mark here does, so this is a
    fully separate function, not a branch inside `render()`'s own
    continuous or `_render_bar`'s categorical path. Generic over
    `T: DrawTarget`, returning the legend's own labels as
    `_TextRequest`s rather than drawing them -- see `_render_generic`'s
    own docstring for why every render path here works this way.

    `ox0`/`oy0`/`ox1`/`oy1` are `render()`'s own already-resolved outer
    bounds (see `_render_bar`'s own docstring for why this function
    never reads a target's own width/height directly either).

    Wedges start at the 12-o'clock position and proceed clockwise,
    matching the conventional real-world pie chart reading direction
    -- confirmed directly (not assumed) that increasing angle in
    `fill_arc_aa`'s own convention sweeps clockwise on screen, since
    pixel y increases downward: starting at `-pi/2` (pointing toward
    -y, i.e. up) and increasing angle sweeps toward +x (3 o'clock),
    then +y (6 o'clock), then -x (9 o'clock), back to 12 -- clockwise
    exactly as a real clock face reads. `SvgCanvas.fill_arc_aa` draws
    the identical wedge shape through SVG's own arc-path markup, in
    the same y-down coordinate space with no sign flip needed -- see
    its own docstring for why the two conventions already agree.

    Wedge colors reuse `default_categorical_palette()` by category
    index, same as `Plot.encode(color_categories=...)` -- a pie chart
    and a categorical-color scatter plot describing the same data get
    visually consistent colors, not two unrelated defaults.

    Every value must be non-negative (a negative angular span has no
    meaning) and the total must be positive (an all-zero pie has
    nothing to divide 2*pi by) -- both raise a clear error rather than
    silently drawing a degenerate or misleading chart.

    `theme.donut_inner_radius_fraction > 0.0` switches each wedge from
    `target.fill_arc_aa` to `target.fill_ring_sector_aa` -- a donut
    instead of a pie, everything else (angles, colors, legend)
    unchanged; see `Theme`'s own docstring for what the fraction means
    and why it's relative to the outer radius rather than a fixed
    pixel value.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_categorical(): x and y must have the same length"
            " (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var text_requests = List[_TextRequest]()

    for v in plot.y_data:
        if v < 0.0:
            raise Error(
                "Plot: Mark.ARC values must be non-negative (got "
                + String(v)
                + ")"
            )
    var total = 0.0
    for v in plot.y_data:
        total += v
    if total <= 0.0:
        raise Error(
            "Plot: Mark.ARC requires at least one positive value"
            " (all values summed to "
            + String(total)
            + ")"
        )
    if theme.donut_inner_radius_fraction < 0.0 or theme.donut_inner_radius_fraction >= 1.0:
        raise Error(
            "Theme.donut_inner_radius_fraction must be in [0.0, 1.0) (got "
            + String(theme.donut_inner_radius_fraction)
            + ")"
        )

    # Every pixel-sized Theme/module-constant quantity below, scaled
    # once by theme.scale -- see _Scaled's own docstring.
    var sc = _Scaled(theme)

    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(plot.x_categories, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    var is_donut = theme.donut_inner_radius_fraction > 0.0
    var inner_radius = radius * theme.donut_inner_radius_fraction

    var palette = default_categorical_palette()
    var start = -pi / 2.0
    for i in range(len(plot.x_categories)):
        var span = (plot.y_data[i] / total) * 2.0 * pi
        var end = start + span
        var color = palette[i % len(palette)]
        if is_donut:
            target.fill_ring_sector_aa(cx, cy, inner_radius, radius, start, end, color)
        else:
            target.fill_arc_aa(cx, cy, radius, start, end, color)
        start = end

    if show_legend:
        _draw_legend(
            target, text_requests, plot.x_categories, palette, plot_x1 + sc.margin_right, plot_y0, theme
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def pie(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A pie chart -- `Mark.ARC` over a categorical `x` and continuous
    `y` (the same shape `bar()` takes; every value must be
    non-negative, and at least one positive). Pass `theme=Theme(
    donut_inner_radius_fraction=0.55)` (or any value in `[0.0, 1.0)`)
    for a donut instead -- see `Theme`'s own docstring. See this
    module's own docstring for the shared parameters every function
    here takes."""
    return _rendered(
        Plot().mark_arc().encode_categorical(x=categories, y=values),
        theme,
        width,
        height,
        title,
        x_title,
        y_title,
    )
