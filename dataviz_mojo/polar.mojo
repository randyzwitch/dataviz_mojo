from std.math import cos, pi, sin

from canvas_mojo.color import Color
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _empty_result,
    _rendered,
)
from dataviz_mojo.theme import Theme

# How many evenly-spaced concentric grid rings/angular spokes the polar
# grid draws -- fixed constants, not `Theme` fields, the same
# "not worth a knob until something concrete needs one" reasoning
# every other module-level layout constant here already follows.
# `_POLAR_GRID_SPOKES = 12` matches ECharts' own default `splitNumber`
# for a polar angle axis (see ECharts.jl's own `polar()` docs).
comptime _POLAR_GRID_RINGS = 4
comptime _POLAR_GRID_SPOKES = 12


struct _PolarPoint(Movable):
    """`_polar_point`'s own return value -- a named struct, not a raw
    tuple, the same multi-value-return convention every other function
    here follows (`_LabelsFrame`, `MinMax`, `Ticks`, ...)."""

    var x: Float64
    var y: Float64

    def __init__(out self, x: Float64, y: Float64):
        self.x = x
        self.y = y


def _polar_point(cx: Float64, cy: Float64, angle: Float64, radius: Float64) -> _PolarPoint:
    """Angle/radius -> pixel (x, y), the one shared primitive every
    polar-coordinate mark in this package ultimately reduces to.
    `angle=0` is 3 o'clock (east), increasing `angle` sweeps clockwise
    -- not the counterclockwise "east, then north" convention plain
    trigonometry usually means, but the same clockwise convention
    `Mark.ARC`/`Mark.CHORD`/`Mark.NIGHTINGALE`/`Mark.POLAR_BAR` already
    establish (a real-world clock face's own reading direction; see
    `_render_arc`'s own docstring for why -- pixel y increases
    downward, which flips the usual counterclockwise-is-positive
    reading), kept identical here so every polar mark in this package
    agrees on which way an angle turns. `radius` is a plain pixel
    distance from `(cx, cy)`, already scaled by whichever caller needs
    it -- this function does no scaling of its own.
    """
    return _PolarPoint(cx + radius * cos(angle), cy + radius * sin(angle))


def _draw_polar_grid[
    T: DrawTarget
](mut target: T, cx: Float64, cy: Float64, max_radius: Float64, theme: Theme) raises:
    """The polar coordinate system itself: `_POLAR_GRID_RINGS` evenly
    spaced concentric circles (one full `Path.arc_to` sweep each,
    stroked) plus `_POLAR_GRID_SPOKES` straight radial lines from the
    center out to `max_radius` -- the polar equivalent of a cartesian
    plot's own gridlines, drawn in `theme.gridline_color` the same way
    `_draw_categorical_axis_frame`'s own gridlines are. No tick labels
    (neither the radius rings' own values nor the angle spokes' own
    degrees) -- a real, deliberate v1 simplification (the same kind
    `Mark.CHORD`'s own straight-rim ribbons or `Mark.VIOLIN`'s own
    std-only bandwidth already are): the grid alone already
    communicates the coordinate system's own shape, and a numeric
    label placed *around* a circle (curved baseline, radial
    orientation) is a real, separate typesetting problem this package
    has no existing machinery for -- worth solving if a concrete need
    for exact radius/angle readout ever asks for it, not built
    speculatively now.
    """
    for i in range(1, _POLAR_GRID_RINGS + 1):
        var r = max_radius * Float64(i) / Float64(_POLAR_GRID_RINGS)
        var ring = Path()
        ring.move_to(cx + r, cy)
        ring.arc_to(cx, cy, r, 0.0, 2.0 * pi)
        target.stroke_path_aa(ring, theme.gridline_color)

    for i in range(_POLAR_GRID_SPOKES):
        var angle = 2.0 * pi * Float64(i) / Float64(_POLAR_GRID_SPOKES)
        var tip = _polar_point(cx, cy, angle, max_radius)
        target.draw_line_aa(Int(cx), Int(cy), Int(tip.x), Int(tip.y), theme.gridline_color)


