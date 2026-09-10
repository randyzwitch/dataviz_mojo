"""Point, line, and area rendering and their one-call constructors."""

from std.math import sin

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.geometry import FPoint, round_to_int
from canvas.path import Path
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale, categorical_palette_for
from dataviz.frame import (
    _CategoricalIndex,
    _axis_pixel,
    _axis_pixel_f,
    _categorical_indices,
    _pull_off_axis_line,
)
from dataviz.legend import (
    _draw_continuous_color_legend,
    _draw_continuous_color_legend_h,
    _draw_continuous_size_legend,
    _draw_continuous_size_legend_h,
    _draw_legend,
    _legend_reserve_for,
)
from dataviz.mark import Mark
from dataviz.marker import PointShape, _fill_shape_aa, default_marker_shapes
from dataviz.pixel_snap import _snap_pixel_center
from dataviz.plot import (
    Plot,
    _finished,
    _point_tooltip_label,
    _zero_baseline_y_extent,
    render,
    render_svg,
    save,
)
from dataviz.scale import LinearScale, MinMax, _min_max
from dataviz.step_style import StepStyle
from dataviz.text import _Scaled, _TextRequest, _text_advance
from dataviz.theme import Theme
from dataviz.validate import _check_line_smoothing, _check_step_smoothing


def _build_line_path(
    px: List[Float64], py: List[Float64], smoothing: Float64
) raises -> Path:
    """Build a line or area path through projected parallel coordinates.

    A zero `smoothing` produces line segments; positive values use
    `Path.curve_through` with scaled Catmull-Rom tangents.
    """
    var points = List[FPoint](capacity=len(px))
    for i in range(len(px)):
        points.append(FPoint(px[i], py[i]))
    var path = Path()
    path.curve_through(points, smoothing)
    return path^


struct _Stepped(Movable):
    """The expanded coordinate lists returned by `_step_points`."""

    var px: List[Float64]
    var py: List[Float64]

    def __init__(out self, var px: List[Float64], var py: List[Float64]):
        self.px = px^
        self.py = py^


def _step_points(
    px: List[Float64], py: List[Float64], step: StepStyle
) -> _Stepped:
    """Expand projected coordinates into the requested staircase.

    The three styles differ only in where the riser goes, which is
    exactly what `StepStyle`'s constants name:

    - `PRE`: riser at the earlier x, so `(x[i], x[i + 1]]` draws at
      `y[i + 1]` -- emits `(x[i], y[i + 1])` then `(x[i + 1], y[i + 1])`.
    - `POST`: riser at the later x, so `[x[i], x[i + 1])` draws at
      `y[i]` -- emits `(x[i + 1], y[i])` then `(x[i + 1], y[i + 1])`.
    - `MID`: riser at the midpoint.

    Coordinates are already projected, so `MID` uses pixel-space
    midpoints. `NONE`, invalid styles, and inputs shorter than two points
    return a copy unchanged. Degenerate plateaus and risers may emit
    duplicate points.

    Args:
        px: Projected x pixel coordinates.
        py: Projected y pixel coordinates, same length as `px`.
        step: Which riser placement to expand to.

    Returns:
        The expanded pair; a copy of the input for `NONE`.
    """
    var is_pre = step == StepStyle.PRE
    var is_mid = step == StepStyle.MID
    var is_post = step == StepStyle.POST
    if len(px) < 2 or not (is_pre or is_mid or is_post):
        return _Stepped(px.copy(), py.copy())

    var n = len(px)
    # PRE/POST land on exactly 2n - 1 points, MID on 2n; one capacity
    # for both.
    var out_x = List[Float64](capacity=2 * n)
    var out_y = List[Float64](capacity=2 * n)
    out_x.append(px[0])
    out_y.append(py[0])
    for i in range(n - 1):
        if is_pre:
            out_x.append(px[i])
            out_y.append(py[i + 1])
            out_x.append(px[i + 1])
            out_y.append(py[i + 1])
        elif is_post:
            out_x.append(px[i + 1])
            out_y.append(py[i])
            out_x.append(px[i + 1])
            out_y.append(py[i + 1])
        else:
            var mid = (px[i] + px[i + 1]) / 2.0
            out_x.append(mid)
            out_y.append(py[i])
            out_x.append(mid)
            out_y.append(py[i + 1])
    if is_mid:
        # The last plateau's second half, which the loop above leaves to
        # "the next pair" that does not exist.
        out_x.append(px[n - 1])
        out_y.append(py[n - 1])
    return _Stepped(out_x^, out_y^)


