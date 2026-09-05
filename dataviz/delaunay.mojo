"""Delaunay triangulation of scattered points, for contouring data that
does not sit on a grid (#261).

Bowyer-Watson incremental insertion: start from one super-triangle that
contains every point, insert points one at a time, delete the triangles
whose circumcircle the new point falls inside, and re-fill that hole by
joining its boundary to the new point. O(n^2) worst case, which the
issue accepts up to about 50k points.

The output is what `tricontour` needs and nothing more: a vertex list
and a triangle list. No adjacency structure, because contouring walks
triangles independently and joins segments by edge id afterwards, the
same way the grid contour does.
"""


comptime _DEGENERATE_EPS = 1e-12
"""Below this, a triangle's circumcircle denominator counts as zero and
the three points are treated as collinear. Collinear points have no
circumcircle -- the "circle" through them is a line -- so the
containment test has no meaning and answers False, which leaves the
triangle in place rather than deleting it on a divide-by-zero.
"""


struct _Triangulation(Movable):
    """Triangles over a point set, as flat index triples.

    `xs`/`ys` are the input points in their original order, so a caller
    can index its own `z` column with the same index. `tri` holds three
    vertex indices per triangle, so triangle `t` is
    `tri[3*t]`, `tri[3*t + 1]`, `tri[3*t + 2]`.
    """

    var xs: List[Float64]
    var ys: List[Float64]
    var tri: List[Int]

    def __init__(out self):
        self.xs = List[Float64]()
        self.ys = List[Float64]()
        self.tri = List[Int]()

    def count(self) -> Int:
        """How many triangles.

        Returns:
            `len(tri) // 3`.
        """
        return len(self.tri) // 3


def _in_circumcircle(
    ax: Float64,
    ay: Float64,
    bx: Float64,
    by: Float64,
    cx: Float64,
    cy: Float64,
    px: Float64,
    py: Float64,
) -> Bool:
    """Whether `(px, py)` lies strictly inside triangle `abc`'s
    circumcircle.

    Computes the circumcentre and compares squared distances rather than
    using the signed in-circle determinant: the determinant's sign
    depends on the triangle's winding, and Bowyer-Watson's hole-filling
    step produces triangles of both orientations, so a winding-sensitive
    test would delete the wrong ones.

    Args:
        ax: First vertex x.
        ay: First vertex y.
        bx: Second vertex x.
        by: Second vertex y.
        cx: Third vertex x.
        cy: Third vertex y.
        px: Query point x.
        py: Query point y.

    Returns:
        True when the point is inside; False for a collinear triangle,
        which has no circumcircle.
    """
    var d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if abs(d) < _DEGENERATE_EPS:
        return False

    var a2 = ax * ax + ay * ay
    var b2 = bx * bx + by * by
    var c2 = cx * cx + cy * cy
    var ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
    var uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d

    var dx = ax - ux
    var dy = ay - uy
    var r2 = dx * dx + dy * dy
    var qx = px - ux
    var qy = py - uy
    return qx * qx + qy * qy < r2 - _DEGENERATE_EPS


def _edge_key(a: Int, b: Int) -> Int:
    """A canonical id for the undirected edge between vertex indices `a`
    and `b`, so the two triangles sharing it agree on the key.

    Args:
        a: One endpoint's vertex index.
        b: The other's.

    Returns:
        An integer unique to the unordered pair.
    """
    var lo = a if a < b else b
    var hi = b if a < b else a
    return lo * 1000003 + hi


