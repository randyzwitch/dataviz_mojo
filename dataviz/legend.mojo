"""Legends: where they go, how wide they are, and the four kinds that
get drawn.

Split out of `plot.mojo`. A legend is laid out before anything
is drawn, because its width comes off the plot area -- `_legend_layout`
and `_legend_reserve_for` answer "how much room does this chart owe its
legend" so the frame can be sized around the answer.

Four kinds: the categorical swatch column (`_draw_legend`, and
`_draw_legend_at` for marks that place their own), and continuous color
and size ramps, each in a vertical and a horizontal form.
"""

from canvas.color import Color
from canvas.geometry import round_to_int
from canvas.gradient import LinearGradient
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.color_scale import ColorScale
from dataviz.continuous import _PointChannels
from dataviz.legend_position import LegendPosition
from dataviz.mark import Mark
from dataviz.marker import PointShape, _fill_shape_aa
from dataviz.plot import Plot, render
from dataviz.scale import LinearScale, MinMax, _format_tick
from dataviz.text import _Scaled, _TextRequest, _max_label_width, _text_advance
from dataviz.theme import Theme


def _dynamic_legend_width(
    labels: List[String],
    content_width: Int,
    sc: _Scaled,
    *,
    mut cache: FontCache,
) raises -> Int:
    """How wide a legend column needs to be to fit `labels` next to
    `content_width`-wide content (a swatch, a gradient bar, or the widest
    size-legend circle): `content_width` + `label_gap` + the widest label
    (`_max_label_width`) + `margin_buffer`, `max`'d against
    `sc.legend_width` so a column never gets narrower than `Theme`'s
    fixed default. Every call site measures its real label list before
    finalizing `plot_x1`, through the render's shared `cache` (see
    `_max_label_width`).
    """
    return max(
        sc.legend_width,
        content_width
        + sc.label_gap
        + Int(_max_label_width(labels, sc.font_size, cache=cache))
        + sc.margin_buffer,
    )


struct _LegendLayout(Movable):
    """How much room a legend needs and on which edge, plus the packing a
    horizontal one will draw with.

    `left`/`right`/`top`/`bottom` are the inset each edge of the plot
    rect takes; exactly one is non-zero. A mark applies them before layout.

    `entry_widths`/`row_of` are filled only for `TOP`/`BOTTOM`, where
    entries pack into wrapping rows: measuring labels twice (once to size
    the reserve, again to draw) would be both slower and a chance for the
    two to disagree, so the packing decided here is the packing drawn.
    """

    var left: Int
    var right: Int
    var top: Int
    var bottom: Int
    var position: LegendPosition
    var active: Bool
    var entry_widths: List[Int]
    var row_of: List[Int]
    var rows: Int

    def __init__(out self):
        """An inactive layout, reserving nothing -- what a mark uses when
        `Theme.show_legend` is off or it has no legend to draw."""
        self.left = 0
        self.right = 0
        self.top = 0
        self.bottom = 0
        self.position = LegendPosition.RIGHT
        self.active = False
        self.entry_widths = List[Int]()
        self.row_of = List[Int]()
        self.rows = 0


