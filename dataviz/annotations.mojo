"""The `annotate_*()` overlays: their stored data, their validation, and
the six passes that draw them.

Split out of `plot.mojo`. This is the most self-contained seam in
that file: `Plot` holds an `_AnnotationData` and calls these six passes,
and nothing else in the package touches them.

Every pass takes the finished `_RenderResult` and draws into the same
frame the marks used, so an annotation lands on the plot's own scales
rather than on a layout of its own. Each returns its labels as
`_TextRequest`s rather than drawing them, because text is replayed after
every pass so a label is never painted over.

Which overlay snaps to the pixel grid, and why, is in the individual
docstrings -- the short version is that a shaded band is a filled rect
and snaps both edges, a reference line is a hairline and snaps its one
fixed coordinate, and a fitted line is a diagonal that snaps nothing.
"""

from std.math import sqrt

from canvas.fill_rule import FillRule
from canvas.geometry import round_to_int
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign, measure_text
from canvas.vector.draw_target import DrawTarget

from dataviz.pixel_snap import _snap_pixel_center, _snap_pixel_edge
from dataviz.scale import _format_fixed
from dataviz.stats import _OlsFit, _ols_fit
from dataviz.theme import Theme

# Circular by construction, and resolved within the package: `plot.mojo`
# imports the six passes back. `_AnnotationData` moved here with them
# because it is theirs -- `Plot` only stores it.
from dataviz.plot import (
    Plot,
    _CategoricalFrame,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel_f,
)


struct _AnnotationData(Copyable, Movable):
    """Annotations, stored on `Plot._annotations`. Each `annotate_*()` method
    appends rather than replaces, so the parallel lists hold one entry
    per call: `line_*` is a horizontal reference line per (value, label)
    from `.annotate_line()`; `area_*` a shaded band per (y0, y1, label)
    from `.annotate_area()`; `vline_*` a vertical line per (value, label)
    from `.annotate_vline()`; `point_*` a labeled point per (x, y, label)
    from `.annotate_point()`; `arrow_*` an arrow per (target x/y, label
    x/y, text) from `.annotate_arrow()`. `line_*` and `vline_*` stay
    separate lists rather than sharing one with an axis flag.

    `band_*` is one filled region per `.annotate_band()` call, and each
    entry's `x`/`y_lower`/`y_upper` is itself a full series (a curve), so
    the outer list is one level deeper: `band_x[k]` is the k-th band's x
    column.

    `best_fit*` is a single opt-in request to compute a line from this
    `Plot`'s own `x_data`/`y_data` (see `annotate_best_fit()`), plus its
    display options: a `Bool` flag like `_secondary_axis`/`_y_log`, not
    repeatable data.
    """

    var line_values: List[Float64]
    var line_labels: List[String]
    var area_y0: List[Float64]
    var area_y1: List[Float64]
    var area_labels: List[String]
    var vline_values: List[Float64]
    var vline_labels: List[String]
    var point_x: List[Float64]
    var point_y: List[Float64]
    var point_labels: List[String]
    var band_x: List[List[Float64]]
    var band_y_lower: List[List[Float64]]
    var band_y_upper: List[List[Float64]]
    var band_labels: List[String]
    var arrow_x: List[Float64]
    var arrow_y: List[Float64]
    var arrow_text_x: List[Float64]
    var arrow_text_y: List[Float64]
    var arrow_labels: List[String]
    var best_fit: Bool
    var best_fit_show_equation: Bool
    var best_fit_show_r_squared: Bool
    var best_fit_label: String
    var best_fit_ci: Float64
    """Two-sided confidence level of the band around the fitted line
    (`0.95` for 95%); `0.0` draws no band."""

    def __init__(out self):
        self.line_values = List[Float64]()
        self.line_labels = List[String]()
        self.area_y0 = List[Float64]()
        self.area_y1 = List[Float64]()
        self.area_labels = List[String]()
        self.vline_values = List[Float64]()
        self.vline_labels = List[String]()
        self.point_x = List[Float64]()
        self.point_y = List[Float64]()
        self.point_labels = List[String]()
        self.band_x = List[List[Float64]]()
        self.band_y_lower = List[List[Float64]]()
        self.band_y_upper = List[List[Float64]]()
        self.band_labels = List[String]()
        self.arrow_x = List[Float64]()
        self.arrow_y = List[Float64]()
        self.arrow_text_x = List[Float64]()
        self.arrow_text_y = List[Float64]()
        self.arrow_labels = List[String]()
        self.best_fit = False
        self.best_fit_show_equation = False
        self.best_fit_show_r_squared = False
        self.best_fit_label = ""
        self.best_fit_ci = 0.0


