"""`Mark.STREAMPLOT` and `streamplot()`: a vector field as streamlines --
curves a particle released into the field would follow.

A glyph field (`quiver()`, `barbs()`) shows the vector *at* each sample;
a streamplot shows where a particle *goes*. For anything about transport
-- currents, wind at scale, a force or flow field -- the streamline is
the readable form, because the eye follows a continuous curve and cannot
integrate a grid of arrows by itself.

Not `Mark.STREAMGRAPH` (streamgraph.mojo), which shares only the word:
that is a stacked area chart with a wiggle baseline, for composition over
time. This one integrates a vector field.

This is a numerical problem before it is a drawing one, and the picture
depends far more on the integrator, the seeding and the termination rule
than on the stroking. The three are `_rk4_step`, `_seed_order` and
`_trace`; each has its own docstring, and `tests/test_streamplot.mojo`
pins both against fields whose exact streamlines are known.
"""

from std.math import sqrt

from canvas.fill_rule import FillRule
from canvas.geometry import round_to_int
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import (
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
)
from dataviz.arrow import (
    _ARROW_HEAD_HALF_WIDTH,
    _ARROW_HEAD_LENGTH,
    _arrow_head_path,
)
from dataviz.color_scale import ColorScale
from dataviz.legend import _draw_continuous_color_legend, _dynamic_legend_width
from dataviz.plot import (
    Plot,
    _LegendLayout,
    _RenderResult,
    _draw_continuous_axis_frame,
    _finished,
)
from dataviz.scale import LinearScale, _format_fixed
from dataviz.text import _Scaled
from dataviz.theme import Theme


comptime _STEP = 0.25
"""Integration step, in grid cells of arc length.

The field is integrated in *index* space, where one unit is one grid
cell, and the integrand is the unit direction (see `_unit_direction`), so
a step is a distance rather than a time and this number means the same
thing on every field. A quarter cell is four samples across the narrowest
feature a grid can represent, which is where RK4's error stops being
visible against the stroke width.
"""

comptime _MIN_SPEED = 1e-12
"""Below this magnitude the direction is undefined and the line stops.

A stagnation point is a real feature of a field, not an error; what would
be an error is integrating through one, where the normalized direction is
whatever the last bits of two near-zero numbers say and the curve wanders
off in an arbitrary direction.
"""

comptime _BLANK_CELLS_PER_DENSITY = 30
"""Occupancy cells per axis at `density=1.0`, matplotlib's constant.

Streamline spacing is set by this grid, not by the data grid: a line
stops when it enters a cell another line already owns, which is what
produces the even spacing. Seeding on a lattice instead gives clumps
where the flow converges and bald patches where it spreads.
"""


struct _Dir(Copyable, ImplicitlyCopyable, Movable):
    """A direction sample, or the fact that there isn't one: outside the
    grid, or too close to a stagnation point to have a direction."""

    var ok: Bool
    var di: Float64
    var dj: Float64

    def __init__(out self, ok: Bool, di: Float64, dj: Float64):
        self.ok = ok
        self.di = di
        self.dj = dj


struct _Field(Copyable, Movable):
    """The vector field in index space: `ui[j][i]` is the x-component at
    grid node `(i, j)` divided by the column spacing, so one unit of `ui`
    moves one column per unit of the integration parameter. Building it
    once is what lets every routine below work in cells and never think
    about the data's units again."""

    var nx: Int
    var ny: Int
    var ui: List[List[Float64]]
    var vj: List[List[Float64]]

    def __init__(
        out self,
        nx: Int,
        ny: Int,
        var ui: List[List[Float64]],
        var vj: List[List[Float64]],
    ):
        self.nx = nx
        self.ny = ny
        self.ui = ui^
        self.vj = vj^


