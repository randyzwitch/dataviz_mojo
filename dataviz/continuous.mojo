"""The three continuous marks -- point, line and area -- and the
one-call functions that build them.

Split out of `plot.mojo` (#222). These three share a frame, a set of
encodings (`_PointChannels` resolves color/size/shape once per chart
rather than per row) and the decimation that keeps a long series from
costing more than the pixels it can occupy.

Marker and line geometry is `Float64` throughout: a disk is antialiased
on every side wherever it sits, so rounding its center bought no
crispness and only moved it off the datum (#312).
"""

from std.math import sin

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.geometry import FPoint, round_to_int
from canvas.path import Path
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale, default_categorical_palette
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
from dataviz.text import _Scaled, _TextRequest, _text_advance
from dataviz.theme import Theme
from dataviz.validate import _check_line_smoothing


def _build_line_path(
    px: List[Float64], py: List[Float64], smoothing: Float64
) raises -> Path:
    """The `Path` a `Mark.LINE` plot strokes through its
    already-pixel-projected points, and the curve `Mark.AREA` fills down
    to the baseline from.

    Delegates to `Path.curve_through`, which canvas_mojo v0.18.0 added
    with exactly these semantics: `smoothing == 0.0` takes an explicit
    `line_to` branch, so the default render is command-for-command the
    one a polyline builds (a flattened cubic samples at even parameter
    spacing, not even pixel spacing, so even a straight cubic flattens
    to different intermediate points); above 0.0 it is one cubic per
    consecutive pair with Catmull-Rom tangents -- control point =
    endpoint +/- (next minus previous)/6 -- with the ends clamped to a
    one-sided tangent, and `smoothing` scaling the tangent length.

    Bit-identical to the arithmetic this used to do inline: canvas_mojo
    v0.18.1 divides then scales per component, the same order, so every
    control point matches to the last bit.

    This wrapper stays rather than callers using `curve_through`
    directly because the render paths carry points as parallel
    `px`/`py` lists, not `FPoint`s.
    """
    var points = List[FPoint](capacity=len(px))
    for i in range(len(px)):
        points.append(FPoint(px[i], py[i]))
    var path = Path()
    path.curve_through(points, smoothing)
    return path^


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

    A `Mark.LINE`/`AREA` plot of 5000 points into a ~640px-wide plot area
    hands the rasterizer roughly eight segments per pixel column, and
    `stroke_path_aa` pays full per-segment cost for each (~263us/segment,
    so a 5000-point line took ~1.7s against ~21ms for the same points as
    a scatter).

    Per column this keeps the minimum and maximum y, in original data
    order (collapsed to one point when they are the same sample), which
    preserves the envelope: a spike inside one column still reaches its
    true extent. Keeping four points per column (first/last as well) was
    tried and dropped nothing at all for a 2000-point series over ~500
    columns. Min and max are real samples, so the joins between columns
    move by at most a pixel.

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
            var default_palette = default_categorical_palette()
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