struct _Decimated(Movable):
    """`_decimate_to_pixel_columns`' result: the reduced `px`/`py` pair plus
    `applied`, whether anything was dropped.
    """

    var px: List[Float64]
    var py: List[Float64]
    var applied: Bool

    def __init__(
        out self, var px: List[Float64], var py: List[Float64], applied: Bool
    ):
        self.px = px^
        self.py = py^
        self.applied = applied


def _decimate_to_pixel_columns(
    px: List[Float64], py: List[Float64]
) -> _Decimated:
    """Reduce a dense polyline to at most two points per horizontal pixel
    column.

    Per column this keeps the minimum and maximum y, in original data
    order, preserving the visible envelope.

    Two guards: `px` must be non-decreasing, since `mark_line()` connects
    points in data order and a path that doubles back would be
    reordered; and it only engages when there are more than twice as
    many points as columns, so every small chart renders byte-for-byte
    as before.
    """
    var n = len(px)
    if n < 4:
        return _Decimated(px.copy(), py.copy(), False)

    var lo = px[0]
    var hi = px[0]
    for i in range(1, n):
        if px[i] < px[i - 1]:
            # Not monotonic -- decline entirely (see docstring).
            return _Decimated(px.copy(), py.copy(), False)
        if px[i] < lo:
            lo = px[i]
        if px[i] > hi:
            hi = px[i]

    var columns = Int(hi) - Int(lo) + 1
    if columns < 1 or n <= 2 * columns:
        return _Decimated(px.copy(), py.copy(), False)

    var out_x = List[Float64](capacity=2 * columns)
    var out_y = List[Float64](capacity=2 * columns)

    var start = 0
    while start < n:
        var col = Int(px[start])
        var end = start
        while end + 1 < n and Int(px[end + 1]) == col:
            end += 1

        var i_min = start
        var i_max = start
        for i in range(start + 1, end + 1):
            if py[i] < py[i_min]:
                i_min = i
            if py[i] > py[i_max]:
                i_max = i

        # The column's two extremes, in the order the data visited them; one
        # point when they're the same sample.
        var first = i_min if i_min <= i_max else i_max
        var second = i_max if i_min <= i_max else i_min
        out_x.append(px[first])
        out_y.append(py[first])
        if second != first:
            out_x.append(px[second])
            out_y.append(py[second])

        start = end + 1

    return _Decimated(out_x^, out_y^, True)


struct _PointChannels(Movable):
    """Every derived value `Mark.POINT`'s optional data-driven channels
    (categorical color, continuous color, continuous size; see
    `Plot.encode`) need: which are encoded, the categorical domain and
    palette a discrete color column indexes into, and the `ColorScale`/
    `LinearScale` a continuous column maps through. Built
    unconditionally, with placeholder scales when a channel isn't
    encoded.

    A struct because these are needed at two points in one render:
    before the plot rect is finalized, to size the legend column
    (`_legend_reserve_for`), and after, to color/size each point and draw
    the legend (`_draw_point_layer`). Computing them once keeps the two
    consistent.
    """

    var has_color: Bool
    var has_color_categories: Bool
    var has_size: Bool
    # The categorical color column's domain and each row's index into it,
    # resolved once (`_categorical_indices`). Held as the whole
    # `_CategoricalIndex` since Mojo won't let a returned struct's fields
    # be moved out individually. Both halves are empty when the channel
    # isn't encoded.
    var cat: _CategoricalIndex
    # One color per `cat.domain` entry, sized to the domain exactly with
    # `Plot.encode()`'s `color_map` overrides folded in, so readers index
    # it directly by domain position.
    var palette: List[Color]
    # One shape per `cat.domain` entry, same indexing as `palette`; empty
    # unless both `has_color_categories` and `Theme.shape_by_category` are
    # true. `has_shapes` names that combination.
    var has_shapes: Bool
    var shapes: List[PointShape]
    var color_scale: ColorScale
    var size_mm: MinMax
    var size_scale: LinearScale

    def __init__(out self, plot: Plot, sc: _Scaled) raises:
        self.has_color = len(plot.color_data) > 0
        self.has_color_categories = len(plot.color_categories) > 0
        self.has_size = len(plot.size_data) > 0
        # Branch rather than resolving an empty column: `plot` is borrowed, so
        # a ternary would need a full copy of `color_categories`.
        if self.has_color_categories:
            self.cat = _categorical_indices(plot.color_categories)
        else:
            self.cat = _CategoricalIndex(List[String](), List[Int]())
        self.palette = List[Color]()
        if self.has_color_categories:
            var default_palette = categorical_palette_for(plot._theme)
            for i in range(len(self.cat.domain)):
                var name = self.cat.domain[i]
                if name in plot.color_map:
                    self.palette.append(plot.color_map[name])
                else:
                    self.palette.append(
                        default_palette[i % len(default_palette)]
                    )
        self.has_shapes = (
            self.has_color_categories and plot._theme.shape_by_category
        )
        self.shapes = List[PointShape]()
        if self.has_shapes:
            var default_shapes = default_marker_shapes()
            for i in range(len(self.cat.domain)):
                self.shapes.append(default_shapes[i % len(default_shapes)])
        var color_mm = _min_max(plot.color_data) if self.has_color else MinMax(
            0.0, 1.0
        )
        self.color_scale = ColorScale.from_theme(
            plot._theme, color_mm.min, color_mm.max
        )
        self.size_mm = _min_max(plot.size_data) if self.has_size else MinMax(
            0.0, 1.0
        )
        self.size_scale = LinearScale(
            self.size_mm.min,
            self.size_mm.max,
            sc.size_range_min,
            sc.size_range_max,
        )