struct _StreamData(Copyable, Movable):
    """The grid `Mark.STREAMPLOT` integrates, from `encode_streamplot()`.
    Stored on `Plot._stream`.

    `x` is `nx` column coordinates and `y` is `ny` row coordinates, both
    ascending and evenly spaced; `u[j][i]` and `v[j][i]` are the field at
    `(x[i], y[j])`, row-major like every other 2D array in this package.

    This is matplotlib's `streamplot` shape and *not* `encode_barbs()`'s
    four flat columns, which #343 suggested reusing. A glyph mark reads
    the field only where it was sampled, so scattered points are fine
    there; an integrator reads it everywhere between the samples, and
    bilinear interpolation needs to know which samples are neighbors.
    Taking flat columns and inferring a grid from them would turn a
    typo into a plausible wrong picture.
    """

    var x: List[Float64]
    var y: List[Float64]
    var u: List[List[Float64]]
    var v: List[List[Float64]]
    var density: Float64
    var arrows: Bool
    var color_by_magnitude: Bool

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.u = List[List[Float64]]()
        self.v = List[List[Float64]]()
        self.density = 1.0
        self.arrows = True
        self.color_by_magnitude = False


def _even_spacing(values: List[Float64], axis: String) raises -> Float64:
    """`values`' step, requiring it ascending and evenly spaced.

    An uneven grid is refused rather than accommodated. The integrator
    works in index space, where a step of one is one cell; on an uneven
    grid a cell's width in data units depends on where you are, so the
    same index-space velocity would mean different data-space speeds in
    different places and the curve would be wrong in a way that still
    looks like flow. matplotlib refuses the same input.

    Args:
        values: The coordinates along one axis.
        axis: "x" or "y", for the message.

    Returns:
        The spacing between neighbors.

    Raises:
        Error: Fewer than two coordinates, not ascending, or uneven.
    """
    var n = len(values)
    if n < 2:
        raise Error(
            "streamplot(): "
            + axis
            + " needs at least two coordinates to define a grid -- got "
            + String(n)
        )
    var step = values[1] - values[0]
    if step <= 0.0:
        raise Error(
            "streamplot(): "
            + axis
            + " must be strictly increasing -- got "
            + String(values[0])
            + " then "
            + String(values[1])
        )
    # Relative tolerance, since the coordinates are usually the result of
    # arithmetic rather than typed out.
    var tol = 1e-9 * abs(step) + 1e-12
    for i in range(1, n):
        var d = values[i] - values[i - 1]
        if abs(d - step) > tol:
            raise Error(
                "streamplot(): "
                + axis
                + " must be evenly spaced -- the step is "
                + String(step)
                + " at the start and "
                + String(d)
                + " at index "
                + String(i)
                + ". The integrator works in grid cells, so an uneven grid"
                " would draw a plausible wrong picture rather than fail"
            )
    return step


def _build_field(data: _StreamData) raises -> _Field:
    """Check the grid and divide the field by the cell size, giving the
    velocity in cells per unit of the integration parameter."""
    var nx = len(data.x)
    var ny = len(data.y)
    var dx = _even_spacing(data.x, "x")
    var dy = _even_spacing(data.y, "y")
    if len(data.u) != ny or len(data.v) != ny:
        raise Error(
            "streamplot(): u and v must have one row per y coordinate -- got "
            + String(ny)
            + " y values against "
            + String(len(data.u))
            + " u rows and "
            + String(len(data.v))
            + " v rows"
        )
    var ui = List[List[Float64]](capacity=ny)
    var vj = List[List[Float64]](capacity=ny)
    for j in range(ny):
        if len(data.u[j]) != nx or len(data.v[j]) != nx:
            raise Error(
                "streamplot(): u and v rows must have one entry per x"
                " coordinate -- row "
                + String(j)
                + " has "
                + String(len(data.u[j]))
                + " u values and "
                + String(len(data.v[j]))
                + " v values against "
                + String(nx)
                + " x values"
            )
        var urow = List[Float64](capacity=nx)
        var vrow = List[Float64](capacity=nx)
        for i in range(nx):
            urow.append(data.u[j][i] / dx)
            vrow.append(data.v[j][i] / dy)
        ui.append(urow^)
        vj.append(vrow^)
    return _Field(nx, ny, ui^, vj^)


