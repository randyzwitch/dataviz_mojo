"""Tests for `Mark.STREAMPLOT` (#343).

The integrator and the seeding can each produce a plausible-looking but
wrong picture, and "looks like flow" is not evidence of anything, so the
numerical half is checked against two fields whose exact streamlines are
known: a uniform field, whose lines are straight, and solid-body
rotation, whose lines are circles.
"""

from std.math import pi, sqrt
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from _test_helpers import _assert_same_canvas, _count_tag
from dataviz import streamplot
from dataviz.plot import Plot, render, render_svg
from dataviz.streamplot import (
    _STEP,
    _Line,
    _Occupancy,
    _build_field,
    _streamlines,
    _trace,
)
from dataviz.theme import Theme


def _coords(n: Int, lo: Float64, step: Float64) -> List[Float64]:
    var out = List[Float64]()
    for i in range(n):
        out.append(lo + step * Float64(i))
    return out^


def _uniform(nx: Int, ny: Int) -> List[List[Float64]]:
    var out = List[List[Float64]]()
    for _ in range(ny):
        var row = List[Float64]()
        for _ in range(nx):
            row.append(1.0)
        out.append(row^)
    return out^


def _zeros(nx: Int, ny: Int) -> List[List[Float64]]:
    var out = List[List[Float64]]()
    for _ in range(ny):
        var row = List[Float64]()
        for _ in range(nx):
            row.append(0.0)
        out.append(row^)
    return out^


def _rotation_field(
    xs: List[Float64], ys: List[Float64]
) -> Tuple[List[List[Float64]], List[List[Float64]]]:
    """Solid-body rotation about the origin, `(u, v) = (-y, x)`. Its
    streamlines are exactly the circles centered there."""
    var us = List[List[Float64]]()
    var vs = List[List[Float64]]()
    for j in range(len(ys)):
        var urow = List[Float64]()
        var vrow = List[Float64]()
        for i in range(len(xs)):
            urow.append(-ys[j])
            vrow.append(xs[i])
        us.append(urow^)
        vs.append(vrow^)
    return (us^, vs^)


def test_a_uniform_field_traces_straight_lines() raises:
    # (u, v) = (1, 0) everywhere: every streamline is a horizontal line,
    # so a traced point's row never changes and its column only grows.
    var xs = _coords(11, 0.0, 1.0)
    var ys = _coords(9, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, _uniform(11, 9), _zeros(11, 9))
    )
    var field = _build_field(p._stream)
    # One occupancy cell, so nothing can block the line and the trace is
    # the integrator alone.
    var occ = _Occupancy(1, 1)
    var claimed = List[Int]()
    var line = _trace(field, occ, 2.0, 4.0, 1.0, 0, 200, claimed)
    assert_true(len(line.fi) > 20, "the line crosses the grid")
    for k in range(len(line.fj)):
        assert_true(
            abs(line.fj[k] - 4.0) < 1e-9,
            "a uniform field's streamline stays in its row -- got "
            + String(line.fj[k])
            + " at step "
            + String(k),
        )
    for k in range(1, len(line.fi)):
        assert_true(
            abs(line.fi[k] - line.fi[k - 1] - _STEP) < 1e-9,
            "each step advances exactly one step's arc length",
        )
    # And it stops at the grid's edge rather than running past it.
    assert_true(line.fi[len(line.fi) - 1] <= 10.0 + 1e-9, "stops at the edge")
    assert_true(line.fi[len(line.fi) - 1] > 9.5, "having reached it")