def _lighten(color: Color, alpha: UInt8, background: Color) -> Color:
    """`color` at `alpha` flattened over `background`, kept fully opaque
    -- for `Mark.EFFECT_SCATTER`'s halo (`Theme.halo_alpha`) and
    `Mark.SUNBURST`'s depth fade. A flattened tint rather than real alpha
    on the shape, so overlapping shapes do not compound and the tint is
    the same whatever else has been drawn beneath.

    `background` must be the theme's, not a literal: flattening against
    white made a `dark()` halo the brightest thing on the chart, a tint
    computed for a ground the chart did not have (#427).
    """
    return color.with_alpha(alpha).blend_over(background)


def _draw_point_layer[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    plot: Plot,
    ch: _PointChannels,
    x_scale: LinearScale,
    y_scale: LinearScale,
    legend_x: Int,
    legend_y: Int,
    draw_halo: Bool = False,
    legend_horizontal: Bool = False,
    band_px: List[Float64] = List[Float64](),
) raises -> Int:
    """Draw one `Mark.POINT` plot's points into an already-laid-out
    continuous axis frame, plus the legend sections its encoded channels
    call for; shared by the standalone path and by each `Mark.POINT`
    layer of a stack. Also `Mark.EFFECT_SCATTER`'s whole render with
    `draw_halo=True`.

    Legend sections stack top to bottom in one column, each returning the
    y just below it for the next: categorical or continuous color first
    (mutually exclusive), then size, the order `_legend_reserve_for`
    sized them in. `legend_y` in, the next free y out, so a layered
    caller threads the return value through as a cursor. `legend_x` is
    the caller's, since a layered render shares one column x from the
    combined rect. Row height, font size, colors, and point radius come
    from `plot`'s own `Theme`.

    `band_px`, when non-empty, replaces `x_scale` as the source of each
    point's x: one precomputed pixel position per row, in row order.
    That is how a `Mark.BAR` combo chart draws this mark against
    categorical band centers, which no `LinearScale` can express
    (#422). Empty -- the default -- leaves the continuous path
    unchanged.

    `draw_halo` draws one extra circle under each point first,
    `_lighten`ed toward white at ~2.2x the radius, a static stand-in for
    ECharts' animated ripple.

    `Plot.encode()`'s `labels`, when set, draw each row's text centered
    `sc.label_gap` above its point; a row whose entry is `""` is skipped.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)

    # The plain scatter -- nothing per point but a disk -- can hand every
    # marker to `fill_circles_aa` in one call (#329). That bands the
    # *canvas* across cores rather than the markers, which is the only
    # way a scatter parallelizes: one marker is far too small to be worth
    # a task. Output is identical to calling `fill_circle_aa` per centre
    # in the same order, translucent overlap included, and the primitive
    # falls back to per-marker calls itself when a transform puts it
    # outside its closed form.
    #
    # Every condition below is a case where the batch would change what
    # is drawn, not merely how fast:
    #   - a size channel gives each marker its own radius; the batch
    #     shares one.
    #   - shapes draw through `_fill_shape_aa`, not a disk at all.
    #   - tooltips need `begin/end_annotated_group` around each point.
    #   - halos and error bars are drawn per point *before* its marker,
    #     so batching the markers to the end would let an earlier
    #     marker survive a later point's halo that today covers it.
    #     That is a z-order change, and overlapping points are exactly
    #     when a halo matters.
    var has_error_bars = (
        len(plot.y_err_data) > 0 or len(plot.y_err_lower_data) > 0
    )
    var tooltips_on = theme.svg_tooltips and plot._mark_style.point_tooltips
    var batched = (
        not ch.has_size
        and not ch.has_shapes
        and not tooltips_on
        and not draw_halo
        and not has_error_bars
    )
    var batch_centers = List[FPoint]()
    var batch_colors = List[Color]()

    for i in range(len(plot.y_data)):
        var px = band_px[i] if len(band_px) > 0 else _axis_pixel_f(
            x_scale, plot.x_data[i]
        )
        var py = _axis_pixel_f(y_scale, plot.y_data[i])
        var color: Color
        if ch.has_color:
            color = ch.color_scale.color_at(plot.color_data[i])
        elif ch.has_color_categories:
            # A plain lookup: _PointChannels resolved every row's domain index up
            # front.
            color = ch.palette[ch.cat.indices[i] % len(ch.palette)]
        else:
            color = theme.mark_color
        # The center never rounds: a marker is a disk, not a rect, so it
        # is antialiased on every side whatever it sits on and snapping
        # buys no crispness while costing position.
        #
        # The radius rounds only when it is a constant. One value for
        # the whole chart loses nothing to a whole-pixel radius, and
        # every other mark that draws `Theme.point_radius` rounds it, so
        # a scatter keeps matching them. A size-encoded radius is data:
        # rounding collapses a continuous scale into a handful of
        # whole-pixel steps, and two points 20% apart in value can come
        # out the same size.
        var radius = ch.size_scale.to_pixel(
            plot.size_data[i]
        ) if ch.has_size else Float64(round_to_int(sc.point_radius))
        # One group per point, covering its error bar, halo and marker
        # -- all one datum. The deferred label sits outside it, since
        # text is replayed after this pass (see _TextRequest).
        var tooltip = theme.svg_tooltips and plot._mark_style.point_tooltips
        if tooltip:
            target.begin_annotated_group(_point_tooltip_label(plot, i))
        if len(plot.y_err_data) > 0 or len(plot.y_err_lower_data) > 0:
            # Whisker first, point on top, in this point's own resolved `color`.
            # y_err and y_err_lower/y_err_upper are mutually exclusive, so exactly
            # one branch has data.
            var lo: Float64
            var hi: Float64
            if len(plot.y_err_data) > 0:
                var err = plot.y_err_data[i]
                lo = plot.y_data[i] - err
                hi = plot.y_data[i] + err
            else:
                lo = plot.y_data[i] - plot.y_err_lower_data[i]
                hi = plot.y_data[i] + plot.y_err_upper_data[i]
            # Snap the hairline and caps to matching pixel centers.
            var bar_x = _snap_pixel_center(px)
            var py_hi = _snap_pixel_center(_axis_pixel_f(y_scale, hi))
            var py_lo = _snap_pixel_center(_axis_pixel_f(y_scale, lo))
            var cap_half = Float64(round_to_int(sc.error_bar_cap_width))
            target.draw_line_aa(
                bar_x, py_hi, bar_x, py_lo, color, width=sc.scale
            )
            target.draw_line_aa(
                bar_x - cap_half,
                py_hi,
                bar_x + cap_half,
                py_hi,
                color,
                width=sc.scale,
            )
            target.draw_line_aa(
                bar_x - cap_half,
                py_lo,
                bar_x + cap_half,
                py_lo,
                color,
                width=sc.scale,
            )
        if draw_halo:
            target.fill_circle_aa(
                px,
                py,
                radius * 2.2,
                _lighten(color, theme.halo_alpha, theme.background),
            )
        if ch.has_shapes:
            # Same lookup as `color`'s categorical branch; ch.shapes is sized to
            # ch.cat.domain like ch.palette.
            _fill_shape_aa(
                target,
                px,
                py,
                radius,
                ch.shapes[ch.cat.indices[i] % len(ch.shapes)],
                color,
            )
        elif batched:
            # Collected and flushed once below, in this same order.
            batch_centers.append(FPoint(px, py))
            batch_colors.append(color)
        else:
            target.fill_circle_aa(px, py, radius, color)
        if tooltip:
            target.end_annotated_group()
        if len(plot.point_labels) > 0 and plot.point_labels[i] != "":
            # Baseline placed label_gap above the point's top edge (py - radius).
            # Text anchors are pixel indices, so the top edge rounds
            # here and the gap stays a whole number of pixels.
            text_requests.append(
                _TextRequest(
                    round_to_int(px),
                    round_to_int(py - radius) - sc.label_gap,
                    plot.point_labels[i],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )

    # Flushed before the legend, so the markers still land under it in
    # draw order exactly as the per-point path left them. The shared
    # radius is the same expression the per-point path uses when
    # `ch.has_size` is false, which `batched` requires.
    if batched and len(batch_centers) > 0:
        var batch_radius = Float64(round_to_int(sc.point_radius))
        if ch.has_color or ch.has_color_categories:
            target.fill_circles_aa(batch_centers, batch_radius, batch_colors)
        else:
            target.fill_circles_aa(
                batch_centers, batch_radius, theme.mark_color
            )

    if not theme.show_legend:
        return legend_y
    if not (ch.has_color_categories or ch.has_color or ch.has_size):
        return legend_y

    if legend_horizontal:
        # One row: sections side by side, in the same order the column
        # stacks them, so a plot reads the same whichever edge it is on.
        var cursor = legend_x
        if ch.has_color_categories:
            var sc_row = _Scaled(theme)
            for i in range(len(ch.cat.domain)):
                var color = ch.palette[i % len(ch.palette)]
                if len(ch.shapes) > 0:
                    var radius = sc_row.legend_swatch_size // 2
                    _fill_shape_aa(
                        target,
                        cursor + radius,
                        legend_y + radius,
                        radius,
                        ch.shapes[i % len(ch.shapes)],
                        color,
                    )
                else:
                    target.fill_rect(
                        cursor,
                        legend_y,
                        sc_row.legend_swatch_size,
                        sc_row.legend_swatch_size,
                        color,
                    )
                var label_x = (
                    cursor + sc_row.legend_swatch_size + sc_row.label_gap
                )
                text_requests.append(
                    _TextRequest(
                        label_x,
                        legend_y + sc_row.legend_swatch_size - 3,
                        ch.cat.domain[i],
                        theme.text_color,
                        sc_row.font_size,
                        TextAlign.LEFT,
                        theme.font_family,
                    )
                )
                cursor = (
                    label_x
                    + _text_advance(ch.cat.domain[i], sc_row)
                    + sc_row.legend_swatch_size
                )
        elif ch.has_color:
            cursor = _draw_continuous_color_legend_h(
                target, text_requests, ch.color_scale, cursor, legend_y, theme
            )
        if ch.has_size:
            cursor = _draw_continuous_size_legend_h(
                target,
                text_requests,
                ch.size_mm,
                ch.size_scale,
                cursor,
                legend_y,
                theme,
            )
        return legend_y

    var next_y = legend_y
    if ch.has_color_categories:
        _draw_legend(
            target,
            text_requests,
            ch.cat.domain,
            ch.palette,
            legend_x,
            next_y,
            theme,
            shapes=ch.shapes,
        )
        next_y += len(ch.cat.domain) * (
            sc.legend_swatch_size + sc.legend_row_gap
        )
    elif ch.has_color:
        next_y = _draw_continuous_color_legend(
            target, text_requests, ch.color_scale, legend_x, next_y, theme
        )
    if ch.has_size:
        next_y = _draw_continuous_size_legend(
            target,
            text_requests,
            ch.size_mm,
            ch.size_scale,
            legend_x,
            next_y,
            theme,
        )
    return next_y


def _draw_line_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: LinearScale,
    y_scale: LinearScale,
    band_px: List[Float64] = List[Float64](),
) raises:
    """Draw one `Mark.LINE` plot's stroked path into an already-laid-out
    continuous axis frame, with `Theme.line_smoothing` via
    `_build_line_path` and `mark_line(step=...)` via `_step_points`.
    Shared by the standalone and layered paths so both honor smoothing,
    stepping and their checks identically.

    `Plot.encode()`'s `y_err` whisker, when set, draws once per original
    data point before the line (whisker first, line on top), over the
    untouched `plot.x_data`/`y_data` rather than the decimated path, in
    `theme.mark_color` (`Mark.LINE` has no per-point color). Stepping
    does not move a whisker: it belongs to a sample, not to the segment
    between two of them.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    _check_line_smoothing(theme)
    _check_step_smoothing(theme, plot._mark_style.step)
    if len(plot.y_err_data) > 0:
        var cap_half = round_to_int(sc.error_bar_cap_width)
        for i in range(len(plot.x_data)):
            var px_i = round_to_int(x_scale.to_pixel(plot.x_data[i]))
            var err = plot.y_err_data[i]
            var py_hi = _axis_pixel(y_scale, plot.y_data[i] + err)
            var py_lo = _axis_pixel(y_scale, plot.y_data[i] - err)
            target.draw_line_aa(
                px_i, py_hi, px_i, py_lo, theme.mark_color, width=sc.scale
            )
            target.draw_line_aa(
                px_i - cap_half,
                py_hi,
                px_i + cap_half,
                py_hi,
                theme.mark_color,
                width=sc.scale,
            )
            target.draw_line_aa(
                px_i - cap_half,
                py_lo,
                px_i + cap_half,
                py_lo,
                theme.mark_color,
                width=sc.scale,
            )
    var px = List[Float64](capacity=len(plot.y_data))
    var py = List[Float64](capacity=len(plot.y_data))
    for i in range(len(plot.y_data)):
        px.append(
            band_px[i] if len(band_px) > 0 else x_scale.to_pixel(plot.x_data[i])
        )
        py.append(y_scale.to_pixel(plot.y_data[i]))
    # Thin the expanded geometry so step risers retain their true positions.
    var stepped = _step_points(px, py, plot._mark_style.step)
    # Drop sub-pixel detail before the rasterizer has to pay for it --
    # a no-op for any series small enough that its points are
    # individually resolvable (see _decimate_to_pixel_columns).
    var thinned = _decimate_to_pixel_columns(stepped.px, stepped.py)
    var path = _build_line_path(thinned.px, thinned.py, theme.line_smoothing)
    target.stroke_path_aa(
        path,
        theme.mark_color,
        width=sc.line_width,
        dashes=plot._mark_style.line_style.dashes(sc.scale),
    )