def _lighten(color: Color, alpha: UInt8) -> Color:
    """`color` blended toward opaque white by `alpha`, for
    `Mark.EFFECT_SCATTER`'s halo (`Theme.halo_alpha`) and `Mark.RADAR`'s
    polygon fill (`mark_radar(fill_alpha=...)`). Built via
    `Color.with_alpha`/`Color.blend_over` (reduced alpha composited over
    white, kept fully opaque) rather than real alpha on the shape, so the
    tint is the same regardless of what's behind it.
    """
    return color.with_alpha(alpha).blend_over(Color(255, 255, 255))


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

    `draw_halo` draws one extra circle under each point first,
    `_lighten`ed toward white at ~2.2x the radius, a static stand-in for
    ECharts' animated ripple.

    `Plot.encode()`'s `labels`, when set, draw each row's text centered
    `sc.label_gap` above its point; a row whose entry is `""` is skipped.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)

    for i in range(len(plot.x_data)):
        var px = _axis_pixel_f(x_scale, plot.x_data[i])
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
            # The whisker and its two caps are hairlines, so all three
            # snap onto pixel centers -- crispness wins over a fraction
            # of a pixel, and the three meeting exactly keeps the T
            # joints clean. That is also what the Int arithmetic here
            # used to do, so error bars do not move; only the marker
            # they belong to does.
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
                _lighten(color, theme.halo_alpha),
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
](mut target: T, plot: Plot, x_scale: LinearScale, y_scale: LinearScale) raises:
    """Draw one `Mark.LINE` plot's stroked path into an already-laid-out
    continuous axis frame, with `Theme.line_smoothing` via
    `_build_line_path`. Shared by the standalone and layered paths so
    both honor smoothing and its range check identically.

    `Plot.encode()`'s `y_err` whisker, when set, draws once per original
    data point before the line (whisker first, line on top), over the
    untouched `plot.x_data`/`y_data` rather than the decimated path, in
    `theme.mark_color` (`Mark.LINE` has no per-point color).
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    _check_line_smoothing(theme)
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
    var px = List[Float64](capacity=len(plot.x_data))
    var py = List[Float64](capacity=len(plot.x_data))
    for i in range(len(plot.x_data)):
        px.append(x_scale.to_pixel(plot.x_data[i]))
        py.append(y_scale.to_pixel(plot.y_data[i]))
    # Drop sub-pixel detail before the rasterizer has to pay for it --
    # a no-op for any series small enough that its points are
    # individually resolvable (see _decimate_to_pixel_columns).
    var thinned = _decimate_to_pixel_columns(px, py)
    var path = _build_line_path(thinned.px, thinned.py, theme.line_smoothing)
    target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)


def _draw_area_layer[
    T: DrawTarget
](mut target: T, plot: Plot, x_scale: LinearScale, y_scale: LinearScale) raises:
    """Draw one `Mark.AREA` plot's filled region into an already-laid-out
    continuous axis frame: the same curve `_draw_line_layer` strokes,
    closed down to the zero baseline (`y_scale`'s domain includes zero;
    see `_zero_baseline_y_extent`) and filled. Only the top edge smooths;
    the two closing segments to and along the baseline stay straight.
    The closing edge is pulled 1px off the bottom axis line when it lands
    there, the `_pull_off_axis_line` rule applied to a path.
    """
    var theme = plot._theme
    _check_line_smoothing(theme)
    var baseline_py = y_scale.to_pixel(0.0)
    if round_to_int(baseline_py) == round_to_int(y_scale.range_min):
        baseline_py -= 1.0
    var px = List[Float64](capacity=len(plot.x_data))
    var py = List[Float64](capacity=len(plot.x_data))
    for i in range(len(plot.x_data)):
        px.append(x_scale.to_pixel(plot.x_data[i]))
        py.append(y_scale.to_pixel(plot.y_data[i]))
    # Same sub-pixel thinning the stroked path gets; the fill's top edge is
    # that curve.
    var thinned = _decimate_to_pixel_columns(px, py)
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
            shows on hover; defaults to `False`. Off by default because
            a title costs roughly as much as the point element itself,
            so a dense scatter's SVG about doubles -- see
            `Plot.mark_point()`'s own `tooltips` parameter.
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
        from dataviz.plot import save

        def main() raises:
            var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
            var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

            var c = scatter(x, y)
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
        from std.math import sin

        from dataviz import line
        from dataviz.plot import save
        from dataviz.colors import BROWN
        from dataviz.theme import Theme

        def main() raises:
            var x = List[Float64]()
            var y = List[Float64]()
            for i in range(40):
                var t = Float64(i) * 0.25
                x.append(t)
                y.append(sin(t) * 10.0 + t * 0.5)

            var c = line(
                x,
                y,
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
        from dataviz.plot import save
        from dataviz.theme import Theme
        from dataviz.colors import SEAGREEN

        def main() raises:
            # x=0.0 ("2023"), x=1.0 ("2024") -- revenue, in millions.
            var x: List[Float64] = [0.0, 1.0]
            var revenue: List[Float64] = [42.0, 61.0]

            var c = line(
                x,
                revenue,
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
    """
    var plot = Plot().mark_line().encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def line[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
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
        from std.math import sin

        from dataviz import area
        from dataviz.plot import save
        from dataviz.colors import STEELBLUE
        from dataviz.theme import Theme

        def main() raises:
            var x = List[Float64]()
            var y = List[Float64]()
            for i in range(30):
                var t = Float64(i) * 0.3
                x.append(t)
                y.append(sin(t) * 4.0 + 6.0)

            var c = area(x, y, theme=Theme(mark_color=STEELBLUE))
            save(c, "docs/src/examples/out_area.svg")
        ```
    """
    var plot = Plot().mark_area().encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def area[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
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
        theme=theme,
        width=width,
        height=height,
        title=title,
        x_title=x_title,
        y_title=y_title,
    )