def test_solid_body_rotation_traces_exact_circles() raises:
    # (u, v) = (-y, x): the streamline through a point at radius r is
    # the circle of radius r, so the radius is the invariant to check.
    # Bilinear interpolation is exact on a linear field, so any drift
    # here is the integrator's -- which is what Euler would fail, its
    # lines spiralling outward by a visible amount over one turn.
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var field_arrays = _rotation_field(xs, ys)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, field_arrays[0], field_arrays[1])
    )
    var field = _build_field(p._stream)
    var occ = _Occupancy(1, 1)
    var claimed = List[Int]()
    # The grid center is index (10, 10); seed 6 cells to its right.
    var radius = 6.0
    var turn = 2.0 * pi * radius
    var steps = Int(turn / _STEP) + 2
    var line = _trace(field, occ, 16.0, 10.0, 1.0, 0, steps, claimed)
    assert_equal(len(line.fi), steps + 1, "nothing stopped it early")

    var worst = 0.0
    for k in range(len(line.fi)):
        var dx = line.fi[k] - 10.0
        var dy = line.fj[k] - 10.0
        worst = max(worst, abs(sqrt(dx * dx + dy * dy) - radius))
    assert_true(
        worst < 1e-4,
        "the radius is conserved over a full turn -- worst drift "
        + String(worst)
        + " cells",
    )

    # And it comes back to where it started. The step is a fixed arc
    # length and the circumference is not a multiple of it, so the
    # closest approach is within half a step by construction; anything
    # worse is the integrator losing phase.
    var closest = 1.0e9
    for k in range(len(line.fi) // 2, len(line.fi)):
        var dx = line.fi[k] - 16.0
        var dy = line.fj[k] - 10.0
        closest = min(closest, sqrt(dx * dx + dy * dy))
    assert_true(
        closest < _STEP,
        "the line closes on its own seed -- closest approach "
        + String(closest)
        + " cells",
    )


def test_a_line_stops_where_another_one_already_passed() raises:
    # The even-spacing rule: with the whole grid one occupancy cell,
    # a second trajectory cannot take a single step.
    var xs = _coords(11, 0.0, 1.0)
    var ys = _coords(9, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, _uniform(11, 9), _zeros(11, 9))
    )
    var field = _build_field(p._stream)
    var occ = _Occupancy(1, 1)
    var claimed = List[Int]()
    var first = _trace(field, occ, 2.0, 4.0, 1.0, 0, 200, claimed)
    assert_true(len(first.fi) > 20, "the first line runs")
    var claimed2 = List[Int]()
    var second = _trace(field, occ, 2.0, 2.0, 1.0, 1, 200, claimed2)
    assert_equal(len(second.fi), 1, "the second gets only its seed")


def test_a_field_with_no_flow_draws_no_lines() raises:
    # Every point is a stagnation point: the direction is undefined, so
    # there is nothing to integrate and nothing to draw. The interesting
    # part is that it does not wander off on the last bits of zero.
    var xs = _coords(9, 0.0, 1.0)
    var ys = _coords(9, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, _zeros(9, 9), _zeros(9, 9))
    )
    assert_equal(len(_streamlines(p._stream)), 0)


def test_density_controls_how_many_lines_are_drawn() raises:
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var f = _rotation_field(xs, ys)
    var sparse = (
        Plot()
        .mark_streamplot(density=0.5)
        .encode_streamplot(xs, ys, f[0], f[1])
    )
    var dense = (
        Plot()
        .mark_streamplot(density=2.0)
        .encode_streamplot(xs, ys, f[0], f[1])
    )
    var n_sparse = len(_streamlines(sparse._stream))
    var n_dense = len(_streamlines(dense._stream))
    assert_true(n_sparse > 0, "a sparse field still draws")
    assert_true(
        n_dense > n_sparse,
        "raising the density draws more lines -- got "
        + String(n_dense)
        + " against "
        + String(n_sparse),
    )


def test_streamlines_run_downstream_not_from_the_seed_outward() raises:
    # Each line is the upstream half reversed then the downstream half,
    # so the points follow the flow end to end. In a uniform rightward
    # field every column must increase along the list -- a line built
    # seed-outward would turn around in the middle.
    var xs = _coords(21, 0.0, 1.0)
    var ys = _coords(11, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, _uniform(21, 11), _zeros(21, 11))
    )
    var lines = _streamlines(p._stream)
    assert_true(len(lines) > 0, "a uniform field draws lines")
    for idx in range(len(lines)):
        ref line = lines[idx]
        for k in range(1, len(line.fi)):
            assert_true(
                line.fi[k] > line.fi[k - 1],
                "the points run downstream",
            )