def _draw_area_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: LinearScale,
    y_scale: LinearScale,
    band_px: List[Float64] = List[Float64](),
) raises:
    """Draw one `Mark.AREA` plot's filled region into an already-laid-out
    continuous axis frame: the same curve `_draw_line_layer` strokes,
    closed down to the zero baseline (`y_scale`'s domain includes zero;
    see `_zero_baseline_y_extent`) and filled. Only the top edge smooths
    or steps; the two closing segments to and along the baseline stay
    straight. The closing edge is pulled 1px off the bottom axis line
    when it lands there, the `_pull_off_axis_line` rule applied to a
    path.

    `mark_area(step=...)` reaches the top edge through the same
    `_step_points` `_draw_line_layer` uses -- a stepped area is a
    stepped line with the region under it filled, so a second expansion
    written against the fill would be two places to get `PRE`/`MID`/
    `POST` right instead of one. The closing segments do not join the
    staircase: `_step_points` neither moves the first x nor the last, so
    the fill still meets the baseline directly under the outermost
    samples, with no sliver at either end and nothing for the path to
    cross back over.
    """
    var theme = plot._theme
    _check_line_smoothing(theme)
    _check_step_smoothing(theme, plot._mark_style.step, Mark.AREA)
    var baseline_py = y_scale.to_pixel(0.0)
    if round_to_int(baseline_py) == round_to_int(y_scale.range_min):
        baseline_py -= 1.0
    var px = List[Float64](capacity=len(plot.x_data))
    var py = List[Float64](capacity=len(plot.x_data))
    for i in range(len(plot.x_data)):
        px.append(
            band_px[i] if len(band_px) > 0 else x_scale.to_pixel(plot.x_data[i])
        )
        py.append(y_scale.to_pixel(plot.y_data[i]))
    # Step first, decimate second, the order and the reasoning
    # _draw_line_layer's own comment spells out: thin the geometry that
    # is actually drawn, so the two-points-per-column cap applies to the
    # staircase rather than being half undone by expanding after it.
    var stepped = _step_points(px, py, plot._mark_style.step)
    # Same sub-pixel thinning the stroked path gets; the fill's top edge is
    # that curve.
    var thinned = _decimate_to_pixel_columns(stepped.px, stepped.py)
    var path = _build_line_path(thinned.px, thinned.py, theme.line_smoothing)
    path.line_to(thinned.px[len(thinned.px) - 1], baseline_py)
    path.line_to(thinned.px[0], baseline_py)
    path.close()
    target.fill_path_aa(path, theme.mark_color, fill_rule=FillRule.NONZERO)


