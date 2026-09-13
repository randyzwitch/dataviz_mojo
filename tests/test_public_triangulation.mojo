"""A public `Triangulation`, and the per-triangle values it unlocks (#397).

`delaunay()` and its result type were private, so every triangulation mark
built its own inside its render function. Two consequences the issue names:
a layered chart triangulated the same points twice, and matplotlib's
`tripcolor(facecolors=...)` could not be offered at all, because the
triangle order is an artifact of Bowyer-Watson's insertion sequence and
nothing outside this package can predict it.

Both are fixed by the same change: make the order knowable by making the
triangulation something the caller owns.

The tests below lean on that: a caller-built `Triangulation` has a triangle
order the test itself chose, so `facecolors` can be asserted against
specific triangles rather than against whatever the algorithm produced.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas

from dataviz import Theme, Triangulation, delaunay
from dataviz.plot import Plot, render


def _square() -> Tuple[List[Float64], List[Float64]]:
    """Four corners of a unit square, in a fixed order.

    Small enough that its two triangles can be written out by hand,
    which is what lets `facecolors` be checked against a known triangle
    rather than an arbitrary one.

    Returns:
        `(x, y)`.
    """
    var x = List[Float64]()
    var y = List[Float64]()
    x.append(0.0)
    y.append(0.0)
    x.append(1.0)
    y.append(0.0)
    x.append(1.0)
    y.append(1.0)
    x.append(0.0)
    y.append(1.0)
    return (x^, y^)


def _two_triangles() -> List[Int]:
    # Lower-left then upper-right, splitting the square on its diagonal.
    var t = List[Int]()
    t.append(0)
    t.append(1)
    t.append(2)
    t.append(0)
    t.append(2)
    t.append(3)
    return t^


def _zeros(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for _ in range(n):
        v.append(0.0)
    return v^


def _theme() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def test_the_type_and_the_function_are_public() raises:
    # Imported from `dataviz` above rather than reaching into a module:
    # if either name stops being exported this file will not build.
    var pts = _square()
    var tri = delaunay(pts[0], pts[1])
    assert_equal(tri.count(), 2, "a square triangulates into two triangles")
    assert_equal(len(tri.x), 4, "the points come back in their own order")
    assert_equal(
        len(tri.triangles), 6, "three vertex indices per triangle, flat"
    )


def test_a_caller_can_build_one_from_its_own_triangles() raises:
    var pts = _square()
    var tri = Triangulation(pts[0], pts[1], _two_triangles())
    assert_equal(tri.count(), 2, "the caller's own two triangles")
    assert_equal(tri.triangles[0], 0, "and in the caller's own order")
    assert_equal(tri.triangles[5], 3, "including the last index")


def test_a_malformed_triangulation_raises() raises:
    var pts = _square()

    with assert_raises(contains="same length"):
        var short_y = List[Float64]()
        short_y.append(0.0)
        _ = Triangulation(pts[0], short_y, _two_triangles())

    with assert_raises(contains="multiple of 3"):
        var ragged = _two_triangles()
        _ = ragged.pop()
        _ = Triangulation(pts[0], pts[1], ragged)

    with assert_raises(contains="outside the 4 points"):
        var bad = _two_triangles()
        bad[0] = 9
        _ = Triangulation(pts[0], pts[1], bad)


def test_facecolors_color_the_triangle_the_caller_indexed() raises:
    """The capability #397 exists for.

    Two triangles, the first given a low value and the second a high
    one. The lower-left triangle covers the bottom-left of the plot rect
    and the upper-right covers the top-right, so the two regions must
    end up different colors, and swapping the values must swap which
    region is which.

    Comparing the two renders rather than naming colors: the ramp is the
    theme's business, and this test is about which triangle got which
    value.
    """
    var pts = _square()
    var tri = Triangulation(pts[0], pts[1], _two_triangles())

    var low_first = List[Float64]()
    low_first.append(0.0)
    low_first.append(1.0)
    var high_first = List[Float64]()
    high_first.append(1.0)
    high_first.append(0.0)

    var a = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(
            pts[0],
            pts[1],
            _zeros(4),
            triangulation=tri,
            facecolors=low_first,
        )
        .theme(_theme())
        .size(240, 180)
    )
    var b = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(
            pts[0],
            pts[1],
            _zeros(4),
            triangulation=tri,
            facecolors=high_first,
        )
        .theme(_theme())
        .size(240, 180)
    )
    var diff = 0
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b:
                diff += 1
    assert_true(
        diff > 200,
        "swapping the two facecolors changed only "
        + String(diff)
        + " pixels, so the values are not reaching their triangles",
    )


def test_facecolors_without_a_triangulation_raises() raises:
    # The order would be an artifact of the algorithm, so a per-triangle
    # column would be assigned arbitrarily. Refused rather than guessed.
    var pts = _square()
    var f = List[Float64]()
    f.append(0.0)
    f.append(1.0)
    with assert_raises(contains="needs a triangulation to index against"):
        _ = (
            Plot()
            .mark_tripcolor()
            .encode_triplot(pts[0], pts[1], _zeros(4), facecolors=f)
        )


def test_the_wrong_number_of_facecolors_raises_at_render() raises:
    var pts = _square()
    var tri = Triangulation(pts[0], pts[1], _two_triangles())
    var three = List[Float64]()
    three.append(0.0)
    three.append(1.0)
    three.append(2.0)
    with assert_raises(contains="one value per triangle"):
        _ = render(
            Plot()
            .mark_tripcolor()
            .encode_triplot(
                pts[0], pts[1], _zeros(4), triangulation=tri, facecolors=three
            )
            .size(240, 180)
        )


def test_a_supplied_triangulation_is_the_one_drawn() raises:
    # One triangle of the square instead of two: if the render still
    # triangulated internally it would draw both and cover more pixels.
    var pts = _square()
    var one = List[Int]()
    one.append(0)
    one.append(1)
    one.append(2)
    var half = Triangulation(pts[0], pts[1], one)
    var bg = _theme().background

    var whole = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(pts[0], pts[1], _zeros(4))
        .theme(_theme())
        .size(240, 180)
    )
    var partial = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(pts[0], pts[1], _zeros(4), triangulation=half)
        .theme(_theme())
        .size(240, 180)
    )

    var ink_whole = 0
    var ink_partial = 0
    for y in range(whole.height):
        for x in range(whole.width):
            var p = whole.get_pixel(x, y)
            var q = partial.get_pixel(x, y)
            if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                ink_whole += 1
            if not (q.r == bg.r and q.g == bg.g and q.b == bg.b):
                ink_partial += 1
    assert_true(
        ink_partial < ink_whole,
        "one triangle covered as much as two ("
        + String(ink_partial)
        + " against "
        + String(ink_whole)
        + "), so the supplied triangulation was ignored",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
