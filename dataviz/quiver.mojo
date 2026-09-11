"""`Mark.QUIVER` and `quiver()`: a vector field as arrows -- one per
sample point, pointing along `(u, v)` with a length proportional to
the magnitude. The general form of `Mark.BARBS`, which draws the same
field in the meteorologist's station notation."""

from std.math import sqrt

from canvas.fill_rule import FillRule
from canvas.geometry import round_to_int
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.arrow import (
    _ARROW_HEAD_HALF_WIDTH,
    _ARROW_HEAD_LENGTH,
    _arrow_head_path,
)
from dataviz.barbs import _validate_vector_field
from dataviz.color_scale import ColorScale, _color_scale_for
from dataviz.legend import (
    _continuous_legend_labels,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
)
from dataviz.plot import (
    Plot,
    _LegendLayout,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
)
from dataviz.scale import LinearScale
from dataviz.text import _Scaled
from dataviz.theme import Theme


comptime _AUTO_SCALE_DIVISOR = 1.8
"""matplotlib's constant in its `quiver` autoscale: an arrow of the mean
magnitude is drawn `plot width / (1.8 * max(10, sqrt(N)))` long, so a
field of N arrows on a grid fills its cells without crossing them."""


def _auto_pixels_per_unit(
    u: List[Float64], v: List[Float64], plot_width_px: Float64
) -> Float64:
    """Pixels per unit of magnitude when `scale` is left at 0: the rule
    the module constant describes. A field of zero vectors gets 1.0,
    which draws nothing either way.
    """
    var n = len(u)
    var total = 0.0
    for i in range(n):
        total += sqrt(u[i] * u[i] + v[i] * v[i])
    if total <= 0.0:
        return 1.0
    var mean = total / Float64(n)
    var sn = max(10.0, sqrt(Float64(n)))
    return plot_width_px / (_AUTO_SCALE_DIVISOR * sn * mean)


def _draw_quiver_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: LinearScale,
    y_scale: LinearScale,
    sc: _Scaled,
    pixels_per_unit: Float64,
    color_scale: ColorScale,
    color_by_magnitude: Bool,
) raises:
    """Draw one `Mark.QUIVER` plot's arrows into an already-laid-out
    continuous axis frame: a shaft from the sample point and a filled
    head at the tip, both in the mark color, or in the magnitude's
    color through `color_scale` when `color_by_magnitude`.

    The head is theme-sized (`_ARROW_HEAD_LENGTH`), never scaled to the
    shaft, so a short arrow does not get an oversized head; an arrow
    shorter than a head is drawn as a head shortened to its length,
    which keeps the direction readable down to a few pixels. A zero
    vector draws nothing. The shaft stops at the head's base so the
    antialiased stroke does not darken the head's centerline.

    `v` is positive up the page and pixel y grows downward, so the
    pixel direction is `(u, -v)`.
    """
    var n = len(plot._barbs.x)
    var theme = plot._theme
    var head_len = _ARROW_HEAD_LENGTH * sc.scale
    var head_half = _ARROW_HEAD_HALF_WIDTH * sc.scale
    var width = sc.line_width
    for i in range(n):
        var u = plot._barbs.u[i]
        var v = plot._barbs.v[i]
        var mag = sqrt(u * u + v * v)
        if mag <= 0.0:
            continue
        var px = x_scale.to_pixel(plot._barbs.x[i])
        var py = y_scale.to_pixel(plot._barbs.y[i])
        var ux = u / mag
        var uy = -v / mag
        var length = mag * pixels_per_unit
        var tip_x = px + ux * length
        var tip_y = py + uy * length
        var color = theme.mark_color
        if color_by_magnitude:
            color = color_scale.color_at(mag)
        var this_head = min(head_len, length)
        var this_half = head_half * (this_head / head_len)
        if length > head_len:
            target.draw_line_aa(
                px,
                py,
                tip_x - ux * head_len,
                tip_y - uy * head_len,
                color,
                width=width,
            )
        target.fill_path_aa(
            _arrow_head_path(tip_x, tip_y, ux, uy, this_head, this_half),
            color,
            fill_rule=FillRule.NONZERO,
        )


