"""Point-marker shapes used to distinguish categories without color alone."""

from canvas.color import Color
from canvas.fill_rule import FillRule
from std.math import pi

from canvas.geometry import round_to_int, snap_to_pixel_edge
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget


struct PointShape(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime CIRCLE = Self(0)
    comptime SQUARE = Self(1)
    comptime TRIANGLE = Self(2)
    comptime DIAMOND = Self(3)
    comptime CROSS = Self(4)
    comptime X = Self(5)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


def default_marker_shapes() -> List[PointShape]:
    """Return the fixed shape cycle used by `Theme.shape_by_category`.

    Returns:
        6 visually distinct point shapes, cycled via modulo for more
        categories than that.
    """
    return [
        PointShape.CIRCLE,
        PointShape.SQUARE,
        PointShape.TRIANGLE,
        PointShape.DIAMOND,
        PointShape.CROSS,
        PointShape.X,
    ]


# X vertex offset: cos(45 degrees).
comptime _COS_45 = 0.7071067811865476


def _fill_shape_aa[
    T: DrawTarget
](
    mut target: T,
    cx: Int,
    cy: Int,
    radius: Int,
    shape: PointShape,
    color: Color,
) raises:
    """Draw one `shape` centered at `(cx, cy)`, sized to `radius`. Called per
    point by `_draw_point_layer` (continuous.mojo) and per legend swatch
    by `_draw_legend` (legend.mojo) when `Theme.shape_by_category` is on. `radius` is already
    `Theme.scale`-scaled by the caller.

    Every shape reaches exactly `radius` pixels from center along its
    widest axis, so turning `shape_by_category` on never changes apparent
    point size. CROSS/X stroke width also scales with `radius`. All shapes
    fill solid; there is no hollow variant.
    """
    if shape == PointShape.CIRCLE:
        target.fill_circle_aa(cx, cy, radius, color)
    elif shape == PointShape.SQUARE:
        target.fill_rect(
            cx - radius, cy - radius, 2 * radius, 2 * radius, color
        )
    elif shape == PointShape.TRIANGLE:
        # A regular polygon with its first vertex straight up, which in
        # pixel coordinates (y growing downward) is -pi/2. The vertex
        # math used to be written out here; canvas owns it now (#579).
        var path = Path()
        path.regular_polygon(
            Float64(cx), Float64(cy), Float64(radius), 3, -pi / 2.0
        )
        target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)
    elif shape == PointShape.DIAMOND:
        # A square on its corner, so the same first-vertex rule.
        var path = Path()
        path.regular_polygon(
            Float64(cx), Float64(cy), Float64(radius), 4, -pi / 2.0
        )
        target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)
    elif shape == PointShape.CROSS:
        var width = Float64(radius) * 0.65
        target.draw_line_aa(
            cx, cy - radius, cx, cy + radius, color, width=width
        )
        target.draw_line_aa(
            cx - radius, cy, cx + radius, cy, color, width=width
        )
    else:
        # PointShape.X: CROSS's two strokes rotated 45 degrees.
        var diag = round_to_int(Float64(radius) * _COS_45)
        var width = Float64(radius) * 0.65
        target.draw_line_aa(
            cx - diag, cy - diag, cx + diag, cy + diag, color, width=width
        )
        target.draw_line_aa(
            cx - diag, cy + diag, cx + diag, cy - diag, color, width=width
        )


def _fill_shape_aa[
    T: DrawTarget
](
    mut target: T,
    cx: Float64,
    cy: Float64,
    radius: Float64,
    shape: PointShape,
    color: Color,
) raises:
    """`_fill_shape_aa` in `Float64` geometry, so a marker sits at its
    data position rather than at the nearest whole pixel.

    Only `SQUARE` snaps. It is the one shape drawn as an axis-aligned
    filled rect, and it is crisp today where the other four are
    antialiased on every side; snapping its two edges keeps that, and at
    marker sizes the half pixel it costs is invisible beside a circle
    drawn from the same point.

    Every shape reaches exactly `radius` pixels from center along its
    widest axis, so turning `shape_by_category` on never changes apparent
    point size. CROSS/X stroke width also scales with `radius`. All shapes
    fill solid; there is no hollow variant.
    """
    if shape == PointShape.CIRCLE:
        target.fill_circle_aa(cx, cy, radius, color)
    elif shape == PointShape.SQUARE:
        var x0 = snap_to_pixel_edge(cx - radius)
        var x1 = snap_to_pixel_edge(cx + radius)
        var y0 = snap_to_pixel_edge(cy - radius)
        var y1 = snap_to_pixel_edge(cy + radius)
        target.fill_rect(x0, y0, x1 - x0, y1 - y0, color)
    elif shape == PointShape.TRIANGLE:
        # First vertex straight up, which is -pi/2 with pixel y growing
        # downward. See the Int overload above.
        var path = Path()
        path.regular_polygon(cx, cy, radius, 3, -pi / 2.0)
        target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)
    elif shape == PointShape.DIAMOND:
        var path = Path()
        path.regular_polygon(cx, cy, radius, 4, -pi / 2.0)
        target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)
    elif shape == PointShape.CROSS:
        var width = radius * 0.65
        target.draw_line_aa(
            cx, cy - radius, cx, cy + radius, color, width=width
        )
        target.draw_line_aa(
            cx - radius, cy, cx + radius, cy, color, width=width
        )
    else:
        # PointShape.X: CROSS's two strokes rotated 45 degrees.
        var diag = radius * _COS_45
        var width = radius * 0.65
        target.draw_line_aa(
            cx - diag, cy - diag, cx + diag, cy + diag, color, width=width
        )
        target.draw_line_aa(
            cx - diag, cy + diag, cx + diag, cy - diag, color, width=width
        )