def _legend_layout(
    labels: List[String],
    content_width: Int,
    sc: _Scaled,
    theme: Theme,
    available_width: Int,
    *,
    mut cache: FontCache,
) raises -> _LegendLayout:
    """Size a legend for `theme.legend_position` and say which edge pays.

    A column (`RIGHT`/`LEFT`) uses `_dynamic_legend_width`. A row
    (`TOP`/`BOTTOM`) packs entries left to right, wrapping
    whenever the next one would run past `available_width`, and reserves
    the height those rows need.

    Args:
        labels: The legend's entries, in draw order.
        content_width: Width of one entry's swatch/bar/circle.
        sc: The render's scaled layout metrics.
        theme: Supplies `legend_position`.
        available_width: The plot rect's full width before the legend is
            taken out -- what a horizontal legend wraps against.
        cache: The render's shared font cache, for measuring labels.

    Returns:
        The layout; `active` is False when `labels` is empty.
    """
    var layout = _LegendLayout()
    if len(labels) == 0:
        return layout^
    layout.active = True
    layout.position = theme.legend_position

    if not theme.legend_position.is_horizontal():
        var width = _dynamic_legend_width(
            labels, content_width, sc, cache=cache
        )
        if theme.legend_position == LegendPosition.LEFT:
            layout.left = width
        else:
            layout.right = width
        return layout^

    # A row per entry that fits, wrapping when the next would overrun.
    # One trailing gap per entry rather than between them: the extra gap
    # at a row's end is what keeps the last entry clear of the plot edge.
    var gap = sc.legend_swatch_size + sc.label_gap
    var row = 0
    var used = 0
    for i in range(len(labels)):
        var one: List[String] = [labels[i]]
        var entry = (
            content_width
            + sc.label_gap
            + Int(_max_label_width(one, sc.font_size, cache=cache))
            + gap
        )
        if used > 0 and used + entry > available_width:
            row += 1
            used = 0
        layout.entry_widths.append(entry)
        layout.row_of.append(row)
        used += entry

    layout.rows = row + 1
    var height = (
        layout.rows * (sc.legend_swatch_size + sc.legend_row_gap)
        + sc.margin_buffer
    )
    if theme.legend_position == LegendPosition.TOP:
        layout.top = height
    else:
        layout.bottom = height
    return layout^


def _legend_column_x(
    layout: _LegendLayout, plot_x0: Int, plot_x1: Int, sc: _Scaled
) -> Int:
    """Where a legend *column* starts, given the plot rect it was already
    reserved out of: just past the right edge, or inside the space opened
    on the left.

    Args:
        layout: What reserved the space.
        plot_x0: Final plot rect's left edge.
        plot_x1: Final plot rect's right edge.
        sc: The render's scaled layout metrics.

    Returns:
        The column's left x.
    """
    if layout.left > 0:
        return plot_x0 - layout.left + sc.margin_buffer
    return plot_x1 + sc.margin_right


def _legend_origin_x(
    layout: _LegendLayout, plot_x0: Int, plot_x1: Int, sc: _Scaled
) -> Int:
    """Where a legend starts horizontally: a row begins at the plot's own
    left edge, a column beside it (`_legend_column_x`).

    Args:
        layout: What reserved the space.
        plot_x0: Final plot rect's left edge.
        plot_x1: Final plot rect's right edge.
        sc: The render's scaled layout metrics.

    Returns:
        The legend's left x.
    """
    if layout.position.is_horizontal():
        return plot_x0
    return _legend_column_x(layout, plot_x0, plot_x1, sc)


def _legend_origin_y(
    layout: _LegendLayout,
    plot_y0: Int,
    plot_y1: Int,
    sc: _Scaled,
) -> Int:
    """Where a legend starts vertically: a column at the plot's top, a
    `TOP` row in the band opened above it, a `BOTTOM` row below the
    x-axis labels rather than on top of them (the same clearance
    `_draw_legend_at` gives a categorical row).

    Args:
        layout: What reserved the space.
        plot_y0: Final plot rect's top edge.
        plot_y1: Final plot rect's bottom edge.
        sc: The render's scaled layout metrics.

    Returns:
        The legend's top y.
    """
    if layout.position == LegendPosition.TOP:
        return plot_y0 - layout.top + sc.margin_buffer
    if layout.position == LegendPosition.BOTTOM:
        return plot_y1 + sc.margin_bottom
    return plot_y0


