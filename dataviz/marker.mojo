"""PointShape: a fixed set of glyph shapes `Mark.POINT` can draw a
category in, in addition to color. Same small-struct-with-comptime-
constants-and-`__eq__` pattern as `Mark`/`OutputFormat`.

A distinct shape per category is redundant coding for charts that are
printed, projected, or viewed without reliable color (matplotlib's
`marker=`, ggplot2's `shape=`). See `Theme.shape_by_category` for how
it layers on top of `color_categories`.

Six shapes: past that, shapes start reading as similar at a typical
`point_radius`. CIRCLE is `Self(0)` so `default_marker_shapes()[0]`
reproduces `fill_circle_aa`'s look for a chart's first category, the
same way `default_categorical_palette()`'s first color does.
"""

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.geometry import round_to_int
from dataviz.pixel_snap import _snap_pixel_edge
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
    """The fixed shape cycle `Theme.shape_by_category` indexes into, the
    marker counterpart to `default_categorical_palette()`
    (color_scale.mojo), cycled via modulo the same way (see
    `Plot.encode`). A plain function rather than a `Theme` field for the
    `ImplicitlyCopyable` reason given in `default_categorical_palette()`'s
    docstring; there is no per-category `shape_map` override.

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


# cos(30 deg): TRIANGLE's two base vertices sit at +-30 deg either side
# of straight down from its top vertex, this fraction of `radius` out
# on the x-axis (sin(30 deg) == 0.5).
comptime _COS_30 = 0.8660254037844387
# cos(45 deg) == sin(45 deg): X's four vertices sit this fraction of
# `radius` out on both axes.
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
        var r = Float64(radius)
        var path = Path()
        path.move_to(Float64(cx), Float64(cy) - r)
        path.line_to(Float64(cx) + r * _COS_30, Float64(cy) + r * 0.5)
        path.line_to(Float64(cx) - r * _COS_30, Float64(cy) + r * 0.5)
        path.close()
        target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)
    elif shape == PointShape.DIAMOND:
        var r = Float64(radius)
        var path = Path()
        path.move_to(Float64(cx), Float64(cy) - r)
        path.line_to(Float64(cx) + r, Float64(cy))
        path.line_to(Float64(cx), Float64(cy) + r)
        path.line_to(Float64(cx) - r, Float64(cy))
        path.close()
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
        var x0 = _snap_pixel_edge(cx - radius)
        var x1 = _snap_pixel_edge(cx + radius)
        var y0 = _snap_pixel_edge(cy - radius)
        var y1 = _snap_pixel_edge(cy + radius)
        target.fill_rect(x0, y0, x1 - x0, y1 - y0, color)
    elif shape == PointShape.TRIANGLE:
        var r = radius
        var path = Path()
        path.move_to(cx, cy - r)
        path.line_to(cx + r * _COS_30, cy + r * 0.5)
        path.line_to(cx - r * _COS_30, cy + r * 0.5)
        path.close()
        target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)
    elif shape == PointShape.DIAMOND:
        var r = radius
        var path = Path()
        path.move_to(cx, cy - r)
        path.line_to(cx + r, cy)
        path.line_to(cx, cy + r)
        path.line_to(cx - r, cy)
        path.close()
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