def _render_polar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.POLAR` plot: `encode_polar()`'s own `angle`/
    `radius` pairs, connected in row order by one stroked polyline
    (`_build_line_path`-style, but there's no smoothing knob here --
    a polar line's own shape *is* the data, not a cartesian curve fit)
    plus a small filled circle marker at each point, drawn over
    `_draw_polar_grid`'s own coordinate system.

    `angle` is used exactly as given, in radians, completely
    unscaled and unwrapped -- unlike every other continuous channel
    in this package, there's no `_data_extent` padding or domain
    normalization step: a caller plotting `angle` values beyond
    `2*pi` (ECharts.jl's own "spiral" example, angle extending past a
    full turn) gets a real spiral outward, not a wrapped-and-
    overlapping mess `mod 2*pi` would produce. `radius` *is* scaled,
    linearly, from `[0, max(radius)]` to `[0, max_radius]` -- always
    zero-anchored (never padded away from zero the way `_data_extent`
    pads other continuous axes), the same "a magnitude axis must
    include its own zero" reasoning `_zero_baseline_y_extent` already
    gives for `Mark.BAR`/`Mark.AREA`: the chart's own center *is* the
    zero point a polar radius axis measures from, not an arbitrary
    coordinate.

    Every `radius` value must be non-negative (checked at render()
    time, the same "raise, don't silently misrepresent" stance every
    other value-validated mark here takes) -- a negative radius has no
    polar meaning without redefining the whole coordinate system.

    No legend, no axis-frame text -- a single, unlabeled series (no
    `Plot.encode_grouped_bar`-style multi-series support yet, a real
    v1 scope choice; see `_draw_polar_grid`'s own docstring for the
    matching "no tick labels" one), so there's nothing to key a legend
    by, the same reason a plain `Mark.LINE`/`Mark.POINT` series draws
    none either.
    """
    if len(plot._polar_angle) != len(plot._polar_radius):
        raise Error(
            "Plot.encode_polar(): angle and radius must have the same length"
            " (got "
            + String(len(plot._polar_angle))
            + " and "
            + String(len(plot._polar_radius))
            + ")"
        )

    var theme = plot._theme
    if len(plot._polar_angle) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for r in plot._polar_radius:
        if r < 0.0:
            raise Error("Plot: Mark.POLAR radius values must be non-negative (got " + String(r) + ")")

    var sc = _Scaled(theme)
    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9

    if theme.show_gridlines:
        _draw_polar_grid(target, cx, cy, max_radius, theme)

    var max_r = 0.0
    for r in plot._polar_radius:
        if r > max_r:
            max_r = r

    var path = Path()
    for i in range(len(plot._polar_angle)):
        var radius_px = max_radius * (plot._polar_radius[i] / max_r) if max_r > 0.0 else 0.0
        var pt = _polar_point(cx, cy, plot._polar_angle[i], radius_px)
        if i == 0:
            path.move_to(pt.x, pt.y)
        else:
            path.line_to(pt.x, pt.y)
    target.stroke_path_aa(path, theme.mark_color, sc.line_width)

    for i in range(len(plot._polar_angle)):
        var radius_px = max_radius * (plot._polar_radius[i] / max_r) if max_r > 0.0 else 0.0
        var pt = _polar_point(cx, cy, plot._polar_angle[i], radius_px)
        target.fill_circle_aa(Int(pt.x), Int(pt.y), Int(sc.point_radius), theme.mark_color)

    return _RenderResult(List[_TextRequest](), plot_x0, plot_y0, plot_x1, plot_y1)


def polar(
    angle: List[Float64],
    radius: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A polar-coordinate line plot -- `Mark.POLAR` over `angle`
    (radians, used exactly as given -- values beyond `2*pi` spiral
    outward rather than wrapping) and `radius` (linearly scaled from
    `[0, max(radius)]`, always zero-anchored at the chart's own
    center; every value must be non-negative). See `_render_polar`'s
    own docstring for the full reasoning."""
    var plot = Plot().mark_polar().encode_polar(angle=angle, radius=radius)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
