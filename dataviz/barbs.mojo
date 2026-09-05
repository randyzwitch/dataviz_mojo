from std.math import atan2, sqrt

from canvas.fill_rule import FillRule
from canvas.geometry import Transform2D, _round_to_int
from canvas.path import Path
from dataviz.plot import _LazyFontCache, _LegendLayout
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
    _require_non_empty,
)
from dataviz.theme import Theme


struct _BarbsData(Copyable, Movable):
    """One (x, y, u, v) row per wind barb, plus the glyph knobs
    `mark_barbs()` sets. See `encode_barbs()`. Stored on `Plot._barbs`.

    `u`/`v` are the vector's components in the same units as each
    other; `hypot(u, v)` is the speed the glyph decomposes into flags,
    barbs and a half barb. The unit is the caller's -- knots by
    meteorological convention, since the 50/10/5 increments below are
    the knot ones.
    """

    var x: List[Float64]
    var y: List[Float64]
    var u: List[Float64]
    var v: List[Float64]
    var length: Float64
    var flip: Bool

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.u = List[Float64]()
        self.v = List[Float64]()
        self.length = 28.0
        self.flip = False


# Feature sizes as fractions of the staff length, matching matplotlib's
# `barbs(sizes=...)` defaults so a glyph drawn here reads the same as one
# drawn there: 'spacing', 'height', 'width' and 'emptybarb'.
comptime _BARB_SPACING = 0.125
comptime _BARB_HEIGHT = 0.40
comptime _FLAG_WIDTH = 0.25
comptime _EMPTY_RADIUS = 0.15


struct _BarbCounts(Copyable, Movable):
    """How many of each feature a speed decomposes into: `flags` at 50
    units each, `barbs` at 10, then a `half` barb at 5. `calm` is the
    "rounds to nothing" case, drawn as a bare circle instead of a staff.
    """

    var flags: Int
    var barbs: Int
    var half: Bool
    var calm: Bool

    def __init__(out self, flags: Int, barbs: Int, half: Bool, calm: Bool):
        self.flags = flags
        self.barbs = barbs
        self.half = half
        self.calm = calm


def _barb_counts(speed: Float64) -> _BarbCounts:
    """Decompose `speed` into flags (50), full barbs (10) and a half
    barb (5), the standard station-model reading.

    The speed is rounded to the nearest 5 first, as matplotlib's
    `_find_tails` does, so 7.4 draws one half barb rather than nothing
    and 12.6 draws a full barb plus a half. A speed rounding to 0 (under
    2.5) is `calm`: no staff, just the small circle meteorologists read
    as "wind under the plotting threshold".
    """
    var rounded = Float64(Int(speed / 5.0 + 0.5)) * 5.0
    var n_flags = Int(rounded / 50.0)
    var rest = rounded - Float64(n_flags) * 50.0
    var n_barbs = Int(rest / 10.0)
    rest -= Float64(n_barbs) * 10.0
    var half = rest >= 5.0
    var calm = n_flags == 0 and n_barbs == 0 and not half
    return _BarbCounts(n_flags, n_barbs, half, calm)