def _draw_legend_at[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    labels: List[String],
    palette: List[Color],
    layout: _LegendLayout,
    plot_x0: Int,
    plot_y0: Int,
    plot_x1: Int,
    plot_y1: Int,
    theme: Theme,
    shapes: List[PointShape] = List[PointShape](),
) raises:
    """Draw `labels` on whichever edge `layout` reserved, against a plot
    rect that already has that reserve taken out of it.

    The column forms hand off to `_draw_legend` unchanged -- `RIGHT` at
    the same origin every mark used before, `LEFT` in the space now
    opened on the other side. The row forms draw here, walking the
    packing `_legend_layout` already decided.

    Args:
        target: The draw target.
        text_requests: Collected label draws, appended to.
        labels: The legend's entries.
        palette: Colors, indexed `i % len(palette)` as the marks were.
        layout: What `_legend_layout` returned for these labels.
        plot_x0: Final plot rect's left edge.
        plot_y0: Final plot rect's top edge.
        plot_x1: Final plot rect's right edge.
        plot_y1: Final plot rect's bottom edge.
        theme: Supplies colors and font.
        shapes: Per-entry `PointShape`s, when the mark draws shapes.
    """
    if not layout.active:
        return
    var sc = _Scaled(theme)

    if not layout.position.is_horizontal():
        var x = _legend_column_x(layout, plot_x0, plot_x1, sc)
        _draw_legend(
            target, text_requests, labels, palette, x, plot_y0, theme, shapes
        )
        return

    var row_height = sc.legend_swatch_size + sc.legend_row_gap
    # TOP sits in the band opened above the plot, below any title.
    # BOTTOM has to clear the x-axis tick labels, which are drawn in
    # `margin_bottom` *below* plot_y1 -- starting at plot_y1 would put
    # the legend straight on top of them.
    var first_row_y = (
        plot_y0 - layout.top + sc.margin_buffer if layout.position
        == LegendPosition.TOP else plot_y1 + sc.margin_bottom
    )

    var x = plot_x0
    var row = 0
    for i in range(len(labels)):
        if layout.row_of[i] != row:
            row = layout.row_of[i]
            x = plot_x0
        var row_y = first_row_y + row * row_height
        var color = palette[i % len(palette)]
        if len(shapes) > 0:
            var radius = sc.legend_swatch_size // 2
            _fill_shape_aa(
                target,
                x + radius,
                row_y + radius,
                radius,
                shapes[i % len(shapes)],
                color,
            )
        else:
            target.fill_rect(
                x, row_y, sc.legend_swatch_size, sc.legend_swatch_size, color
            )
        text_requests.append(
            _TextRequest(
                x + sc.legend_swatch_size + sc.label_gap,
                row_y + sc.legend_swatch_size - 3,
                labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.LEFT,
                theme.font_family,
            )
        )
        x += layout.entry_widths[i]


def _draw_legend[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    labels: List[String],
    palette: List[Color],
    x: Int,
    y: Int,
    theme: Theme,
    shapes: List[PointShape] = List[PointShape](),
) raises:
    """A swatch+label legend, one row per entry in `labels`, starting at
    (x, y) and growing downward; shared by every mark with a categorical
    legend. `palette` is indexed `i % len(palette)`, the same way the
    marks were colored, so a row shows the exact color its category got.

    `shapes`, when non-empty (`_PointChannels.shapes`, for
    `Theme.shape_by_category`), draws each row's `PointShape` in place of
    the color square at the same size and position. Labels are appended
    to `text_requests` rather than drawn; only the swatch is drawn here.
    """
    var sc = _Scaled(theme)
    for i in range(len(labels)):
        var row_y = y + i * (sc.legend_swatch_size + sc.legend_row_gap)
        var color = palette[i % len(palette)]
        if len(shapes) > 0:
            var radius = sc.legend_swatch_size // 2
            _fill_shape_aa(
                target,
                x + radius,
                row_y + radius,
                radius,
                shapes[i % len(shapes)],
                color,
            )
        else:
            target.fill_rect(
                x, row_y, sc.legend_swatch_size, sc.legend_swatch_size, color
            )
        text_requests.append(
            _TextRequest(
                x + sc.legend_swatch_size + sc.label_gap,
                row_y + sc.legend_swatch_size - 3,
                labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.LEFT,
                theme.font_family,
            )
        )


def _continuous_legend_row_height(sc: _Scaled, has_size: Bool) -> Int:
    """How tall one row of horizontal continuous legend is: the tallest
    section it can contain, plus the gap separating it from the plot.

    A size section reserves room for the circle diameter and its label.

    Args:
        sc: The render's scaled layout metrics.
        has_size: Whether a size section will be drawn in this row.

    Returns:
        The height to reserve.
    """
    var bar = max(sc.continuous_legend_bar_width, Int(sc.font_size))
    var circles = (
        2 * round_to_int(sc.size_range_max) + Int(sc.font_size) + sc.label_gap
    )
    var tallest = max(bar, circles) if has_size else bar
    return tallest + sc.legend_row_gap + sc.margin_buffer