def _interp(grid: List[List[Float64]], fi: Float64, fj: Float64) -> Float64:
    """Bilinear sample of `grid` at fractional index `(fi, fj)`, which
    the caller has already checked is inside the grid."""
    var i0 = Int(fi)
    var j0 = Int(fj)
    var nx = len(grid[0])
    var ny = len(grid)
    if i0 > nx - 2:
        i0 = nx - 2
    if j0 > ny - 2:
        j0 = ny - 2
    if i0 < 0:
        i0 = 0
    if j0 < 0:
        j0 = 0
    var ti = fi - Float64(i0)
    var tj = fj - Float64(j0)
    var a = grid[j0][i0] * (1.0 - ti) + grid[j0][i0 + 1] * ti
    var b = grid[j0 + 1][i0] * (1.0 - ti) + grid[j0 + 1][i0 + 1] * ti
    return a * (1.0 - tj) + b * tj


def _unit_direction(field: _Field, fi: Float64, fj: Float64) -> _Dir:
    """The field's direction at `(fi, fj)` as a unit vector in index
    space, or `ok=False` outside the grid or at a stagnation point.

    Normalizing is what makes `_STEP` a distance rather than a time: the
    curve a particle traces is the same either way (speed changes how
    fast it gets there, not where it goes), and a fixed arc-length step
    resolves a fast region and a slow one equally well. Integrating the
    raw field instead takes huge steps through the fast parts, which is
    exactly where the curvature usually is.
    """
    if fi < 0.0 or fj < 0.0:
        return _Dir(False, 0.0, 0.0)
    if fi > Float64(field.nx - 1) or fj > Float64(field.ny - 1):
        return _Dir(False, 0.0, 0.0)
    var di = _interp(field.ui, fi, fj)
    var dj = _interp(field.vj, fi, fj)
    var speed = sqrt(di * di + dj * dj)
    if speed < _MIN_SPEED:
        return _Dir(False, 0.0, 0.0)
    return _Dir(True, di / speed, dj / speed)


def _rk4_step(field: _Field, fi: Float64, fj: Float64, h: Float64) -> _Dir:
    """One classical fourth-order Runge-Kutta step of arc length `h`
    from `(fi, fj)`, returning the new point (in `di`/`dj`) or
    `ok=False` if any stage left the grid or hit a stagnation point.

    RK4 rather than Euler because the error that matters here is
    systematic, not small: on a curved field Euler steps along the
    tangent and so always lands outside the curve, and a closed
    streamline spirals visibly outward over one revolution. On solid-body
    rotation, where the exact streamlines are circles, RK4 at a quarter
    cell holds the radius to parts in a million over a full turn -- which
    `tests/test_streamplot.mojo` pins, because "looks like flow" is not
    evidence of anything.
    """
    var k1 = _unit_direction(field, fi, fj)
    if not k1.ok:
        return k1
    var k2 = _unit_direction(field, fi + 0.5 * h * k1.di, fj + 0.5 * h * k1.dj)
    if not k2.ok:
        return k2
    var k3 = _unit_direction(field, fi + 0.5 * h * k2.di, fj + 0.5 * h * k2.dj)
    if not k3.ok:
        return k3
    var k4 = _unit_direction(field, fi + h * k3.di, fj + h * k3.dj)
    if not k4.ok:
        return k4
    var si = (k1.di + 2.0 * k2.di + 2.0 * k3.di + k4.di) / 6.0
    var sj = (k1.dj + 2.0 * k2.dj + 2.0 * k3.dj + k4.dj) / 6.0
    return _Dir(True, fi + h * si, fj + h * sj)