def _barb_glyph(
    mut strokes: List[Path],
    mut pennants: List[Path],
    counts: _BarbCounts,
    length: Float64,
    flip: Bool,
) raises:
    """Build one barb glyph in glyph-local coordinates: the staff runs
    from the origin along +x to `(length, 0)`, and every feature hangs
    off the far end, working inward -- flags first, then full barbs,
    then the half barb, which is how a station model is read.

    Appends two paths, one to each list, because the two halves are
    drawn differently: the staff and the barb ticks are stroked, while
    flags are filled pennants. The pennant path is empty when the speed
    carries no flags (a 10-unit wind), and appending to both keeps the
    two lists index-aligned for the caller's speed-bucket cache.

    `flip` mirrors every feature across the staff, the southern-
    hemisphere convention matplotlib spells `flip_barb`.

    The caller rotates and translates this into place, so one glyph is
    built per distinct speed bucket rather than per point.
    """
    var side = 1.0 if flip else -1.0
    var spacing = _BARB_SPACING * length
    var height = _BARB_HEIGHT * length
    var flag_width = _FLAG_WIDTH * length

    var stroke = Path()
    var flags = Path()

    stroke.move_to(0.0, 0.0)
    stroke.line_to(length, 0.0)

    var pos = length

    for _ in range(counts.flags):
        # A pennant: a filled right triangle with its perpendicular edge
        # at the outboard end, so consecutive flags read as separate
        # triangles rather than one long wedge.
        flags.move_to(pos, 0.0)
        flags.line_to(pos, side * height)
        flags.line_to(pos - flag_width, 0.0)
        flags.close()
        pos -= flag_width

    if counts.flags > 0:
        pos -= spacing

    for _ in range(counts.barbs):
        stroke.move_to(pos, 0.0)
        stroke.line_to(pos - spacing, side * height)
        pos -= spacing

    if counts.half:
        # A lone half barb sits one spacing in from the tip rather than
        # on it, so 5 units is not mistaken for a full barb drawn short
        # -- the same inset matplotlib applies.
        if counts.flags == 0 and counts.barbs == 0:
            pos -= spacing
        stroke.move_to(pos, 0.0)
        stroke.line_to(pos - spacing * 0.5, side * height * 0.5)

    strokes.append(stroke^)
    pennants.append(flags^)


def _render_barbs[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: _LazyFontCache,
) raises -> _RenderResult:
    """Render a `Mark.BARBS` plot: `encode_barbs()`'s continuous `x`/`y`
    positions with a wind barb at each, the vector field convention
    matplotlib's `barbs()` draws.

    Layout is the shared continuous-axis frame every `Mark.POINT`-shaped
    mark uses (`_draw_continuous_axis_frame`), so the axes, gridlines and
    ticks come out identical to a scatter of the same positions; only the
    per-point glyph differs.

    Each glyph's staff points *upwind* -- toward where the wind is coming
    from, not where it is going -- which is what a station model means and
    the opposite of an arrow drawn along `(u, v)`. In pixel space, where y
    grows downward, that direction is `(-u, v)`, so the rotation is
    `atan2(v, -u)`; a wind out of the north (`u = 0`, `v = -1`) draws a
    staff pointing up the page.

    Speed is `hypot(u, v)` in the caller's own unit, decomposed by
    `_barb_counts` against the knot increments (50/10/5). Glyphs are built
    once per distinct speed bucket and reused: a field of 10k barbs
    holding a handful of distinct speeds builds a handful of paths, then
    pays only one `Path.transformed` per point. (canvas v0.13.0's
    `DrawTarget` has no transform stack, so the per-point transform
    allocates a path; a `save`/`translate`/`rotate` API would remove
    even that.)

    Glyphs are not clipped to the plot rect, so a barb on a point at the
    very edge of the data can reach into the margin -- matplotlib behaves
    the same way.
    """
    var n = len(plot._barbs.x)
    if (
        len(plot._barbs.y) != n
        or len(plot._barbs.u) != n
        or len(plot._barbs.v) != n
    ):
        raise Error(
            "Plot.encode_barbs(): x, y, u, and v must all have the same length"
            " (got "
            + String(n)
            + " x values, "
            + String(len(plot._barbs.y))
            + " y values, "
            + String(len(plot._barbs.u))
            + " u values, "
            + String(len(plot._barbs.v))
            + " v values)"
        )
    _require_non_empty(n, "Plot.encode_barbs()")
    if plot._barbs.length <= 0.0:
        raise Error(
            "Plot.mark_barbs(): length must be positive (got "
            + String(plot._barbs.length)
            + ")"
        )

    var theme = plot._theme
    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(plot._barbs.x),
        _data_extent(plot._barbs.y),
        theme,
        _LegendLayout(),
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var length = plot._barbs.length * frame.sc.scale
    var stroke_width = frame.sc.scale
    var empty_radius = _round_to_int(_EMPTY_RADIUS * length)

    # One glyph per distinct speed bucket, built lazily. `keys` is the
    # rounded-to-5 speed as an integer; the bucket count is small (a
    # 100-knot field has 20 of them), so a linear scan beats hashing.
    var keys = List[Int]()
    var strokes = List[Path]()
    var pennants = List[Path]()

    for i in range(n):
        var u = plot._barbs.u[i]
        var v = plot._barbs.v[i]
        var speed = sqrt(u * u + v * v)
        var counts = _barb_counts(speed)

        var px = frame.x_scale.to_pixel(plot._barbs.x[i])
        var py = frame.y_scale.to_pixel(plot._barbs.y[i])

        if counts.calm:
            target.draw_ellipse_aa(
                _round_to_int(px),
                _round_to_int(py),
                empty_radius,
                empty_radius,
                theme.mark_color,
            )
            continue

        var key = Int(speed / 5.0 + 0.5)
        var slot = -1
        for k in range(len(keys)):
            if keys[k] == key:
                slot = k
                break
        if slot < 0:
            _barb_glyph(strokes, pennants, counts, length, plot._barbs.flip)
            keys.append(key)
            slot = len(keys) - 1

        # Staff direction is upwind, and pixel y grows downward: see the
        # docstring above for why this is atan2(v, -u) and not atan2(v, u).
        var xform = Transform2D(1.0, 1.0, px, py, atan2(v, -u))
        target.stroke_path_aa(
            strokes[slot].transformed(xform), theme.mark_color, stroke_width
        )
        if counts.flags > 0:
            target.fill_path_aa(
                pennants[slot].transformed(xform),
                theme.mark_color,
                fill_rule=FillRule.NONZERO,
            )

    return frame.result()