def scatter(
    x: List[Float64],
    y: List[Float64],
    tooltips: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A scatter plot: one point per (x, y) pair, the standard choice for
    showing the relationship between two continuous variables.

    `Mark.POINT` over continuous `x`/`y`.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column, one entry per point.
        tooltips: Whether each point carries an SVG `<title>` a browser
            shows on hover; defaults to `False`. `Theme.svg_tooltips`
            must also be enabled.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import scatter
        from dataviz import save

        def main() raises:
            # Illustrative specifications for current electric vehicles.
            var battery_kwh: List[Float64] = [
                42, 50, 54, 58, 62, 66, 70, 74, 78, 82, 88, 94, 101, 108, 115,
            ]
            var highway_range_km: List[Float64] = [
                255, 292, 318, 305, 354, 381, 365, 419, 445, 432, 487, 516, 548,
                565, 604,
            ]

            var c = scatter(
                battery_kwh,
                highway_range_km,
                tooltips=True,
                title="Illustrative EV Battery Capacity vs. Highway Range",
                x_title="Usable battery capacity (kWh)",
                y_title="Highway range (km)",
            )
            save(c, "docs/src/examples/out_scatter.svg")
        ```
    """
    var plot = Plot().mark_point(tooltips=tooltips).encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def scatter[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    tooltips: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`scatter()` generalized over numeric element type (`List[Int]`,
    `List[Float32]`, ...); see `Plot.encode()`'s `DType` overload and
    array_like.mojo. Delegates to the concrete overload above.
    """
    return scatter(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        tooltips=tooltips,
        theme=theme,
        width=width,
        height=height,
        title=title,
        x_title=x_title,
        y_title=y_title,
    )


def line(
    x: List[Float64],
    y: List[Float64],
    step: StepStyle = StepStyle.NONE,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A line chart: continuous x/y data connected in order, the standard
    choice for showing a trend over a continuous variable such as time.

    `Mark.LINE` over continuous `x`/`y`, connected in data order.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column, one entry per point.
        step: Step (stairs) interpolation -- `NONE` (the default,
            straight segments), or `PRE`/`MID`/`POST` for a value that
            holds until it changes rather than moving gradually between
            samples. See `StepStyle` for which riser placement claims
            what.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import line
        from dataviz import save
        from dataviz.colors import BROWN
        from dataviz import Theme

        def main() raises:
            # Illustrative monthly active users after a product launch:
            # sustained growth with a summer plateau and year-end lift.
            var month: List[Float64] = [
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
                13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
            ]
            var active_users_k: List[Float64] = [
                18, 24, 31, 39, 48, 57, 63, 66, 68, 74, 83, 96,
                104, 113, 125, 138, 149, 156, 158, 164, 177, 193, 214, 238,
            ]

            var c = line(
                month,
                active_users_k,
                title="Illustrative Monthly Active Users After Launch",
                x_title="Month since launch",
                y_title="Active users (thousands)",
                theme=Theme(
                    mark_color=BROWN,
                    line_width=3.0,
                    show_gridlines=False,
                ),
            )
            save(c, "docs/src/examples/out_line.svg")
        ```

    Example (Slope Chart):
        ```mojo
        from dataviz import line
        from dataviz import save
        from dataviz import Theme
        from dataviz.colors import SEAGREEN

        def main() raises:
            # x=0.0 ("2023"), x=1.0 ("2024") -- revenue, in millions.
            var x: List[Float64] = [0.0, 1.0]
            var revenue: List[Float64] = [42.0, 61.0]

            var c = line(
                x,
                revenue,
                title="Revenue, 2023 to 2024",
                x_title="Year",
                y_title="Revenue ($M)",
                theme=Theme(
                    mark_color=SEAGREEN,
                    line_width=3.0,
                    show_gridlines=False,
                ),
                width=320,
                height=420,
            )
            save(c, "docs/src/examples/out_slope.svg")
        ```

    Example (Step Chart):
        ```mojo
        from dataviz import StepStyle, line
        from dataviz import save
        from dataviz.colors import CRIMSON
        from dataviz import Theme

        def main() raises:
            # A central bank's policy rate holds flat between meetings and
            # moves only at one, so the straight interpolation a plain line
            # draws would show months of gradual drift that never happened.
            # StepStyle.POST puts the riser at the later month: the rate set
            # at a meeting is the rate in force until the next one.
            var month: List[Float64] = [
                0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0, 27.0
            ]
            var rate: List[Float64] = [
                1.75, 2.5, 3.25, 4.0, 4.5, 5.0, 5.25, 5.25, 4.75, 4.75
            ]

            var c = line(
                month,
                rate,
                step=StepStyle.POST,
                title="Policy Rate Changes",
                theme=Theme(mark_color=CRIMSON, line_width=3.0),
                x_title="Months since first hike",
                y_title="Policy rate (%)",
            )
            save(c, "docs/src/examples/out_step.svg")
        ```
    """
    var plot = Plot().mark_line(step=step).encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def line[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    step: StepStyle = StepStyle.NONE,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`line()` generalized over numeric element type; see `scatter()`'s
    `DType` overload above. Delegates to the concrete overload above.
    """
    return line(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        step=step,
        theme=theme,
        width=width,
        height=height,
        title=title,
        x_title=x_title,
        y_title=y_title,
    )


def area(
    x: List[Float64],
    y: List[Float64],
    step: StepStyle = StepStyle.NONE,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """An area chart: a line chart with the region down to a zero
    baseline filled in, emphasizing a series' magnitude and cumulative
    feel over its exact trend line.

    `Mark.AREA` over continuous `x`/`y`, filled down to a zero baseline.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column; the filled area runs from each
            point down to zero.
        step: Step (stairs) interpolation on the fill's top edge --
            `NONE` (the default, straight segments), or `PRE`/`MID`/
            `POST` for a quantity that holds constant between samples
            rather than sliding between them. See `StepStyle` for which
            riser placement claims what, and `Plot.mark_area()` for why
            only the top edge steps.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import area
        from dataviz import save
        from dataviz.colors import STEELBLUE
        from dataviz import Theme

        def main() raises:
            # Illustrative hourly solar output: zero overnight, a small
            # morning cloud dip, and a broad midday production peak.
            var hour: List[Float64] = [
                0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
                12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
            ]
            var output_mw: List[Float64] = [
                0, 0, 0, 0, 0, 0, 2, 9, 21, 34, 31, 52,
                63, 68, 66, 59, 48, 35, 20, 8, 1, 0, 0, 0,
            ]

            var c = area(
                hour,
                output_mw,
                title="Illustrative Solar Generation on a Clear Day",
                x_title="Hour of day",
                y_title="Output (MW)",
                theme=Theme(mark_color=STEELBLUE),
            )
            save(c, "docs/src/examples/out_area.svg")
        ```

    Example (Stepped Area Chart):
        ```mojo
        from dataviz import StepStyle, area
        from dataviz import save
        from dataviz.colors import SEAGREEN
        from dataviz import Theme

        def main() raises:
            # Units in the warehouse change only when a delivery arrives
            # or a shipment leaves, and hold flat in between. A straight
            # top edge would fill in a slow drift between counts that
            # never happened, and the fill would assign area to those
            # invented values; StepStyle.POST holds each count until the
            # day the next one was taken.
            var day: List[Float64] = [
                0.0, 4.0, 7.0, 11.0, 16.0, 20.0, 25.0, 28.0
            ]
            var units: List[Float64] = [
                120.0, 340.0, 300.0, 260.0, 480.0, 430.0, 390.0, 350.0
            ]

            var c = area(
                day,
                units,
                step=StepStyle.POST,
                title="Warehouse Inventory",
                theme=Theme(mark_color=SEAGREEN),
                x_title="Day of month",
                y_title="Units on hand",
            )
            save(c, "docs/src/examples/out_step_area.svg")
        ```
    """
    var plot = Plot().mark_area(step=step).encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def area[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    step: StepStyle = StepStyle.NONE,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`area()` generalized over numeric element type; see `scatter()`'s
    `DType` overload above. Delegates to the concrete overload above.
    """
    return area(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        step=step,
        theme=theme,
        width=width,
        height=height,
        title=title,
        x_title=x_title,
        y_title=y_title,
    )