struct _Occupancy(Movable):
    """Which streamline owns each cell of the spacing grid.

    `0` is free and `id + 1` is trajectory `id`. A line may re-enter its
    own cells -- a closed streamline must be able to -- and stops the
    moment it enters another's, which is the whole of the even-spacing
    rule. `nx`/`ny` are the *cell* counts, not the data grid's.
    """

    var nx: Int
    var ny: Int
    var owner: List[Int]

    def __init__(out self, nx: Int, ny: Int):
        self.nx = nx
        self.ny = ny
        self.owner = List[Int](capacity=nx * ny)
        for _ in range(nx * ny):
            self.owner.append(0)

    def cell_of(self, fi: Float64, fj: Float64, field: _Field) -> Int:
        """The flat cell index a point in grid-index space falls in, or
        -1 when it is outside."""
        var span_i = Float64(field.nx - 1)
        var span_j = Float64(field.ny - 1)
        if span_i <= 0.0 or span_j <= 0.0:
            return -1
        var cx = Int(fi / span_i * Float64(self.nx))
        var cy = Int(fj / span_j * Float64(self.ny))
        if cx < 0 or cy < 0 or cx >= self.nx or cy >= self.ny:
            return -1
        return cy * self.nx + cx

    def center_of(self, cell: Int, field: _Field) -> _Dir:
        """The grid-index point at the middle of `cell`, as a seed."""
        var cx = cell % self.nx
        var cy = cell // self.nx
        var fi = (Float64(cx) + 0.5) / Float64(self.nx) * Float64(field.nx - 1)
        var fj = (Float64(cy) + 0.5) / Float64(self.ny) * Float64(field.ny - 1)
        return _Dir(True, fi, fj)


def _seed_order(nx: Int, ny: Int) -> List[Int]:
    """Cell indices in an inward spiral from the outside.

    Order matters because the first line through a region owns it. Going
    row by row grows every line out of one corner and leaves the far side
    to whatever is left over; spiralling inward lays the boundary flow
    down first and fills the interior against it, which is matplotlib's
    choice and what makes two runs of the same field look alike.
    """
    var out = List[Int](capacity=nx * ny)
    var top = 0
    var bottom = ny - 1
    var left = 0
    var right = nx - 1
    while top <= bottom and left <= right:
        for i in range(left, right + 1):
            out.append(top * nx + i)
        top += 1
        for j in range(top, bottom + 1):
            out.append(j * nx + right)
        right -= 1
        if top <= bottom:
            for i in range(right, left - 1, -1):
                out.append(bottom * nx + i)
            bottom -= 1
        if left <= right:
            for j in range(bottom, top - 1, -1):
                out.append(j * nx + left)
            left += 1
    return out^


struct _Line(Movable):
    """One traced streamline, in grid-index space."""

    var fi: List[Float64]
    var fj: List[Float64]

    def __init__(out self):
        self.fi = List[Float64]()
        self.fj = List[Float64]()


def _trace(
    field: _Field,
    mut occ: _Occupancy,
    seed_i: Float64,
    seed_j: Float64,
    sign: Float64,
    traj_id: Int,
    max_steps: Int,
    mut claimed: List[Int],
) -> _Line:
    """Integrate one half of a streamline from the seed, `sign` being
    +1 downstream and -1 upstream.

    Four things stop it, all of them real: leaving the grid, reaching a
    stagnation point (both from `_rk4_step` returning `ok=False`),
    entering a cell another line already owns, and `max_steps`. The last
    is the only arbitrary one, and it exists because a closed streamline
    -- a vortex, an orbit -- never leaves the grid and never meets
    another line, so nothing else would ever stop it.

    Cells this half claims are appended to `claimed`, so the caller can
    hand them back if the finished line turns out to be too short to
    draw.
    """
    var out = _Line()
    out.fi.append(seed_i)
    out.fj.append(seed_j)
    var fi = seed_i
    var fj = seed_j
    for _ in range(max_steps):
        var next = _rk4_step(field, fi, fj, sign * _STEP)
        if not next.ok:
            break
        var cell = occ.cell_of(next.di, next.dj, field)
        if cell < 0:
            break
        var owner = occ.owner[cell]
        if owner != 0 and owner != traj_id + 1:
            break
        if owner == 0:
            occ.owner[cell] = traj_id + 1
            claimed.append(cell)
        fi = next.di
        fj = next.dj
        out.fi.append(fi)
        out.fj.append(fj)
    return out^