def delaunay(xs: List[Float64], ys: List[Float64]) raises -> _Triangulation:
    """Triangulate the points, Bowyer-Watson.

    Duplicate points are dropped: inserting a point that already exists
    finds no triangle whose circumcircle strictly contains it, which
    would leave an empty hole and no triangles to re-add. Fewer than
    three distinct points, or points that are all collinear, produce no
    triangles at all rather than raising -- a caller contouring them
    draws an empty frame, which is what the data supports.

    Args:
        xs: Point x coordinates.
        ys: Point y coordinates, one per `xs` entry.

    Returns:
        The triangulation; `count()` is 0 for degenerate input.

    Raises:
        Error: `xs` and `ys` have different lengths.
    """
    var n = len(xs)
    if len(ys) != n:
        raise Error(
            "delaunay(): x and y must have the same length (got "
            + String(n)
            + " and "
            + String(len(ys))
            + ")"
        )

    var out = _Triangulation()
    out.xs = xs.copy()
    out.ys = ys.copy()
    if n < 3:
        return out^

    # A super-triangle comfortably containing every point. Its vertices
    # are appended past the real ones so their indices are recognisable,
    # and every triangle still touching one is dropped at the end.
    var min_x = xs[0]
    var max_x = xs[0]
    var min_y = ys[0]
    var max_y = ys[0]
    for i in range(1, n):
        if xs[i] < min_x:
            min_x = xs[i]
        if xs[i] > max_x:
            max_x = xs[i]
        if ys[i] < min_y:
            min_y = ys[i]
        if ys[i] > max_y:
            max_y = ys[i]
    var dx = max_x - min_x
    var dy = max_y - min_y
    var span = dx if dx > dy else dy
    if span <= 0.0:
        # Every point identical: no triangle exists.
        return out^
    var mid_x = (min_x + max_x) / 2.0
    var mid_y = (min_y + max_y) / 2.0
    var big = span * 20.0

    var work_x = xs.copy()
    var work_y = ys.copy()
    work_x.append(mid_x - big)
    work_y.append(mid_y - big)
    work_x.append(mid_x + big)
    work_y.append(mid_y - big)
    work_x.append(mid_x)
    work_y.append(mid_y + big)
    var s0 = n
    var s1 = n + 1
    var s2 = n + 2

    var tri = List[Int]()
    tri.append(s0)
    tri.append(s1)
    tri.append(s2)

    for p in range(n):
        var px = work_x[p]
        var py = work_y[p]

        # Triangles whose circumcircle swallows this point come out; the
        # boundary of the hole they leave is every edge not shared by two
        # of them.
        var keep = List[Int]()
        var hole_a = List[Int]()
        var hole_b = List[Int]()
        for t in range(len(tri) // 3):
            var i0 = tri[3 * t]
            var i1 = tri[3 * t + 1]
            var i2 = tri[3 * t + 2]
            var bad = _in_circumcircle(
                work_x[i0],
                work_y[i0],
                work_x[i1],
                work_y[i1],
                work_x[i2],
                work_y[i2],
                px,
                py,
            )
            if bad:
                hole_a.append(i0)
                hole_b.append(i1)
                hole_a.append(i1)
                hole_b.append(i2)
                hole_a.append(i2)
                hole_b.append(i0)
            else:
                keep.append(i0)
                keep.append(i1)
                keep.append(i2)

        tri = keep^

        # An edge appearing twice among the deleted triangles was interior
        # to the hole; only the ones appearing once form its boundary.
        for e in range(len(hole_a)):
            var shared = False
            for f in range(len(hole_a)):
                if f == e:
                    continue
                if _edge_key(hole_a[e], hole_b[e]) == _edge_key(
                    hole_a[f], hole_b[f]
                ):
                    shared = True
                    break
            if not shared:
                tri.append(hole_a[e])
                tri.append(hole_b[e])
                tri.append(p)

    # Drop anything still touching the super-triangle.
    for t in range(len(tri) // 3):
        var i0 = tri[3 * t]
        var i1 = tri[3 * t + 1]
        var i2 = tri[3 * t + 2]
        if i0 >= s0 or i1 >= s0 or i2 >= s0:
            continue
        out.tri.append(i0)
        out.tri.append(i1)
        out.tri.append(i2)

    return out^
