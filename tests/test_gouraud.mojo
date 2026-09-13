"""Gouraud shading for `Mark.TRIPCOLOR` (#398).

Flat shading gives each triangle one color, from the mean of its three
vertex values. It is the right default -- a flat fill says "this
triangle has this value", which is what the data supports -- but it
makes a smooth field look faceted, and the facets are an artifact of
where the samples happened to fall rather than anything in the data.

#398 says how to test the difference, and it is a good test because it
does not depend on the triangulation: over a linear ramp `z = x`, a
Gouraud-shaded pixel's color is a function of its own x alone, so two
pixels at the same x in *different* triangles must match. Under flat
shading they do not, which is exactly the artifact.

The issue's plan was recursive subdivision, because no drawing primitive
could interpolate across a face. canvas_mojo v0.35.0 added
`fill_mesh_shaded`, which does it directly, so the subdivision is not
needed and is not here.
"""

from std.math import sin
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import Theme
from dataviz.core.colormaps import viridis
from dataviz.multivariate.triplot import tripcolor
from dataviz.plot import Plot, render, render_svg


def _theme() -> Theme:
    return Theme(
        color_ramp=viridis(),
        show_gridlines=False,
        show_legend=False,
        raster_supersample=1,
    )


def _ramp_samples() -> Tuple[List[Float64], List[Float64], List[Float64]]:
    """A coarse scatter over a square, with `z = x`.

    Coarse on purpose: the faceting Gouraud removes is only visible when
    the mesh is coarse relative to the field. The four corners are
    pinned so the hull is the whole square and the sampled interior is
    well inside it.
    """
    var xs: List[Float64] = [0.0, 10.0, 10.0, 0.0]
    var ys: List[Float64] = [0.0, 0.0, 10.0, 10.0]
    var seed = 20260913
    for _ in range(40):
        seed = (seed * 1103515245 + 12345) % 2147483648
        xs.append(Float64(seed % 10000) / 1000.0)
        seed = (seed * 1103515245 + 12345) % 2147483648
        ys.append(Float64(seed % 10000) / 1000.0)
    var zs = List[Float64]()
    for i in range(len(xs)):
        zs.append(xs[i])
    return (xs^, ys^, zs^)


def _column_spread(c: Canvas, x: Int, y0: Int, y1: Int) -> Int:
    """The widest channel gap between any two pixels in one column.

    Under `z = x` every pixel in a column has the same value, so a
    correct Gouraud render paints the column one color and this is 0.
    """
    var worst = 0
    for a in range(y0, y1):
        for b in range(a + 1, y1):
            var p = c.get_pixel(x, a)
            var q = c.get_pixel(x, b)
            var d = max(
                abs(Int(p.r) - Int(q.r)),
                max(abs(Int(p.g) - Int(q.g)), abs(Int(p.b) - Int(q.b))),
            )
            if d > worst:
                worst = d
    return worst


def test_a_linear_ramp_shades_by_x_alone() raises:
    """#398's stated criterion.

    Two pixels at the same x are at the same `z`, so under Gouraud they
    must be the same color whichever triangles they fall in. The column
    is sampled well inside the hull so the anti-aliased boundary never
    enters it.
    """
    var s = _ramp_samples()
    var img = render(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=True,
            width=300,
            height=220,
            theme=_theme(),
        )
    )
    var worst = _column_spread(img, 150, 80, 140)
    assert_true(
        worst <= 2,
        (
            "a column of constant z spans "
            + String(worst)
            + " levels, so the shading is not a function of x alone"
        ),
    )


def test_flat_shading_is_the_thing_this_fixes() raises:
    # The control. The same mesh flat-shaded must NOT be constant down a
    # column, or the test above proves nothing about Gouraud.
    var s = _ramp_samples()
    var img = render(
        tripcolor(s[0], s[1], s[2], width=300, height=220, theme=_theme())
    )
    var worst = _column_spread(img, 150, 80, 140)
    assert_true(
        worst > 10,
        (
            "flat shading already paints a constant-z column one color (spread "
            + String(worst)
            + "), so there is nothing for Gouraud to fix"
        ),
    )


def test_gouraud_changes_the_picture() raises:
    var s = _ramp_samples()
    var flat = render(
        tripcolor(s[0], s[1], s[2], width=300, height=220, theme=_theme())
    )
    var smooth = render(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=True,
            width=300,
            height=220,
            theme=_theme(),
        )
    )
    var diff = 0
    for y in range(flat.height):
        for x in range(flat.width):
            var a = flat.get_pixel(x, y)
            var b = smooth.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                diff += 1
    assert_true(diff > 500, "gouraud changed nothing on the canvas")


def test_flat_is_still_the_default() raises:
    var s = _ramp_samples()
    var explicit = render(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=False,
            width=300,
            height=220,
            theme=_theme(),
        )
    )
    var default = render(
        tripcolor(s[0], s[1], s[2], width=300, height=220, theme=_theme())
    )
    for y in range(0, default.height, 7):
        for x in range(0, default.width, 7):
            var a = explicit.get_pixel(x, y)
            var b = default.get_pixel(x, y)
            assert_equal(
                Int(a.r) * 65536 + Int(a.g) * 256 + Int(a.b),
                Int(b.r) * 65536 + Int(b.g) * 256 + Int(b.b),
                "the default is not flat shading",
            )


def test_gouraud_and_facecolors_are_exclusive() raises:
    # facecolors is one value per triangle, so there is nothing to
    # interpolate between. Caught in the builder rather than at render.
    var xs: List[Float64] = [0.0, 1.0, 0.5, 1.5]
    var ys: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    var zs: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var faces: List[Float64] = [1.0, 2.0]
    from dataviz.core.delaunay import delaunay

    with assert_raises(contains="nothing to interpolate between"):
        _ = (
            Plot()
            .mark_tripcolor()
            .encode_triplot(
                x=xs,
                y=ys,
                z=zs,
                triangulation=delaunay(xs, ys),
                facecolors=faces,
                gouraud=True,
            )
        )


def test_svg_renders_and_says_it_approximates() raises:
    """SVG has no mesh gradient, so canvas draws each face flat at the
    mean of its corners. That is the first place the backends differ by
    design, and it is worth pinning that the vector path at least
    renders rather than raising.
    """
    var s = _ramp_samples()
    var svg = render_svg(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=True,
            width=300,
            height=220,
            theme=_theme(),
        )
    ).to_string()
    assert_true("<svg" in svg, "no svg root")
    assert_true(svg.count("<path") > 10, "the mesh drew almost nothing")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