def _streamlines(data: _StreamData) raises -> List[_Line]:
    """Every streamline of the field, seeded and terminated so the set
    is evenly spaced. Grid-index coordinates throughout; the renderer
    maps them back to data and then to pixels.
    """
    var field = _build_field(data)
    if field.nx < 2 or field.ny < 2:
        return List[_Line]()
    var cells = max(Int(Float64(_BLANK_CELLS_PER_DENSITY) * data.density), 2)
    var occ = _Occupancy(cells, cells)
    # A closed line has to be able to come back around to its seed, so
    # the cap is generous: the perimeter of the grid, several times over.
    var max_steps = Int(4.0 * Float64(field.nx + field.ny) / _STEP)
    var lines = List[_Line]()
    var order = _seed_order(cells, cells)
    for cell in order:
        if occ.owner[cell] != 0:
            continue
        var traj_id = len(lines)
        var seed = occ.center_of(cell, field)
        var start_cell = occ.cell_of(seed.di, seed.dj, field)
        if start_cell < 0:
            continue
        var claimed = List[Int]()
        occ.owner[start_cell] = traj_id + 1
        claimed.append(start_cell)
        var back = _trace(
            field, occ, seed.di, seed.dj, -1.0, traj_id, max_steps, claimed
        )
        var fwd = _trace(
            field, occ, seed.di, seed.dj, 1.0, traj_id, max_steps, claimed
        )
        # Upstream half reversed, then downstream, so the points run
        # along the flow and an arrowhead can point down the list.
        var line = _Line()
        for k in range(len(back.fi) - 1, 0, -1):
            line.fi.append(back.fi[k])
            line.fj.append(back.fj[k])
        for k in range(len(fwd.fi)):
            line.fi.append(fwd.fi[k])
            line.fj.append(fwd.fj[k])
        if len(line.fi) < 3:
            # Too short to read as a curve. Hand its cells back rather
            # than letting a stub block a line that would have drawn.
            for c in claimed:
                occ.owner[c] = 0
            continue
        lines.append(line^)
    return lines^


def _magnitude_at(data: _StreamData, fi: Float64, fj: Float64) -> Float64:
    """The field's magnitude in *data* units at a grid-index point, for
    coloring. Read from the original arrays rather than the index-space
    field, whose components are divided by the cell size."""
    var u = _interp(data.u, fi, fj)
    var v = _interp(data.v, fi, fj)
    return sqrt(u * u + v * v)


def _max_magnitude(data: _StreamData) -> Float64:
    var top = 0.0
    for j in range(len(data.u)):
        for i in range(len(data.u[j])):
            var u = data.u[j][i]
            var v = data.v[j][i]
            top = max(top, sqrt(u * u + v * v))
    return top