def _continuous_legend_labels(
    color_scale: ColorScale, theme: Theme
) -> List[String]:
    """Exactly the labels a continuous color legend will draw: the domain
    max, the domain min, and the center when the scale was centered
    (`Plot.scale_color_center()`).

    One function so the column's *width* is measured from the same
    strings the bar is later labeled with. Each mark used to build its
    own two-label list with `_format_fixed`, while both legend drawers
    write `_format_tick` -- so under a `Theme.y_tick_format` carrying a
    prefix, a suffix or a percent sign the reserved width was measured
    from a string that is not the one drawn. Adding a third label for a
    centered scale would have repeated that divergence in eight places,
    which is reason enough to have one list.

    Args:
        color_scale: The scale the mark colored with.
        theme: Supplies `y_tick_format`, the formatter both drawers use.

    Returns:
        Two labels, or three for a centered scale.
    """
    var labels = List[String]()
    labels.append(_format_tick(color_scale.domain_max, 1, theme.y_tick_format))
    labels.append(_format_tick(color_scale.domain_min, 1, theme.y_tick_format))
    if color_scale.has_center:
        labels.append(_format_tick(color_scale.center, 1, theme.y_tick_format))
    return labels^


def _draw_continuous_color_legend_h[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    color_scale: ColorScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """`_draw_continuous_color_legend` laid out along a row, for
    `LegendPosition.TOP`/`BOTTOM`.

    The bar runs left to right with the domain's low end at the left,
    which is the reading order a horizontal scale already implies -- so
    unlike the vertical form there is no `1.0 - offset` inversion, and
    the stops go into the gradient exactly as `ColorScale` holds them.
    `ColorScale` keeps them sorted by offset (canvas's `_insert_stop`),
    which is what SVG's `<linearGradient>` needs.

    Labels sit inline at either end rather than beside the bar: the
    whole point of a row legend is that it costs height, so a label
    stacked under the bar would spend the height it saved.

    A centered scale (`Plot.scale_color_center()`) gets a tick on the
    bar at the center's offset rather than the third label the vertical
    form draws beside it, for the same reason (#526). The tick carries
    no number; what it says is that the neutral color is here.

    Args:
        target: The draw target.
        text_requests: Collected label draws, appended to.
        color_scale: The scale whose stops and domain are shown.
        x: Section's left edge.
        y: Section's top edge.
        theme: Supplies colors and font.

    Returns:
        The x just past this section, where the next one starts.
    """
    var sc = _Scaled(theme)
    var bar_length = sc.continuous_legend_bar_height
    var bar_thickness = sc.continuous_legend_bar_width
    var baseline = (
        y + bar_thickness - max(0, (bar_thickness - Int(sc.font_size)) // 2)
    )

    var low = _format_tick(color_scale.domain_min, 1, theme.y_tick_format)
    var high = _format_tick(color_scale.domain_max, 1, theme.y_tick_format)

    # Low label, then the bar, then the high label.
    text_requests.append(
        _TextRequest(
            x,
            baseline,
            low,
            theme.text_color,
            sc.font_size,
            TextAlign.LEFT,
            theme.font_family,
        )
    )
    var bar_x = x + _text_advance(low, sc) + sc.label_gap
    var gradient = LinearGradient(
        Float64(bar_x), Float64(y), Float64(bar_x + bar_length), Float64(y)
    )
    for stop in color_scale.stops:
        gradient.add_stop(stop.offset, stop.color)
    target.fill_rect_gradient(bar_x, y, bar_length, bar_thickness, gradient)

    # A centered ramp needs its neutral point marked: with asymmetric
    # arms the two end labels no longer say where it sits (#526). A tick
    # on the bar rather than a label under it, because a row legend
    # exists to cost no height and a label would spend exactly what it
    # saved. No text, so it says "the neutral color is here" without
    # saying which number -- enough while the centered value is almost
    # always zero. `_continuous_legend_labels` still returns the third
    # string, so a labeled variant needs no new plumbing.
    if color_scale.has_center:
        var span = color_scale.domain_max - color_scale.domain_min
        if span != 0.0:
            # Low at the left here, so no `1.0 - t` inversion; the
            # vertical form needs one because its bar runs high at top.
            var t = (color_scale.center - color_scale.domain_min) / span
            var tick_w = max(1, round_to_int(sc.line_width))
            var center_x = bar_x + Int(t * Float64(bar_length))
            # Skip a tick that would sit on the bar's own edge, where it
            # reads as a border rather than as a mark. The vertical form
            # guards the same case with a font-size clearance, because
            # what it places there is a label; a tick needs only its own
            # width.
            if (
                center_x - bar_x >= tick_w
                and bar_x + bar_length - center_x >= tick_w
            ):
                target.fill_rect(
                    center_x - tick_w // 2,
                    y,
                    tick_w,
                    bar_thickness,
                    theme.text_color,
                )

    var high_x = bar_x + bar_length + sc.label_gap
    text_requests.append(
        _TextRequest(
            high_x,
            baseline,
            high,
            theme.text_color,
            sc.font_size,
            TextAlign.LEFT,
            theme.font_family,
        )
    )
    return high_x + _text_advance(high, sc) + sc.legend_swatch_size


def _draw_continuous_size_legend_h[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    size_mm: MinMax,
    size_scale: LinearScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """`_draw_continuous_size_legend` laid out along a row, for
    `LegendPosition.TOP`/`BOTTOM`: the same three sample circles
    (min, midpoint, max) side by side with each label under its own
    circle's center rather than beside it.

    Args:
        target: The draw target.
        text_requests: Collected label draws, appended to.
        size_mm: The size channel's domain.
        size_scale: Value to radius.
        x: Section's left edge.
        y: Section's top edge.
        theme: Supplies colors and font.

    Returns:
        The x just past this section.
    """
    var sc = _Scaled(theme)
    var max_radius = round_to_int(sc.size_range_max)
    var cursor = x
    var values = List[Float64]()
    values.append(size_mm.min)
    values.append((size_mm.min + size_mm.max) / 2.0)
    values.append(size_mm.max)

    for i in range(len(values)):
        var value = values[i]
        var radius = round_to_int(size_scale.to_pixel(value))
        var center_x = cursor + max_radius
        var center_y = y + max_radius
        target.fill_circle_aa(center_x, center_y, radius, theme.mark_color)
        text_requests.append(
            _TextRequest(
                center_x,
                center_y + max_radius + Int(sc.font_size),
                _format_tick(value, 1, theme.y_tick_format),
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )
        cursor = center_x + max_radius + sc.label_gap
    return cursor


def _draw_continuous_color_legend[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    color_scale: ColorScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """A continuous color legend: a vertical gradient bar
    (`DrawTarget.fill_rect_gradient`) with `color_scale`'s high value at
    the top and low at the bottom, plus two labels (`_format_tick` at
    `theme.y_tick_format`, one decimal place) for the domain max at the
    top and min at the bottom.

    The `LinearGradient` is built from `color_scale.stops` directly. The
    bar runs top to bottom while the scale's offsets run low to high, so
    each stop's gradient offset is `1.0 - stop.offset`; the stops are
    then sorted back into ascending order (see the body's comment).

    A third label is drawn beside the bar at `color_scale.center` when
    the scale was centered (`Plot.scale_color_center()`). With
    asymmetric arms the two end labels no longer say where the ramp's
    neutral color sits, and that value is the one the chart was centered
    on -- so leaving it off would hide the very thing the caller asked
    for. It is suppressed when it would land within one font-size of
    either end label, since two overlapping numbers say less than one.

    Only the vertical legend does this. The row form
    (`_draw_continuous_color_legend_h`) puts its labels inline at the
    two ends precisely so the legend costs no height; a center label
    there would have to sit above or below the bar and spend the height
    the row layout exists to save.

    Returns the y just below this section (bar height plus one row gap),
    where `_draw_continuous_size_legend` starts when a plot combines
    both.
    """
    var sc = _Scaled(theme)
    var bar_width = sc.continuous_legend_bar_width
    var bar_height = sc.continuous_legend_bar_height
    var gradient = LinearGradient(
        Float64(x), Float64(y), Float64(x), Float64(y + bar_height)
    )

    # Stops are emitted in ascending offset order, which SVG requires (the
    # raster backend doesn't care). SVG's <linearGradient> clamps each
    # <stop>'s offset to be no less than the previous one's, so emitting
    # `1.0 - offset` off an ascending ColorScale (1.0, 0.5, 0.0) collapsed
    # every stop after the first onto 1.0 and the bar rendered as one flat
    # color; the raster path was always correct because `_color_at_t`
    # scans for the bracketing pair regardless of order. Sorted rather
    # than iterated backwards because `ColorScale.add_stop` accepts stops
    # in any order. Insertion sort, since the list is three stops long.
    var offsets = List[Float64](capacity=len(color_scale.stops))
    var colors = List[Color](capacity=len(color_scale.stops))
    for stop in color_scale.stops:
        offsets.append(1.0 - stop.offset)
        colors.append(stop.color)
    for a in range(1, len(offsets)):
        var key_offset = offsets[a]
        var key_color = colors[a]
        var b = a - 1
        while b >= 0 and offsets[b] > key_offset:
            offsets[b + 1] = offsets[b]
            colors[b + 1] = colors[b]
            b -= 1
        offsets[b + 1] = key_offset
        colors[b + 1] = key_color
    for i in range(len(offsets)):
        gradient.add_stop(offsets[i], colors[i])

    target.fill_rect_gradient(x, y, bar_width, bar_height, gradient)

    var label_baseline_offset = Int(sc.font_size * 0.35)
    text_requests.append(
        _TextRequest(
            x + bar_width + sc.label_gap,
            y + label_baseline_offset,
            _format_tick(color_scale.domain_max, 1, theme.y_tick_format),
            theme.text_color,
            sc.font_size,
            TextAlign.LEFT,
            theme.font_family,
        )
    )
    text_requests.append(
        _TextRequest(
            x + bar_width + sc.label_gap,
            y + bar_height + label_baseline_offset,
            _format_tick(color_scale.domain_min, 1, theme.y_tick_format),
            theme.text_color,
            sc.font_size,
            TextAlign.LEFT,
            theme.font_family,
        )
    )

    if color_scale.has_center:
        var span = color_scale.domain_max - color_scale.domain_min
        if span != 0.0:
            var t = (color_scale.center - color_scale.domain_min) / span
            # The bar runs high at the top, so the center's distance from
            # the top edge is 1 - t, matching the 1 - offset inversion
            # the gradient stops go through above.
            var center_y = y + Int((1.0 - t) * Float64(bar_height))
            var clearance = Int(sc.font_size)
            if (
                center_y - y >= clearance
                and y + bar_height - center_y >= clearance
            ):
                text_requests.append(
                    _TextRequest(
                        x + bar_width + sc.label_gap,
                        center_y + label_baseline_offset,
                        _format_tick(
                            color_scale.center, 1, theme.y_tick_format
                        ),
                        theme.text_color,
                        sc.font_size,
                        TextAlign.LEFT,
                        theme.font_family,
                    )
                )
    return y + bar_height + sc.legend_row_gap


def _draw_continuous_size_legend[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    size_mm: MinMax,
    size_scale: LinearScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """A continuous size legend: three circles at the max, midpoint, and min
    of the size domain (evenly spaced values, not radii), each at
    `size_scale`'s radius for that value. Circles are left-aligned on
    their widest possible edge (`x + sc.size_range_max`) so every label
    lines up at the same x.

    Returns the y just below the last circle plus one row gap, for
    consistency with `_draw_continuous_color_legend`; currently the last
    legend section drawn.
    """
    var sc = _Scaled(theme)
    var values = List[Float64]()
    values.append(size_mm.max)
    values.append((size_mm.min + size_mm.max) / 2.0)
    values.append(size_mm.min)

    var label_baseline_offset = Int(sc.font_size * 0.35)
    var cx = x + round_to_int(sc.size_range_max)
    var top_y = y
    for v in values:
        var radius = round_to_int(size_scale.to_pixel(v))
        var center_y = top_y + radius
        target.fill_circle_aa(cx, center_y, radius, theme.mark_color)
        text_requests.append(
            _TextRequest(
                cx + radius + sc.label_gap,
                center_y + label_baseline_offset,
                _format_tick(v, 1, theme.y_tick_format),
                theme.text_color,
                sc.font_size,
                TextAlign.LEFT,
                theme.font_family,
            )
        )
        top_y = center_y + radius + sc.legend_row_gap
    return top_y


def _levels_descending(levels: List[Float64]) -> List[Float64]:
    """`levels` sorted high to low, for a level legend's row order.

    A contour's key reads top-down like the colorbar beside a heatmap
    does: the highest band first. The caller's own `levels` order is
    whatever it was given or computed and carries no display meaning,
    so the legend imposes one.

    Args:
        levels: The contour levels, in any order.

    Returns:
        A sorted copy, descending.
    """
    var out = levels.copy()
    for i in range(len(out)):
        for j in range(i + 1, len(out)):
            if out[j] > out[i]:
                var t = out[i]
                out[i] = out[j]
                out[j] = t
    return out^


def _legend_reserve_for(
    plot: Plot, ch: _PointChannels, sc: _Scaled, *, mut cache: FontCache
) raises -> _LegendLayout:
    """How much room `plot`'s point-mark legend needs and on which edge,
    or an inactive layout when it has no legend (`Theme.show_legend` off,
    not a point mark, or no data-driven channel). A plot combining
    continuous color and size stacks both sections vertically in one
    column, so the width is the larger of the two, not the sum. Called
    before the plot rect is finalized, measuring through the render's
    shared `cache` (see `_max_label_width`).

    Honors all four positions. `TOP`/`BOTTOM` reserve a row's height
    rather than a column's width and the sections draw along it
    (`_draw_continuous_color_legend_h`/`_draw_continuous_size_legend_h`),
    so a point mark's legend behaves the same way a categorical one does.
    A plot combining color and size stacks them in a column and lays them
    side by side in a row, which is why the row's height is one section's
    and not two.
    """
    var layout = _LegendLayout()
    if not plot._theme.show_legend:
        return layout^
    if not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.SINGLE_AXIS
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        return layout^
    if not (ch.has_color_categories or ch.has_color or ch.has_size):
        return layout^

    var reserve = 0
    if ch.has_color_categories:
        reserve = max(
            reserve,
            _dynamic_legend_width(
                ch.cat.domain, sc.legend_swatch_size, sc, cache=cache
            ),
        )
    elif ch.has_color:
        var color_labels = _continuous_legend_labels(
            ch.color_scale, plot._theme
        )
        reserve = max(
            reserve,
            _dynamic_legend_width(
                color_labels, sc.continuous_legend_bar_width, sc, cache=cache
            ),
        )
    if ch.has_size:
        var size_labels = List[String]()
        size_labels.append(
            _format_tick(ch.size_mm.max, 1, plot._theme.y_tick_format)
        )
        size_labels.append(
            _format_tick(
                (ch.size_mm.min + ch.size_mm.max) / 2.0,
                1,
                plot._theme.y_tick_format,
            )
        )
        size_labels.append(
            _format_tick(ch.size_mm.min, 1, plot._theme.y_tick_format)
        )
        var circle_content_width = 2 * round_to_int(sc.size_range_max)
        reserve = max(
            reserve,
            _dynamic_legend_width(
                size_labels, circle_content_width, sc, cache=cache
            ),
        )

    layout.active = True
    layout.position = plot._theme.legend_position
    if plot._theme.legend_position == LegendPosition.TOP:
        layout.top = _continuous_legend_row_height(sc, ch.has_size)
    elif plot._theme.legend_position == LegendPosition.BOTTOM:
        layout.bottom = _continuous_legend_row_height(sc, ch.has_size)
    elif plot._theme.legend_position == LegendPosition.LEFT:
        layout.left = reserve
    else:
        layout.right = reserve
    return layout^
