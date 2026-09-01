from std.math import pi

from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.mark import Mark
from dataviz.plot import (
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
)
from dataviz.theme import Theme


def _render_arc[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.ARC` plot (a pie chart): one wedge per category
    (`encode_categorical`'s `x`), its angular span proportional to its value (`y`) divided by the total. No x/y axis frame at all
    (no ticks, gridlines, or axis lines) -- a pie chart doesn't have a
    coordinate system the way every other mark here does, so this is
    its own function. Generic over
    `T: DrawTarget`, returning the legend's labels as
    `_TextRequest`s rather than drawing them -- see `_render_generic`'s docstring for why every render path here works this way.

    `ox0`/`oy0`/`ox1`/`oy1` are `render()`'s already-resolved outer
    bounds (see `_render_bar`'s docstring for why this function
    never reads a target's width/height directly either).

    Wedges start at the 12-o'clock position and proceed clockwise,
    matching the conventional real-world pie chart reading direction.
    Increasing angle in `fill_arc_aa`'s convention sweeps clockwise on
    screen, since pixel y increases downward: starting at `-pi/2`
    (pointing toward
    -y, i.e. up) and increasing angle sweeps toward +x (3 o'clock),
    then +y (6 o'clock), then -x (9 o'clock), back to 12 -- clockwise
    exactly as a real clock face reads. `SvgCanvas.fill_arc_aa` draws
    the identical wedge shape through SVG's arc-path markup, in
    the same y-down coordinate space with no sign flip needed -- see
    its docstring for why the two conventions already agree.

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
    unchanged; see `Theme`'s docstring for what the fraction means
    and why it's relative to the outer radius rather than a fixed
    pixel value.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.ARC")
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
    # once by theme.scale -- see _Scaled's docstring.
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
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A pie chart -- `Mark.ARC` over a categorical `x` and continuous
    `y` (the same shape `bar()` takes; every value must be
    non-negative, and at least one positive). Pass `theme=Theme(
    donut_inner_radius_fraction=0.55)` (or any value in `[0.0, 1.0)`)
    for a donut instead -- see `Theme`'s docstring.

    Args:
        categories: One wedge per entry, in the given order.
        values: Each category's share; every value must be
            non-negative, and at least one positive.
        theme: Full styling knobs beyond this function's own
            parameters, including `donut_inner_radius_fraction` for
            a donut -- see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: Unused -- a pie chart has no x-axis to label.
        y_title: Unused -- a pie chart has no y-axis to label.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import pie
        from dataviz.plot import save

        def main() raises:
            var browsers: List[String] = ["Chrome", "Safari", "Edge", "Firefox", "Other"]
            var share: List[Int] = [65, 18, 5, 7, 5]

            var c = pie(browsers, share, width=400, height=300)
            save(c, "docs/src/examples/out_pie.svg")
        ```

    Example (Donut (donut_inner_radius_fraction)):
        ```mojo
        from dataviz import pie
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var browsers: List[String] = ["Chrome", "Safari", "Edge", "Firefox", "Other"]
            var share: List[Int] = [65, 18, 5, 7, 5]

            var c_donut = pie(
                browsers,
                share,
                theme=Theme(donut_inner_radius_fraction=0.55),
                width=400,
                height=300,
            )
            save(c_donut, "docs/src/examples/out_pie_donut.svg")
        ```
    """
    var plot = Plot().mark_arc().encode_categorical(x=categories, y=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def pie[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`pie()`, generalized over numeric element type -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `pie()` above.
    """
    return pie(
        categories, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
