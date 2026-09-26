"""Pattern fills for filled marks (#842): hatch lines and dots drawn
over a shape's flat fill, so a series reads without its color."""

from std.math import cos, sin, pi, floor, ceil, sqrt
from canvas.color import Color
from canvas.path import FillRule, Path
from canvas.shapes.lines import LineCap
from canvas.vector.draw_target import DrawTarget


struct HatchStyle(Copyable, ImplicitlyCopyable, Movable):
    """A pattern drawn over a filled shape, dealt per category when
    `Theme.fill_pattern_by_category` is on.

    Color alone cannot carry a series for a reader with a color-vision
    deficiency or on a grayscale printout, and a filled area has no
    marker shape or line dash to fall back on the way a scatter or a
    line does. A pattern is that second channel for fills. The first
    category stays solid, so a chart with one series looks as it did.
    """

    var _value: Int

    comptime NONE = Self(0)
    """No pattern: the flat fill alone."""
    comptime DIAGONAL = Self(1)
    """Lines rising left to right, at 45 degrees."""
    comptime HORIZONTAL = Self(2)
    """Horizontal lines."""
    comptime CROSS = Self(3)
    """Horizontal and vertical lines: a grid."""
    comptime BACK_DIAGONAL = Self(4)
    """Lines falling left to right, at 45 degrees."""
    comptime VERTICAL = Self(5)
    """Vertical lines."""
    comptime DOTS = Self(6)
    """A staggered grid of dots."""
    comptime DIAGONAL_CROSS = Self(7)
    """Both diagonals: a diamond lattice."""

    def __init__(out self, value: Int):
        """Prefer the comptime constants over constructing one directly.

        Args:
            value: 0 to 7, in the order the constants are declared.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        return self._value != other._value

    def name(self) -> String:
        """This style's constant name, for messages.

        Returns:
            The constant's name, or "HatchStyle(<n>)" outside them.
        """
        if self._value == 0:
            return "NONE"
        if self._value == 1:
            return "DIAGONAL"
        if self._value == 2:
            return "HORIZONTAL"
        if self._value == 3:
            return "CROSS"
        if self._value == 4:
            return "BACK_DIAGONAL"
        if self._value == 5:
            return "VERTICAL"
        if self._value == 6:
            return "DOTS"
        if self._value == 7:
            return "DIAGONAL_CROSS"
        return "HatchStyle(" + String(self._value) + ")"


def _hatch_for_index(index: Int) -> HatchStyle:
    """The pattern category `index` gets: the eight styles in the order
    they are declared, `NONE` first, dealt the way the palette deals
    colors, so category `i`'s pattern and color both come from `i`."""
    return HatchStyle(index % 8)


def _hatch_color(fill: Color, background: Color) -> Color:
    """The color a pattern is drawn in over `fill`: the chart background
    at partial opacity, so the pattern reads as a lighter texture on
    any fill and never introduces a color of its own."""
    return background.with_alpha(UInt8(191)).blend_over(fill)


def _hatch_line_family[
    T: DrawTarget
](
    mut target: T,
    xs: List[Float64],
    ys: List[Float64],
    angle: Float64,
    spacing: Float64,
    width: Float64,
    color: Color,
):
    """Parallel lines at `angle` (radians, 0 along +x), `spacing` apart,
    clipped to the polygon `xs`/`ys` by the even-odd rule.

    The lines sit on a grid anchored at the canvas origin rather than
    at the shape, so two shapes side by side hatch as one continuous
    texture instead of each starting its own phase.
    """
    var n = len(xs)
    if n < 3:
        return
    var ux = cos(angle)
    var uy = sin(angle)
    # The normal: distance of every hatch line from the origin.
    var nx = -uy
    var ny = ux
    var dmin = xs[0] * nx + ys[0] * ny
    var dmax = dmin
    for i in range(1, n):
        var d = xs[i] * nx + ys[i] * ny
        dmin = min(dmin, d)
        dmax = max(dmax, d)
    var k = Int(ceil(dmin / spacing))
    while Float64(k) * spacing <= dmax:
        var d = Float64(k) * spacing
        var ts = List[Float64]()
        for i in range(n):
            var j = (i + 1) % n
            var da = xs[i] * nx + ys[i] * ny
            var db = xs[j] * nx + ys[j] * ny
            # Half-open, so a line through a vertex counts it once.
            if (da <= d and d < db) or (db <= d and d < da):
                var t = (d - da) / (db - da)
                var px = xs[i] + t * (xs[j] - xs[i])
                var py = ys[i] + t * (ys[j] - ys[i])
                ts.append(px * ux + py * uy)
        sort(ts)
        var m = 0
        while m + 1 < len(ts):
            var t0 = ts[m]
            var t1 = ts[m + 1]
            target.draw_line_aa(
                d * nx + t0 * ux,
                d * ny + t0 * uy,
                d * nx + t1 * ux,
                d * ny + t1 * uy,
                color,
                width=width,
                cap=LineCap.BUTT,
            )
            m += 2
        k += 1