def _render_streamplot[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render `Mark.STREAMPLOT`: the field's streamlines over a
    continuous frame, each one a stroked path, with an arrowhead at the
    middle of each line showing which way the flow runs.

    The axis domains are the grid's own corners, unpadded: the field is
    defined exactly there and nowhere else, and 5% of empty axis around
    it would read as "no flow here" when the truth is "no data here" --
    the reason `imshow` pins its domain the same way.

    Args:
        target: Where to draw.
        plot: The chart, whose `_stream` data this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: The grid is malformed; see `_even_spacing`/`_build_field`.
    """
    ref data = plot._stream
    var lines = _streamlines(data)
    var theme = plot._theme
    var sc = _Scaled(theme)
    var nx = len(data.x)
    var ny = len(data.y)
    var color_scale = ColorScale.from_theme(theme, 0.0, _max_magnitude(data))

    var legend = _LegendLayout()
    if theme.show_legend and data.color_by_magnitude:
        var legend_labels = List[String]()
        legend_labels.append(_format_fixed(color_scale.domain_max, 1))
        legend_labels.append(_format_fixed(color_scale.domain_min, 1))
        legend.right = _dynamic_legend_width(
            legend_labels, sc.continuous_legend_bar_width, sc, cache=cache
        )
        legend.active = True

    var frame = _draw_continuous_axis_frame(
        target,
        LinearScale(data.x[0], data.x[nx - 1], 0.0, 1.0),
        LinearScale(data.y[0], data.y[ny - 1], 0.0, 1.0),
        theme,
        legend,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var dx = (data.x[nx - 1] - data.x[0]) / Float64(nx - 1)
    var dy = (data.y[ny - 1] - data.y[0]) / Float64(ny - 1)
    var head_len = _ARROW_HEAD_LENGTH * sc.scale
    var head_half = _ARROW_HEAD_HALF_WIDTH * sc.scale
    for idx in range(len(lines)):
        ref line = lines[idx]
        var n = len(line.fi)
        var px = List[Float64](capacity=n)
        var py = List[Float64](capacity=n)
        for k in range(n):
            px.append(frame.x_scale.to_pixel(data.x[0] + line.fi[k] * dx))
            py.append(frame.y_scale.to_pixel(data.y[0] + line.fj[k] * dy))
        if data.color_by_magnitude:
            # One stroke per step, each in its own color: the speed
            # varies along a streamline, and a line drawn in its average
            # color would claim it does not.
            for k in range(n - 1):
                var mag = _magnitude_at(
                    data,
                    (line.fi[k] + line.fi[k + 1]) * 0.5,
                    (line.fj[k] + line.fj[k + 1]) * 0.5,
                )
                var seg = Path()
                seg.move_to(px[k], py[k])
                seg.line_to(px[k + 1], py[k + 1])
                target.stroke_path_aa(
                    seg, color_scale.color_at(mag), width=sc.line_width
                )
        else:
            var path = Path()
            path.move_to(px[0], py[0])
            for k in range(1, n):
                path.line_to(px[k], py[k])
            target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)

        if not data.arrows or n < 3:
            continue
        # One head at the middle of the line, pointing downstream, the
        # placement matplotlib uses: a head per step would bury the
        # curve, and a head at the end lands on whatever stopped the
        # line rather than on the flow.
        var m = n // 2
        var ax = px[m] - px[m - 1]
        var ay = py[m] - py[m - 1]
        var mag = sqrt(ax * ax + ay * ay)
        if mag <= 0.0:
            continue
        var color = theme.mark_color
        if data.color_by_magnitude:
            color = color_scale.color_at(
                _magnitude_at(data, line.fi[m], line.fj[m])
            )
        target.fill_path_aa(
            _arrow_head_path(
                px[m], py[m], ax / mag, ay / mag, head_len, head_half
            ),
            color,
            fill_rule=FillRule.NONZERO,
        )

    if legend.active:
        _ = _draw_continuous_color_legend(
            target,
            frame.text_requests,
            color_scale,
            round_to_int(frame.x_scale.range_max) + sc.margin_right,
            frame.py0,
            theme,
        )
    return frame.result()


def streamplot(
    x: List[Float64],
    y: List[Float64],
    u: List[List[Float64]],
    v: List[List[Float64]],
    density: Float64 = 1.0,
    arrows: Bool = True,
    color_by_magnitude: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A vector field as streamlines, matplotlib's `streamplot()`: the
    curves a particle released into the field would follow.

    `quiver()` shows the vector *at* each sample; this shows where a
    particle *goes*. For transport -- a current, a wind field, a force
    field -- the streamline is the readable form, because the eye follows
    a continuous curve and cannot integrate a grid of arrows by itself.

    The field is given on a grid, not as scattered samples: `x` is `nx`
    column coordinates and `y` is `ny` row coordinates, both ascending
    and evenly spaced, and `u[j][i]`/`v[j][i]` are the components at
    `(x[i], y[j])`. A glyph mark can take scattered points because it
    reads the field only where it was sampled; an integrator reads it
    everywhere in between, and interpolation needs to know which samples
    are neighbors.

    `density` scales the spacing between lines. It is the number of
    occupancy cells per axis over 30: a line stops when it enters a cell
    another line already owns, so a larger density means smaller cells,
    more lines and finer detail. This is matplotlib's parameter and it
    behaves the same way.

    Lines are traced with RK4 at a quarter-cell step over the bilinearly
    interpolated field, both upstream and downstream from each seed, and
    stop at the grid's edge, at a stagnation point, or where another line
    already passed.

    Args:
        x: Column coordinates, ascending and evenly spaced.
        y: Row coordinates, ascending and evenly spaced.
        u: The x-component at each node, `len(y)` rows of `len(x)`.
        v: The y-component at each node, positive pointing up the page.
        density: Line spacing; 1.0 is matplotlib's default.
        arrows: Draw an arrowhead at the middle of each line.
        color_by_magnitude: Color each step by the local `hypot(u, v)`
            through the theme's ramp, with a legend.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: The grid is empty, uneven, not ascending, or `u`/`v` do
            not match its shape, or `density` is not positive.

    Example:
        ```mojo
        from dataviz import streamplot, save
        from dataviz import Theme
        from dataviz.colormaps import viridis

        def main() raises:
            # A vortex pair: two counter-rotating centers, the flow
            # between them running from one to the other. Sampled on a
            # 33x25 grid over [-4, 4] x [-3, 3].
            var xs = List[Float64]()
            for i in range(33):
                xs.append(-4.0 + 0.25 * Float64(i))
            var ys = List[Float64]()
            for j in range(25):
                ys.append(-3.0 + 0.25 * Float64(j))

            var us = List[List[Float64]]()
            var vs = List[List[Float64]]()
            for j in range(len(ys)):
                var urow = List[Float64]()
                var vrow = List[Float64]()
                for i in range(len(xs)):
                    var px = xs[i]
                    var py = ys[j]
                    # Each center contributes a rotation falling off
                    # with the square of the distance to it.
                    var ax = px + 1.5
                    var ay = py
                    var ra = ax * ax + ay * ay + 0.35
                    var bx = px - 1.5
                    var by = py
                    var rb = bx * bx + by * by + 0.35
                    urow.append(-ay / ra + by / rb)
                    vrow.append(ax / ra - bx / rb)
                us.append(urow^)
                vs.append(vrow^)

            var chart = streamplot(
                xs,
                ys,
                us,
                vs,
                color_by_magnitude=True,
                theme=Theme(color_ramp=viridis()),
                title="Illustrative Vortex Pair",
                x_title="x",
                y_title="y",
            )
            save(chart, "docs/src/examples/out_streamplot.svg")
        ```
    """
    if density <= 0.0:
        raise Error(
            "streamplot(): density must be positive -- got " + String(density)
        )
    var plot = (
        Plot()
        .mark_streamplot(
            density=density,
            arrows=arrows,
            color_by_magnitude=color_by_magnitude,
        )
        .encode_streamplot(x, y, u, v)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def streamplot[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    u: List[List[Scalar[dtype]]],
    v: List[List[Scalar[dtype]]],
    density: Float64 = 1.0,
    arrows: Bool = True,
    color_by_magnitude: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`streamplot()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (continuous.mojo). Delegates to the
    concrete overload above.

    Parameters:
        dtype: The element type of the grid and the field.

    Args:
        x: Column coordinates, ascending and evenly spaced.
        y: Row coordinates, ascending and evenly spaced.
        u: The x-component at each node.
        v: The y-component at each node.
        density: Line spacing; 1.0 is matplotlib's default.
        arrows: Draw an arrowhead at the middle of each line.
        color_by_magnitude: Color each step by the local magnitude.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: As the concrete overload.
    """
    return streamplot(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        _materialize_nested_scalar_list(u),
        _materialize_nested_scalar_list(v),
        density=density,
        arrows=arrows,
        color_by_magnitude=color_by_magnitude,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