def _draw_annotation_areas[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_area()` shaded band directly (a `fill_rect`
    needs no text machinery) and return each one's optional label as a
    `_TextRequest`.

    Called by `_render_into`/`_render_svg_into` right after
    `_render_generic`, before `_draw_annotation_lines`, since areas are
    the bottom-most annotation layer. Uses `result.y_scale`, raising if
    `has_y_scale` is `False`.

    Each band spans the inner plot rect's full width in
    `Theme.annotation_area_color` (translucent, so the mark shows
    through). Its label draws inside the band near its top edge in
    `Theme.annotation_color`. A band partially outside the y-domain draws
    its clipped visible portion; one with zero overlap draws nothing.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.area_y0) == 0:
        return text_requests^
    if not result.has_y_scale:
        raise Error(
            "Plot.annotate_area(): this mark has no continuous y-axis to place"
            " a shaded band"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER and"
            " every mark sharing"
            " _CategoricalFrame"
            " (BAR/LOLLIPOP/WATERFALL/BOX/CANDLESTICK/BULLET/GROUPED_BAR/"
            "STACKED_BAR/STREAMGRAPH)"
        )

    var sc = _Scaled(theme)
    var plot_top = min(result.py0, result.py1)
    var plot_bottom = max(result.py0, result.py1)
    # The plot rect arrives as pixel indices, so its geometric extent
    # runs from half a pixel above the first row to half a pixel below
    # the last -- clipping against the indices themselves would land a
    # band edge on a pixel center, and the nearest boundary to that is a
    # coin flip that can cost a whole row.
    var clip_top = Float64(plot_top) - 0.5
    var clip_bottom = Float64(plot_bottom) + 0.5
    for i in range(len(plot._annotations.area_y0)):
        # A shaded band is an axis-aligned filled rect, so both edges
        # snap to pixel boundaries: it keeps hard edges, and its height
        # comes from the snapped pair rather than from a rounded height
        # laid off a rounded top.
        var py_a = _snap_pixel_edge(
            _axis_pixel_f(result.y_scale, plot._annotations.area_y0[i])
        )
        var py_b = _snap_pixel_edge(
            _axis_pixel_f(result.y_scale, plot._annotations.area_y1[i])
        )
        var band_top = min(py_a, py_b)
        var band_bottom = max(py_a, py_b)
        # Clip to the visible plot rect rather than skip outright; a band has
        # real height, so a partial overlap is still meaningful.
        var draw_top = max(band_top, clip_top)
        var draw_bottom = min(band_bottom, clip_bottom)
        if draw_top >= draw_bottom:
            continue
        target.fill_rect(
            Float64(result.px0) - 0.5,
            draw_top,
            Float64(result.px1 - result.px0),
            draw_bottom - draw_top,
            theme.annotation_area_color,
        )
        var label = plot._annotations.area_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    result.px1 - sc.label_gap,
                    round_to_int(draw_top) + Int(sc.font_size),
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.RIGHT,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_bands[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_band()` filled region with the same
    `fill_path_aa` closed-polygon technique `_draw_area_layer` uses,
    built from `y_upper` left-to-right then `y_lower` right-to-left, and
    return each band's optional label as a `_TextRequest`.

    Called right after `_draw_annotation_areas`, as the other
    translucent-fill layer beneath lines/vlines/points. Needs both
    `result.x_scale` and `result.y_scale`. Raises if a band's `x`/
    `y_lower`/`y_upper` lengths mismatch or any `y_upper[i] < y_lower[i]`.

    No true polygon clip against the inner rect: each vertex's pixel
    position is clamped independently into the rect before the path is
    built. A band mostly in range draws correctly; a vertex clamped on
    one axis draws a straight wall at that boundary rather than a true
    intersection. A band with every vertex clamped to one corner fills a
    zero-area region.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.band_x) == 0:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_band(): this mark has no continuous x/y axes to"
            " place a band against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )

    var sc = _Scaled(theme)
    var px_left = Float64(min(result.px0, result.px1))
    var px_right = Float64(max(result.px0, result.px1))
    var py_top = Float64(min(result.py0, result.py1))
    var py_bottom = Float64(max(result.py0, result.py1))
    for k in range(len(plot._annotations.band_x)):
        var xs = plot._annotations.band_x[k].copy()
        var ys_lower = plot._annotations.band_y_lower[k].copy()
        var ys_upper = plot._annotations.band_y_upper[k].copy()
        if len(xs) != len(ys_lower) or len(xs) != len(ys_upper):
            raise Error(
                "Plot.annotate_band(): x/y_lower/y_upper must be the same"
                " length (got "
                + String(len(xs))
                + ", "
                + String(len(ys_lower))
                + ", and "
                + String(len(ys_upper))
                + ")"
            )
        if len(xs) == 0:
            continue
        var px_upper = List[Float64](capacity=len(xs))
        var py_upper = List[Float64](capacity=len(xs))
        var px_lower = List[Float64](capacity=len(xs))
        var py_lower = List[Float64](capacity=len(xs))
        for i in range(len(xs)):
            if ys_upper[i] < ys_lower[i]:
                raise Error(
                    "Plot.annotate_band(): y_upper must be >= y_lower at every"
                    " index (got y_lower="
                    + String(ys_lower[i])
                    + " and y_upper="
                    + String(ys_upper[i])
                    + " at index "
                    + String(i)
                    + ")"
                )
            var this_px = min(
                max(result.x_scale.to_pixel(xs[i]), px_left), px_right
            )
            px_upper.append(this_px)
            px_lower.append(this_px)
            py_upper.append(
                min(
                    max(result.y_scale.to_pixel(ys_upper[i]), py_top), py_bottom
                )
            )
            py_lower.append(
                min(
                    max(result.y_scale.to_pixel(ys_lower[i]), py_top), py_bottom
                )
            )
        var path = Path()
        path.move_to(px_upper[0], py_upper[0])
        for i in range(1, len(xs)):
            path.line_to(px_upper[i], py_upper[i])
        for i in range(len(xs) - 1, -1, -1):
            path.line_to(px_lower[i], py_lower[i])
        path.close()
        target.fill_path_aa(
            path, theme.annotation_area_color, fill_rule=FillRule.NONZERO
        )

        var label = plot._annotations.band_labels[k]
        if label.byte_length() > 0:
            var mid = len(xs) // 2
            text_requests.append(
                _TextRequest(
                    Int(px_upper[mid]),
                    Int(py_upper[mid]) - sc.label_gap,
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_lines[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_line()` reference line directly (a
    horizontal `draw_line_aa` needs no text machinery) and return each
    one's optional label as a `_TextRequest`.

    Called right after `_render_generic` returns, using `result.y_scale`
    so each line lands on the same pixel row the mark's data would;
    raises if `has_y_scale` is `False`.

    Each line spans the inner plot rect's full width in
    `Theme.annotation_color`. Its label right-aligns just above the
    line's right end, at a fixed position with no collision avoidance.

    A `value` outside the mark's padded domain is skipped rather than
    drawn where unclamped extrapolation would put it (up in the title
    band); an out-of-range target is a legitimate reading, not an error.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.line_values) == 0:
        return text_requests^
    if not result.has_y_scale:
        raise Error(
            "Plot.annotate_line(): this mark has no continuous y-axis to place"
            " a reference line"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER and"
            " every mark sharing"
            " _CategoricalFrame"
            " (BAR/LOLLIPOP/WATERFALL/BOX/CANDLESTICK/BULLET/GROUPED_BAR/"
            "STACKED_BAR/STREAMGRAPH)"
        )

    var sc = _Scaled(theme)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    for i in range(len(plot._annotations.line_values)):
        # A reference line is a horizontal hairline, so its one fixed
        # coordinate snaps to a pixel center and it covers a single row
        # instead of two half-lit ones. That is what rounding the pixel
        # index already did here; saying it this way is what lets the
        # value stay Float64 up to the point where crispness is the
        # reason to move it.
        var py = _snap_pixel_center(
            _axis_pixel_f(result.y_scale, plot._annotations.line_values[i])
        )
        if py < Float64(py_top) or py > Float64(py_bottom):
            continue
        target.draw_line_aa(
            Float64(result.px0),
            py,
            Float64(result.px1),
            py,
            theme.annotation_color,
            width=sc.scale,
            dashes=theme.annotation_line_style.dashes(sc.scale),
        )
        var label = plot._annotations.line_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    result.px1 - sc.label_gap,
                    round_to_int(py) - sc.label_gap,
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.RIGHT,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_vlines[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """`_draw_annotation_lines`'s mirror image for `Plot.annotate_vline()`:
    a vertical line at an x `value`, using `result.x_scale`/
    `has_x_scale`, spanning the inner rect's full height, skipping an
    out-of-range value the same way. The label is left-aligned just right
    of the line near its top (`px + label_gap`, `py0 + font_size`).
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.vline_values) == 0:
        return text_requests^
    if not result.has_x_scale:
        raise Error(
            "Plot.annotate_vline(): this mark has no continuous x-axis to place"
            " a reference line against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )

    var sc = _Scaled(theme)
    var px_left = min(result.px0, result.px1)
    var px_right = max(result.px0, result.px1)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    for i in range(len(plot._annotations.vline_values)):
        # A vertical hairline: same rule as annotate_hline, on the other
        # axis.
        var px = _snap_pixel_center(
            _axis_pixel_f(result.x_scale, plot._annotations.vline_values[i])
        )
        if px < Float64(px_left) or px > Float64(px_right):
            continue
        target.draw_line_aa(
            px,
            Float64(py_top),
            px,
            Float64(py_bottom),
            theme.annotation_color,
            width=sc.scale,
            dashes=theme.annotation_line_style.dashes(sc.scale),
        )
        var label = plot._annotations.vline_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    round_to_int(px) + sc.label_gap,
                    py_top + Int(sc.font_size),
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.LEFT,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_points[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_point()` marker directly and return each
    one's optional label as a `_TextRequest`. Called last among the
    annotation passes so a point draws on top of every other layer. Needs
    both `result.x_scale` and `result.y_scale`. A point outside the
    padded domain on either axis is skipped.

    The marker is a filled circle of `sc.point_radius` in
    `Theme.annotation_color` (canvas has no pin glyph). Its label centers
    just above the marker.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.point_x) == 0:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_point(): this mark has no continuous x/y axes to"
            " place a point against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )

    var sc = _Scaled(theme)
    var px_left = min(result.px0, result.px1)
    var px_right = max(result.px0, result.px1)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    var radius = Float64(round_to_int(sc.point_radius))
    for i in range(len(plot._annotations.point_x)):
        var px = _axis_pixel_f(result.x_scale, plot._annotations.point_x[i])
        var py = _axis_pixel_f(result.y_scale, plot._annotations.point_y[i])
        if (
            px < Float64(px_left)
            or px > Float64(px_right)
            or py < Float64(py_top)
            or py > Float64(py_bottom)
        ):
            continue
        target.fill_circle_aa(px, py, radius, theme.annotation_color)
        var label = plot._annotations.point_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    round_to_int(px),
                    round_to_int(py - radius) - sc.label_gap,
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )
    return text_requests^


comptime _ARROW_HEAD_LENGTH = 11.0
"""Pixel length of an arrowhead before `Theme.scale`.

Sized from the theme, never from the arrow's own length: a head scaled
to the shaft would be comically large on a short arrow pointing at a
nearby point, and invisible on a long one crossing the chart. Every
other piece of furniture here is theme-sized for the same reason."""

comptime _ARROW_HEAD_HALF_WIDTH = 4.0
"""Half the arrowhead's base width, before `Theme.scale`. Narrower than
it is long, which is what reads as a direction rather than a wedge."""


def _draw_annotation_arrows[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    result: _RenderResult,
    theme: Theme,
    *,
    mut cache: FontCache,
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_arrow()` shaft and head, and return each
    one's label as a `_TextRequest` so it is replayed after the marks
    rather than painted over by them.

    An arrow is the only annotation that can be placed in empty space,
    which is what makes it usable on a crowded chart where every other
    overlay lands on data. Both ends are in data coordinates, so the
    label travels with the data when the domain changes.

    The head is one `fill_path_aa` triangle rather than three strokes:
    adjacent antialiased fills never reach full coverage at a shared
    edge, so a head assembled from separate pieces shows pale seams
    through it.

    Nothing snaps. The shaft is a diagonal and the head is a rotated
    triangle, and neither has a crisp position to snap to -- the rule
    used here, where only axis-aligned fills and hairlines snap.

    An arrow whose target or label falls outside the plot rect is
    skipped whole rather than clipped, matching `annotate_point()`: half
    an arrow points at nothing.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.arrow_x) == 0:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_arrow(): this mark has no continuous x/y axes to"
            " place an arrow against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )

    var sc = _Scaled(theme)
    var px_left = Float64(min(result.px0, result.px1))
    var px_right = Float64(max(result.px0, result.px1))
    var py_top = Float64(min(result.py0, result.py1))
    var py_bottom = Float64(max(result.py0, result.py1))

    var head_len = _ARROW_HEAD_LENGTH * theme.scale
    var head_half = _ARROW_HEAD_HALF_WIDTH * theme.scale

    for i in range(len(plot._annotations.arrow_x)):
        var tx = _axis_pixel_f(result.x_scale, plot._annotations.arrow_x[i])
        var ty = _axis_pixel_f(result.y_scale, plot._annotations.arrow_y[i])
        var lx = _axis_pixel_f(
            result.x_scale, plot._annotations.arrow_text_x[i]
        )
        var ly = _axis_pixel_f(
            result.y_scale, plot._annotations.arrow_text_y[i]
        )
        var inside = (
            tx >= px_left
            and tx <= px_right
            and ty >= py_top
            and ty <= py_bottom
            and lx >= px_left
            and lx <= px_right
            and ly >= py_top
            and ly <= py_bottom
        )
        if not inside:
            continue

        var label_text = plot._annotations.arrow_labels[i]
        var dx = tx - lx
        var dy = ty - ly
        var length = sqrt(dx * dx + dy * dy)
        # A label sitting on its own target has no direction to point
        # in, and normalizing would divide by zero. Draw the label and
        # skip the arrow rather than raising: the text still says what
        # it came to say.
        if length > head_len:
            var ux = dx / length
            var uy = dy / length
            # Perpendicular, for the head's base corners.
            var nx = -uy
            var ny = ux
            var base_x = tx - ux * head_len
            var base_y = ty - uy * head_len

            # The shaft starts where the ray leaves the label's own
            # box, not at its center: a fixed offset from the center
            # draws the line straight through the text, which is what
            # the first version did. The label is measured rather than
            # estimated from its character count -- a proportional font
            # makes "peak demand" and "IIIIIIIIIII" very different
            # widths at the same length.
            var m = measure_text(label_text, sc.font_size, cache=cache)
            var half_w = m.width / 2.0
            var half_h = sc.font_size / 2.0
            var exit_t = length
            if abs(ux) > 1e-9:
                exit_t = min(exit_t, half_w / abs(ux))
            if abs(uy) > 1e-9:
                exit_t = min(exit_t, half_h / abs(uy))
            if label_text.byte_length() == 0:
                exit_t = 0.0
            var gap = exit_t + Float64(sc.label_gap)

            # The shaft stops at the head's base rather than the target,
            # so the two do not overlap -- an antialiased stroke under a
            # filled head darkens its centerline where they cross.
            var start_x = lx + ux * gap
            var start_y = ly + uy * gap
            target.draw_line_aa(
                start_x,
                start_y,
                base_x,
                base_y,
                theme.annotation_color,
                width=theme.annotation_arrow_width * theme.scale,
            )

            var head = Path()
            head.move_to(tx, ty)
            head.line_to(base_x + nx * head_half, base_y + ny * head_half)
            head.line_to(base_x - nx * head_half, base_y - ny * head_half)
            head.close()
            target.fill_path_aa(
                head, theme.annotation_color, fill_rule=FillRule.NONZERO
            )

        if label_text.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    round_to_int(lx),
                    round_to_int(ly),
                    label_text,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_best_fit[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw `Plot.annotate_best_fit()`'s ordinary-least-squares line and
    return its optional label/equation/R-squared text as `_TextRequest`s.

    The regression is computed here from `plot.x_data`/`plot.y_data`, so
    the fit sees whatever data the plot ends up with regardless of call
    order, by `_ols_fit` (stats.mojo): closed-form OLS, `slope =
    (n*sum_xy - sum_x*sum_y) / (n*sum_xx - sum_x^2)`, `intercept =
    mean_y - slope*mean_x`. With `ci` set, its confidence band is
    filled first, beneath the line.

    Needs both `result.x_scale` and `result.y_scale`. Raises with fewer
    than 2 points, or when every x value is identical (the OLS
    denominator is 0).

    Drawn across the mark's full padded x-domain, with each endpoint's y
    clamped into the plot rect so a steep fit doesn't project outside it.
    """
    var text_requests = List[_TextRequest]()
    if not plot._annotations.best_fit:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_best_fit(): this mark has no continuous x/y axes to"
            " fit a line against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )
    var fit: _OlsFit
    try:
        fit = _ols_fit(plot.x_data, plot.y_data)
    except e:
        raise Error("Plot.annotate_best_fit(): " + String(e))
    var slope = fit.slope
    var intercept = fit.intercept
    var mean_y = fit.mean_y
    var n_points = fit.n
    var sc = _Scaled(theme)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    var x_left = result.x_scale.domain_min
    var x_right = result.x_scale.domain_max
    var px_left = _axis_pixel_f(result.x_scale, x_left)
    var px_right = _axis_pixel_f(result.x_scale, x_right)

    # The confidence band goes down first, under the line: a translucent
    # region in annotation_area_color whose edges are the fitted mean
    # plus and minus the band half-width, sampled across the domain so
    # the hourglass shape -- narrowest at mean_x, flaring at the ends --
    # is drawn as it is rather than as a constant-width strip. Each
    # edge is clamped into the plot rect the way the line's ends are.
    var ci = plot._annotations.best_fit_ci
    # Two points have no residual degrees of freedom, so there is no
    # band to size; the line draws alone rather than the default ci
    # turning a two-point fit into an error.
    if ci > 0.0 and fit.n >= 3:
        if ci >= 1.0:
            raise Error(
                "Plot.annotate_best_fit(): ci must be in (0, 1) (got "
                + String(ci)
                + ")"
            )
        var steps = 64
        var upper_py = List[Float64](capacity=steps + 1)
        var lower_py = List[Float64](capacity=steps + 1)
        var band_px = List[Float64](capacity=steps + 1)
        for i in range(steps + 1):
            var t = Float64(i) / Float64(steps)
            var xv = x_left + (x_right - x_left) * t
            var hw: Float64
            try:
                hw = fit.band_half_width(xv, ci)
            except e:
                raise Error("Plot.annotate_best_fit(): " + String(e))
            var yc = fit.predict(xv)
            band_px.append(_axis_pixel_f(result.x_scale, xv))
            upper_py.append(
                min(
                    max(
                        _axis_pixel_f(result.y_scale, yc + hw),
                        Float64(py_top),
                    ),
                    Float64(py_bottom),
                )
            )
            lower_py.append(
                min(
                    max(
                        _axis_pixel_f(result.y_scale, yc - hw),
                        Float64(py_top),
                    ),
                    Float64(py_bottom),
                )
            )
        var band = Path()
        band.move_to(band_px[0], upper_py[0])
        for i in range(1, steps + 1):
            band.line_to(band_px[i], upper_py[i])
        for i in range(steps, -1, -1):
            band.line_to(band_px[i], lower_py[i])
        band.close()
        target.fill_path_aa(
            band, theme.annotation_area_color, fill_rule=FillRule.NONZERO
        )
    # A fitted line is a diagonal, and a diagonal is antialiased
    # wherever it is put -- there is no crisp position to snap to, and
    # rounding the two ends tilted the line off the fit it is there to
    # show. The one exception is a flat fit, which is a horizontal
    # hairline like annotate_hline and snaps for the same reason.
    var py_left = min(
        max(
            _axis_pixel_f(result.y_scale, slope * x_left + intercept),
            Float64(py_top),
        ),
        Float64(py_bottom),
    )
    var py_right = min(
        max(
            _axis_pixel_f(result.y_scale, slope * x_right + intercept),
            Float64(py_top),
        ),
        Float64(py_bottom),
    )
    if py_left == py_right:
        py_left = _snap_pixel_center(py_left)
        py_right = py_left
    target.draw_line_aa(
        px_left,
        py_left,
        px_right,
        py_right,
        theme.annotation_color,
        width=sc.scale,
        dashes=theme.annotation_line_style.dashes(sc.scale),
    )

    var text_x = max(result.px0, result.px1) - sc.label_gap
    var text_y = py_top + Int(sc.font_size)
    if plot._annotations.best_fit_label.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                text_x,
                text_y,
                plot._annotations.best_fit_label,
                theme.annotation_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )
        text_y += Int(sc.font_size) + sc.label_gap
    if plot._annotations.best_fit_show_equation:
        var slope_str = _format_fixed(slope, 3)
        var eq: String
        if intercept >= 0.0:
            eq = "y = " + slope_str + "x + " + _format_fixed(intercept, 3)
        else:
            eq = "y = " + slope_str + "x - " + _format_fixed(-intercept, 3)
        text_requests.append(
            _TextRequest(
                text_x,
                text_y,
                eq,
                theme.annotation_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )
        text_y += Int(sc.font_size) + sc.label_gap
    if plot._annotations.best_fit_show_r_squared:
        # R-squared = 1 - SS_res/SS_tot. SS_tot == 0.0 (every y identical) is
        # defined as exactly 1.0 rather than 0/0.
        var ss_res = 0.0
        var ss_tot = 0.0
        for i in range(n_points):
            var predicted = slope * plot.x_data[i] + intercept
            var residual = plot.y_data[i] - predicted
            ss_res += residual * residual
            var deviation = plot.y_data[i] - mean_y
            ss_tot += deviation * deviation
        var r_squared = 1.0 if ss_tot == 0.0 else 1.0 - ss_res / ss_tot
        text_requests.append(
            _TextRequest(
                text_x,
                text_y,
                "R² = " + _format_fixed(r_squared, 3),
                theme.annotation_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )
    return text_requests^


def _validate_log_scale_annotations(plot: Plot) raises:
    """Every `annotate_line()`/`annotate_area()`/`annotate_vline()`/
    `annotate_point()` value on a log-scaled axis must be strictly
    positive, the same requirement `_log_data_extent()` enforces for the
    data, since annotations go through the same `to_pixel()`. Checked up
    front here because `to_pixel()` isn't `raises`. A no-op when neither
    axis is log-scaled.
    """
    if plot._y_log:
        for v in plot._annotations.line_values:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_line(): value must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.area_y0:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_area(): y0 must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.area_y1:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_area(): y1 must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.point_y:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_point(): y must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
    if plot._x_log:
        for v in plot._annotations.vline_values:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_vline(): value must be > 0 when"
                    " Plot.scale_x_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.point_x:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_point(): x must be > 0 when"
                    " Plot.scale_x_log() is set (got "
                    + String(v)
                    + ")"
                )