def _inside(
    xs: List[Float64], ys: List[Float64], px: Float64, py: Float64
) -> Bool:
    """Even-odd point-in-polygon, the rule the line family uses."""
    var inside = False
    var n = len(xs)
    var j = n - 1
    for i in range(n):
        if (ys[i] > py) != (ys[j] > py):
            var x = xs[i] + (py - ys[i]) / (ys[j] - ys[i]) * (xs[j] - xs[i])
            if px < x:
                inside = not inside
        j = i
    return inside


def _hatch_polygon[
    T: DrawTarget
](
    mut target: T,
    xs: List[Float64],
    ys: List[Float64],
    style: HatchStyle,
    fill: Color,
    background: Color,
    scale: Float64,
):
    """Draw `style` over the polygon `xs`/`ys`, already filled with
    `fill`. `scale` is the theme's, so the pattern's spacing and weight
    grow with the rest of the chart. `NONE` draws nothing.
    """
    if style == HatchStyle.NONE or len(xs) < 3:
        return
    var color = _hatch_color(fill, background)
    var spacing = 6.0 * scale
    var width = 1.0 * scale
    if style == HatchStyle.DOTS:
        var x0 = xs[0]
        var x1 = xs[0]
        var y0 = ys[0]
        var y1 = ys[0]
        for i in range(len(xs)):
            x0 = min(x0, xs[i])
            x1 = max(x1, xs[i])
            y0 = min(y0, ys[i])
            y1 = max(y1, ys[i])
        var row = Int(floor(y0 / spacing))
        while Float64(row) * spacing <= y1:
            var cy = Float64(row) * spacing
            var shift = spacing / 2.0 if row % 2 != 0 else 0.0
            var col = Int(floor((x0 - shift) / spacing))
            while Float64(col) * spacing + shift <= x1:
                var cx = Float64(col) * spacing + shift
                if _inside(xs, ys, cx, cy):
                    target.fill_circle_aa(cx, cy, 1.1 * scale, color)
                col += 1
            row += 1
        return
    if style == HatchStyle.HORIZONTAL or style == HatchStyle.CROSS:
        _hatch_line_family(target, xs, ys, 0.0, spacing, width, color)
    if style == HatchStyle.VERTICAL or style == HatchStyle.CROSS:
        _hatch_line_family(target, xs, ys, pi / 2.0, spacing, width, color)
    # Screen y points down, so a line rising left to right runs at -45.
    if style == HatchStyle.DIAGONAL or style == HatchStyle.DIAGONAL_CROSS:
        _hatch_line_family(target, xs, ys, -pi / 4.0, spacing, width, color)
    if style == HatchStyle.BACK_DIAGONAL or style == HatchStyle.DIAGONAL_CROSS:
        _hatch_line_family(target, xs, ys, pi / 4.0, spacing, width, color)


def _hatch_rect[
    T: DrawTarget
](
    mut target: T,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    style: HatchStyle,
    fill: Color,
    background: Color,
    scale: Float64,
):
    """`_hatch_polygon` over the rect `fill_rect(x, y, width, height)`
    covers."""
    if width <= 0 or height <= 0:
        return
    var x0 = Float64(x)
    var y0 = Float64(y)
    var x1 = Float64(x + width)
    var y1 = Float64(y + height)
    var xs: List[Float64] = [x0, x1, x1, x0]
    var ys: List[Float64] = [y0, y0, y1, y1]
    _hatch_polygon(target, xs, ys, style, fill, background, scale)


def _hatch_rect[
    T: DrawTarget
](
    mut target: T,
    x: Float64,
    y: Float64,
    width: Float64,
    height: Float64,
    style: HatchStyle,
    fill: Color,
    background: Color,
    scale: Float64,
):
    """`_hatch_rect` for the `Float64` `fill_rect` a snapped band
    fills."""
    if width <= 0.0 or height <= 0.0:
        return
    var xs: List[Float64] = [x, x + width, x + width, x]
    var ys: List[Float64] = [y, y, y + height, y + height]
    _hatch_polygon(target, xs, ys, style, fill, background, scale)


def _sector_polygon(
    cx: Float64,
    cy: Float64,
    inner: Float64,
    outer: Float64,
    start: Float64,
    end: Float64,
) -> Tuple[List[Float64], List[Float64]]:
    """A ring sector (a wedge when `inner` is 0) as a polygon, the arcs
    sampled finely enough that the hatch meets the curved edge to well
    under a pixel. Angles are radians from +x, as `fill_arc_aa` takes
    them."""
    var steps = max(2, Int(ceil(abs(end - start) * max(outer, 1.0) / 2.0)))
    var xs = List[Float64]()
    var ys = List[Float64]()
    for i in range(steps + 1):
        var a = start + (end - start) * Float64(i) / Float64(steps)
        xs.append(cx + outer * cos(a))
        ys.append(cy + outer * sin(a))
    if inner > 0.0:
        for i in range(steps, -1, -1):
            var a = start + (end - start) * Float64(i) / Float64(steps)
            xs.append(cx + inner * cos(a))
            ys.append(cy + inner * sin(a))
    else:
        xs.append(cx)
        ys.append(cy)
    return (xs^, ys^)


