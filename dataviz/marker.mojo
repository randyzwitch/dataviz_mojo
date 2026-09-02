"""PointShape -- a small, fixed set of glyph shapes `Mark.POINT` can
draw a category in, instead of (well, in addition to) color. Follows
the same small-struct-with-comptime-constants-and-`__eq__` pattern
`Mark`/`OutputFormat` use, not a distinct enum mechanism.

Exists for one reason: `Theme.color_by_sign` aside, every data-driven
channel this package draws (color, size, position) collapses toward
indistinguishable gray the moment a chart is printed, projected, or
viewed by someone who can't rely on color -- a categorical scatter's
whole "which series is this point" story disappears with it. A
distinct *shape* per category is the standard fix (matplotlib's
`marker=`, ggplot2's `shape=` aesthetic): redundant coding, not a new
data encoding -- see `Theme.shape_by_category`'s own docstring for how
this package wires it in (on top of `color_categories`, not a second
independent channel).

Six shapes, not more: matplotlib/ggplot2 both default to a comparable
handful (their own most-used sets run 6-8) -- past around six, two
shapes start reading as "similar" at a typical small `point_radius`
rather than "distinct," the exact failure mode this exists to avoid.
CIRCLE is first (`Self(0)`) so `default_marker_shapes()[0]` reproduces
`fill_circle_aa`'s own long-standing look for a chart's first
category, the same "index 0 changes nothing" backward-compatibility
default `default_categorical_palette()` already gives its own first
color.
"""

from canvas.color import Color
from canvas.geometry import _round_to_int
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
    """The fixed shape cycle `Theme.shape_by_category` indexes into,
    the marker-shape counterpart to `default_categorical_palette()`
    (color_scale.mojo) -- cycled via modulo the identical way a column
    with more unique categories than entries here already cycles that
    palette (see `Plot.encode`'s docstring).

    A plain function, not a `Theme` field, for the same `List` field
    would-break-`ImplicitlyCopyable` reason `default_categorical_
    palette()`'s own docstring gives -- unlike that palette, there
    isn't yet a concrete case for a caller-supplied shape order to
    weigh against that cost, so this doesn't even have a `shape_map`-
    style per-category override the way `color_categories` has
    `Plot.encode`'s own `color_map`.

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


# cos(30 deg) -- TRIANGLE's two base vertices sit at +-30 deg either
# side of straight down from its top vertex, both at this fraction of
# `radius` out from center on the x-axis (sin(30 deg) == 0.5 exactly,
# needs no named constant of its own).
comptime _COS_30 = 0.8660254037844387
# cos(45 deg) == sin(45 deg) -- X's own four vertices sit this
# fraction of `radius` out from center on both axes.
comptime _COS_45 = 0.7071067811865476


def _fill_shape_aa[
    T: DrawTarget
](mut target: T, cx: Int, cy: Int, radius: Int, shape: PointShape, color: Color) raises:
    """Draw one `shape` centered at `(cx, cy)`, sized to `radius` --
    `_draw_point_layer`'s (plot.mojo) own per-point call, and `_draw_
    legend`'s (plot.mojo) own per-row swatch call when `Theme.shape_
    by_category` is on. `radius` is the caller's already-`Theme.scale`-
    scaled pixel radius (`_Scaled.point_radius`/`size_scale`'s own
    output) -- this function does no scaling of its own, the same
    "caller resolves the size, this just draws it" split `fill_
    circle_aa` itself already has.

    Every shape's own extent reaches exactly `radius` pixels from
    `(cx, cy)` along its widest axis -- CIRCLE's own radius, unchanged
    -- so switching a chart's `Theme.shape_by_category` on never makes
    its points read as visually larger or smaller than before, just
    differently shaped. CROSS/X are the one pair whose *ink* (stroke
    width, not extent) also scales with `radius`, since a fixed stroke
    width would read as disproportionately thick on a small `point_
    radius` chart and thin on a large one -- the same "every pixel-
    sized quantity scales together" principle `Theme.scale` itself
    documents, applied here to one shape's own two dimensions instead
    of across a whole render.

    Deliberately no `TRIANGLE`/`DIAMOND` "is this shape hollow or
    filled" option -- every shape here fills solid, the same "one
    unambiguous default, not a style matrix" scope `Theme.title_bold`'s
    own docstring argues for a single new capability.
    """
    if shape == PointShape.CIRCLE:
        target.fill_circle_aa(cx, cy, radius, color)
    elif shape == PointShape.SQUARE:
        target.fill_rect(cx - radius, cy - radius, 2 * radius, 2 * radius, color)
    elif shape == PointShape.TRIANGLE:
        var r = Float64(radius)
        var path = Path()
        path.move_to(Float64(cx), Float64(cy) - r)
        path.line_to(Float64(cx) + r * _COS_30, Float64(cy) + r * 0.5)
        path.line_to(Float64(cx) - r * _COS_30, Float64(cy) + r * 0.5)
        path.close()
        target.fill_path_aa(path, color)
    elif shape == PointShape.DIAMOND:
        var r = Float64(radius)
        var path = Path()
        path.move_to(Float64(cx), Float64(cy) - r)
        path.line_to(Float64(cx) + r, Float64(cy))
        path.line_to(Float64(cx), Float64(cy) + r)
        path.line_to(Float64(cx) - r, Float64(cy))
        path.close()
        target.fill_path_aa(path, color)
    elif shape == PointShape.CROSS:
        var width = Float64(radius) * 0.65
        target.draw_line_aa(cx, cy - radius, cx, cy + radius, color, width=width)
        target.draw_line_aa(cx - radius, cy, cx + radius, cy, color, width=width)
    else:
        # PointShape.X -- the same two-stroke plus CROSS draws,
        # rotated 45 degrees (diagonal corner-to-corner instead of
        # axis-aligned) rather than a distinct drawing strategy.
        var diag = _round_to_int(Float64(radius) * _COS_45)
        var width = Float64(radius) * 0.65
        target.draw_line_aa(cx - diag, cy - diag, cx + diag, cy + diag, color, width=width)
        target.draw_line_aa(cx - diag, cy + diag, cx + diag, cy - diag, color, width=width)