def barbs(
    x: List[Float64],
    y: List[Float64],
    u: List[Float64],
    v: List[Float64],
    length: Float64 = 28.0,
    flip: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A wind barb field: one station-model glyph per point, where the
    staff points upwind and the flags, barbs and half barb hanging off
    its end add up to the speed -- the meteorological reading of a vector
    field, and the shape matplotlib's `barbs()` draws.

    `Mark.BARBS` over continuous `x`/`y` with `u`/`v` components. Speed is
    `hypot(u, v)` in the caller's own unit, decomposed against the knot
    increments: a flag is 50, a full barb 10, a half barb 5, and a speed
    rounding below 2.5 draws the "calm" circle. See `_render_barbs`.

    Args:
        x: The continuous x position of each barb.
        y: The continuous y position of each barb.
        u: Each barb's x-component, in the same unit as `v`.
        v: Each barb's y-component, positive pointing up the page.
        length: Staff length in pixels before `Theme.scale`, so a
            HiDPI export grows the glyphs with everything else.
        flip: Mirror every feature across its staff -- the southern-
            hemisphere convention (matplotlib's `flip_barb`).
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import barbs
        from dataviz.plot import save

        def main() raises:
            var x = List[Float64]()
            var y = List[Float64]()
            var u = List[Float64]()
            var v = List[Float64]()

            # A sheared westerly: speed climbing with height, backing
            # slightly across the grid.
            for row in range(5):
                for col in range(6):
                    x.append(Float64(col))
                    y.append(Float64(row))
                    u.append(5.0 + 12.0 * Float64(row))
                    v.append(3.0 * Float64(col) - 6.0)

            var c = barbs(x, y, u, v, title="Wind field (knots)")
            save(c, "docs/src/examples/out_barbs.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_barbs(length=length, flip=flip)
        .encode_barbs(x=x, y=y, u=u, v=v)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def barbs[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    u: List[Scalar[dtype]],
    v: List[Scalar[dtype]],
    length: Float64 = 28.0,
    flip: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`barbs()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return barbs(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        _materialize_scalar_list(u),
        _materialize_scalar_list(v),
        length=length,
        flip=flip,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