def _hatch_sector[
    T: DrawTarget
](
    mut target: T,
    cx: Float64,
    cy: Float64,
    inner: Float64,
    outer: Float64,
    start: Float64,
    end: Float64,
    style: HatchStyle,
    fill: Color,
    background: Color,
    scale: Float64,
):
    """`_hatch_polygon` over what `fill_arc_aa` (inner 0) or
    `fill_ring_sector_aa` covers."""
    if style == HatchStyle.NONE:
        return
    var poly = _sector_polygon(cx, cy, inner, outer, start, end)
    _hatch_polygon(target, poly[0], poly[1], style, fill, background, scale)


def _hatch_path_family[
    T: DrawTarget
](
    mut target: T,
    path: Path,
    box: Tuple[Float64, Float64, Float64, Float64],
    angle: Float64,
    spacing: Float64,
    width: Float64,
    color: Color,
):
    """`_hatch_line_family` for a `Path` whose outline is curved: each
    line is walked in half-pixel steps and drawn where `Path.in_fill`
    (nonzero, as the marks fill) holds, so the pattern follows the
    same flattened edge the fill does."""
    var ux = cos(angle)
    var uy = sin(angle)
    var nx = -uy
    var ny = ux
    var corners_x: List[Float64] = [box[0], box[2], box[2], box[0]]
    var corners_y: List[Float64] = [box[1], box[1], box[3], box[3]]
    var dmin = corners_x[0] * nx + corners_y[0] * ny
    var dmax = dmin
    var tmin = corners_x[0] * ux + corners_y[0] * uy
    var tmax = tmin
    for i in range(1, 4):
        var d = corners_x[i] * nx + corners_y[i] * ny
        var t = corners_x[i] * ux + corners_y[i] * uy
        dmin = min(dmin, d)
        dmax = max(dmax, d)
        tmin = min(tmin, t)
        tmax = max(tmax, t)
    var step = 0.5
    var k = Int(ceil(dmin / spacing))
    while Float64(k) * spacing <= dmax:
        var d = Float64(k) * spacing
        var run_start = 0.0
        var in_run = False
        var t = tmin
        while t <= tmax + step:
            var px = d * nx + t * ux
            var py = d * ny + t * uy
            var inside = t <= tmax and path.in_fill(
                px, py, fill_rule=FillRule.NONZERO
            )
            if inside and not in_run:
                run_start = t
                in_run = True
            elif not inside and in_run:
                var t_end = t - step
                if t_end > run_start:
                    target.draw_line_aa(
                        d * nx + run_start * ux,
                        d * ny + run_start * uy,
                        d * nx + t_end * ux,
                        d * ny + t_end * uy,
                        color,
                        width=width,
                        cap=LineCap.BUTT,
                    )
                in_run = False
            t += step
        k += 1


def _hatch_path[
    T: DrawTarget
](
    mut target: T,
    path: Path,
    style: HatchStyle,
    fill: Color,
    background: Color,
    scale: Float64,
):
    """`_hatch_polygon` for a `Path`, for the marks whose fills are
    curved or stepped outlines (`Mark.FUNNEL`, `STREAMGRAPH`)."""
    if style == HatchStyle.NONE:
        return
    var color = _hatch_color(fill, background)
    var spacing = 6.0 * scale
    var width = 1.0 * scale
    var box = path.bounds()
    if style == HatchStyle.DOTS:
        var row = Int(floor(box[1] / spacing))
        while Float64(row) * spacing <= box[3]:
            var cy = Float64(row) * spacing
            var shift = spacing / 2.0 if row % 2 != 0 else 0.0
            var col = Int(floor((box[0] - shift) / spacing))
            while Float64(col) * spacing + shift <= box[2]:
                var cx = Float64(col) * spacing + shift
                if path.in_fill(cx, cy, fill_rule=FillRule.NONZERO):
                    target.fill_circle_aa(cx, cy, 1.1 * scale, color)
                col += 1
            row += 1
        return
    if style == HatchStyle.HORIZONTAL or style == HatchStyle.CROSS:
        _hatch_path_family(target, path, box, 0.0, spacing, width, color)
    if style == HatchStyle.VERTICAL or style == HatchStyle.CROSS:
        _hatch_path_family(target, path, box, pi / 2.0, spacing, width, color)
    if style == HatchStyle.DIAGONAL or style == HatchStyle.DIAGONAL_CROSS:
        _hatch_path_family(target, path, box, -pi / 4.0, spacing, width, color)
    if style == HatchStyle.BACK_DIAGONAL or style == HatchStyle.DIAGONAL_CROSS:
        _hatch_path_family(target, path, box, pi / 4.0, spacing, width, color)