def _render_quiver[
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
    """Render a `Mark.QUIVER` plot: `encode_quiver()`'s continuous `x`/`y`
    positions on a continuous frame, one arrow per point along `(u, v)`.
    `_render_barbs`'s counterpart over the same data.

    With `mark_quiver(color_by_magnitude=True)` the arrows take their
    color from the theme's ramp over `[0, max magnitude]` and a color
    legend is laid out beside the plot, as `Mark.HEXBIN` lays out its
    count legend.

    Args:
        target: Where to draw.
        plot: The chart, whose `_barbs` data this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: Mismatched channel lengths, empty data, or a negative
            scale.
    """
    _validate_vector_field(plot, "Plot.encode_quiver()")
    if plot._quiver_scale < 0.0:
        raise Error(
            "Plot.mark_quiver(): scale must be 0 (automatic) or positive (got "
            + String(plot._quiver_scale)
            + ")"
        )
    var theme = plot._theme
    var sc = _Scaled(theme)
    var top = 0.0
    for i in range(len(plot._barbs.u)):
        var u = plot._barbs.u[i]
        var v = plot._barbs.v[i]
        top = max(top, sqrt(u * u + v * v))
    var color_scale = _color_scale_for(theme, plot._color_domain, 0.0, top)

    var legend = _LegendLayout()
    if theme.show_legend and plot._quiver_color_by_magnitude:
        var legend_labels = _continuous_legend_labels(color_scale, theme)
        legend.right = _dynamic_legend_width(
            legend_labels,
            sc.continuous_legend_bar_width,
            sc,
            cache=cache,
        )
        legend.active = True

    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(plot._barbs.x),
        _data_extent(plot._barbs.y),
        theme,
        legend,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    var pixels_per_unit = plot._quiver_scale * sc.scale
    if plot._quiver_scale == 0.0:
        pixels_per_unit = _auto_pixels_per_unit(
            plot._barbs.u,
            plot._barbs.v,
            abs(frame.x_scale.range_max - frame.x_scale.range_min),
        )
    _draw_quiver_layer(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        frame.sc,
        pixels_per_unit,
        color_scale,
        plot._quiver_color_by_magnitude,
    )
    if legend.active:
        _ = _draw_continuous_color_legend(
            target,
            frame.text_requests,
            color_scale,
            round_to_int(frame.x_scale.range_max) + sc.margin_right,
            frame.py0,
            theme,
        )
    return frame.result()


def quiver(
    x: List[Float64],
    y: List[Float64],
    u: List[Float64],
    v: List[Float64],
    scale: Float64 = 0.0,
    color_by_magnitude: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A vector field as arrows, matplotlib's `quiver()`: one arrow per
    `(x, y)` sample, pointing along `(u, v)` with a length proportional
    to the magnitude and a filled head at the tip.

    The general form of `barbs()`. Wind barbs are a specialist notation
    -- speed read from flags in 5-knot steps, staff pointing upwind --
    that assumes a meteorologist is reading. An arrow's length and
    direction show the vector directly, which is what a gradient, a
    flow, a force or a displacement field wants.

    `scale` is pixels per unit of magnitude, before `Theme.scale`, so
    `scale=2.0` draws a vector of magnitude 10 as a 20-pixel arrow. At
    the default of 0 it is chosen from the data, by matplotlib's rule:
    an arrow of the mean magnitude is drawn `plot width / (1.8 *
    max(10, sqrt(N)))` long, so a field of N arrows on a grid fills its
    cells without crossing them. Set it explicitly to compare two
    fields on the same footing, since the automatic value depends on
    each field's own mean.

    The head is theme-sized, never scaled to the shaft, so short arrows
    do not get oversized heads; an arrow shorter than a head is drawn
    as a head shortened to its length. A zero vector draws nothing.

    `color_by_magnitude` colors each arrow through the theme's ramp
    from zero to the longest vector, with a color legend beside the
    plot -- how a dense field is usually made readable, since arrow
    length alone is hard to compare across a crowded chart.

    Args:
        x: The continuous x position of each arrow's tail.
        y: The continuous y position of each arrow's tail.
        u: Each vector's x-component, in the same unit as `v`.
        v: Each vector's y-component, positive pointing up the page.
        scale: Pixels per unit of magnitude, or 0 for automatic.
        color_by_magnitude: Color arrows by `hypot(u, v)` through the
            theme's ramp, with a legend.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: Channel lengths differ, the data is empty, or `scale` is
            negative.

    Example:
        ```mojo
        from std.math import cos, sin

        from dataviz import quiver, save
        from dataviz import Theme
        from dataviz.colormaps import viridis

        def main() raises:
            # A circulating flow around the center with a steady drift
            # to the right -- the field a rectangular sampling grid
            # shows as arrows curling around a hub.
            var xs = List[Float64]()
            var ys = List[Float64]()
            var us = List[Float64]()
            var vs = List[Float64]()
            for j in range(12):
                for i in range(16):
                    var x = Float64(i) - 7.5
                    var y = Float64(j) - 5.5
                    xs.append(x)
                    ys.append(y)
                    us.append(-y * 0.4 + 1.0)
                    vs.append(x * 0.4)
            var chart = quiver(
                xs,
                ys,
                us,
                vs,
                color_by_magnitude=True,
                theme=Theme(color_ramp=viridis()),
                title="Illustrative Flow Around a Hub",
                x_title="x",
                y_title="y",
            )
            save(chart, "docs/src/examples/out_quiver.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_quiver(scale=scale, color_by_magnitude=color_by_magnitude)
        .encode_quiver(x, y, u, v)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def quiver[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    u: List[Scalar[dtype]],
    v: List[Scalar[dtype]],
    scale: Float64 = 0.0,
    color_by_magnitude: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`quiver()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.

    Parameters:
        dtype: The element type of `x`, `y`, `u` and `v`.

    Args:
        x: The continuous x position of each arrow's tail.
        y: The continuous y position of each arrow's tail.
        u: Each vector's x-component.
        v: Each vector's y-component, positive pointing up the page.
        scale: Pixels per unit of magnitude, or 0 for automatic.
        color_by_magnitude: Color arrows by magnitude, with a legend.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: As the concrete overload.
    """
    return quiver(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        _materialize_scalar_list(u),
        _materialize_scalar_list(v),
        scale=scale,
        color_by_magnitude=color_by_magnitude,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