def test_svg_draws_a_path_per_line_and_one_more_with_arrows() raises:
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var f = _rotation_field(xs, ys)
    var t = Theme(show_gridlines=False, show_legend=False)
    var plain = render_svg(
        streamplot(
            xs, ys, f[0], f[1], arrows=False, theme=t, width=400, height=300
        )
    ).to_string()
    var arrowed = render_svg(
        streamplot(
            xs, ys, f[0], f[1], arrows=True, theme=t, width=400, height=300
        )
    ).to_string()
    var lines = _count_tag(plain, "path")
    assert_true(lines > 4, "the field draws several lines")
    assert_true(
        _count_tag(arrowed, "path") > lines,
        "each arrowhead is a path of its own",
    )


def test_color_by_magnitude_strokes_each_step_separately() raises:
    # The speed varies along a streamline, so a line drawn in one color
    # would claim it does not: the colored form is one stroke per step.
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var f = _rotation_field(xs, ys)
    var t = Theme(show_gridlines=False, show_legend=False)
    var plain = _count_tag(
        render_svg(
            streamplot(
                xs, ys, f[0], f[1], arrows=False, theme=t, width=400, height=300
            )
        ).to_string(),
        "path",
    )
    var colored = _count_tag(
        render_svg(
            streamplot(
                xs,
                ys,
                f[0],
                f[1],
                arrows=False,
                color_by_magnitude=True,
                theme=t,
                width=400,
                height=300,
            )
        ).to_string(),
        "path",
    )
    assert_true(
        colored > 10 * plain,
        "coloring by magnitude strokes every step -- got "
        + String(colored)
        + " against "
        + String(plain),
    )


def test_dtype_overload_matches_the_float64_path() raises:
    var xf = _coords(9, 0.0, 1.0)
    var yf = _coords(9, 0.0, 1.0)
    var uf = List[List[Float64]]()
    var vf = List[List[Float64]]()
    var ui = List[List[Int32]]()
    var vi = List[List[Int32]]()
    var xi = List[Int32]()
    var yi = List[Int32]()
    for i in range(9):
        xi.append(Int32(i))
        yi.append(Int32(i))
    for j in range(9):
        var ur = List[Float64]()
        var vr = List[Float64]()
        var ur_i = List[Int32]()
        var vr_i = List[Int32]()
        for i in range(9):
            ur.append(Float64(-(j - 4)))
            vr.append(Float64(i - 4))
            ur_i.append(Int32(-(j - 4)))
            vr_i.append(Int32(i - 4))
        uf.append(ur^)
        vf.append(vr^)
        ui.append(ur_i^)
        vi.append(vr_i^)
    _assert_same_canvas(
        render(streamplot(xf, yf, uf, vf, width=300, height=220)),
        render(streamplot(xi, yi, ui, vi, width=300, height=220)),
        "Int32 streamplot matches Float64",
    )


def test_streamplot_raises_with_names() raises:
    var xs = _coords(5, 0.0, 1.0)
    var ys = _coords(4, 0.0, 1.0)
    with assert_raises(contains="density must be positive"):
        _ = streamplot(xs, ys, _uniform(5, 4), _zeros(5, 4), density=0.0)
    # An uneven grid: the integrator works in cells, so it refuses.
    var uneven: List[Float64] = [0.0, 1.0, 3.0, 4.0, 5.0]
    var p = streamplot(uneven, ys, _uniform(5, 4), _zeros(5, 4))
    with assert_raises(contains="must be evenly spaced"):
        _ = render(p)
    var descending: List[Float64] = [5.0, 4.0, 3.0, 2.0, 1.0]
    var p2 = streamplot(descending, ys, _uniform(5, 4), _zeros(5, 4))
    with assert_raises(contains="must be strictly increasing"):
        _ = render(p2)
    var p3 = streamplot(xs, ys, _uniform(5, 3), _zeros(5, 4))
    with assert_raises(contains="one row per y coordinate"):
        _ = render(p3)
    var short = List[List[Float64]]()
    for _ in range(4):
        var row = List[Float64]()
        for _ in range(3):
            row.append(1.0)
        short.append(row^)
    var p4 = streamplot(xs, ys, short, _zeros(5, 4))
    with assert_raises(contains="one entry per x coordinate"):
        _ = render(p4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
