"""Delaunay triangulation of scattered points using Bowyer-Watson insertion.

Bowyer-Watson incremental insertion: start from one super-triangle that
contains every point, insert points one at a time, delete the triangles
whose circumcircle the new point falls inside, and re-fill that hole by
joining its boundary to the new point.

Adjacency supports walking to each insertion and flooding its circumcircle
cavity. Boustrophedon grid ordering keeps consecutive insertions nearby.
The result contains vertex and triangle lists; build-time adjacency is not
retained.
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

    Computes the circumcenter and compares squared distances rather than
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


def _orient2d(
    ax: Float64, ay: Float64, bx: Float64, by: Float64, px: Float64, py: Float64
) -> Float64:
    """Twice the signed area of triangle `abp`: positive when `p` is left
    of the directed edge `a -> b`, negative when right, zero when the
    three are collinear.

    The walk in `_locate` uses the sign to decide which edge to cross,
    which is why every triangle this file builds is wound
    counter-clockwise -- a mixed-winding triangle list has no consistent
    "outside".

    Args:
        ax: Edge start x.
        ay: Edge start y.
        bx: Edge end x.
        by: Edge end y.
        px: Query point x.
        py: Query point y.

    Returns:
        The signed area, doubled.
    """
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax)


def _grid_order(xs: List[Float64], ys: List[Float64], n: Int) -> List[Int]:
    """Point indices in boustrophedon grid order: bucketed into a
    roughly sqrt(n/2)-per-side grid, rows bottom to top, and every other
    row right to left so the end of one row is next to the start of the
    next.

    This is the whole reason `_locate`'s walk is short. Inserting in the
    caller's order sends it across the triangulation each time; inserting
    in spatial order leaves the next point a few triangles from the last.
    Sorting is a counting sort over cell ids, so it costs O(n + cells).

    Args:
        xs: Point x coordinates.
        ys: Point y coordinates.
        n: How many points.

    Returns:
        The indices `0..n-1`, reordered.
    """
    var side = 1
    while side * side * 2 < n:
        side += 1

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
    var w = max_x - min_x
    var h = max_y - min_y

    var cell = List[Int](capacity=n)
    var cells = side * side
    var counts = List[Int](capacity=cells + 1)
    for _ in range(cells + 1):
        counts.append(0)
    for i in range(n):
        var cx = 0
        var cy = 0
        if w > 0.0:
            cx = Int((xs[i] - min_x) / w * Float64(side - 1) + 0.5)
        if h > 0.0:
            cy = Int((ys[i] - min_y) / h * Float64(side - 1) + 0.5)
        # Serpentine: odd rows run backwards, so consecutive cells in the
        # ordering are always physically adjacent.
        var col = cx if cy % 2 == 0 else side - 1 - cx
        var key = cy * side + col
        cell.append(key)
        counts[key + 1] += 1
    for k in range(cells):
        counts[k + 1] += counts[k]

    var order = List[Int](capacity=n)
    for _ in range(n):
        order.append(0)
    for i in range(n):
        order[counts[cell[i]]] = i
        counts[cell[i]] += 1
    return order^


def _in_list(xs: List[Int], v: Int) -> Bool:
    """Whether `v` appears in `xs`.

    Used only against the current cavity, which is a handful of
    triangles, so a scan is cheaper than a set.

    Args:
        xs: The list to search.
        v: The value to look for.

    Returns:
        True when present.
    """
    for x in xs:
        if x == v:
            return True
    return False


def _contains_in_circle(
    work_x: List[Float64],
    work_y: List[Float64],
    tri: List[Int],
    t: Int,
    px: Float64,
    py: Float64,
) -> Bool:
    """Whether triangle `t`'s circumcircle strictly contains `(px, py)`.

    A three-argument wrapper so the flood fill reads as one test rather
    than six index lookups.

    Args:
        work_x: Point x coordinates, real points then super-triangle.
        work_y: Point y coordinates, matching `work_x`.
        tri: Flat vertex triples.
        t: Which triangle.
        px: Query point x.
        py: Query point y.

    Returns:
        True when the point falls inside.
    """
    var i0 = tri[3 * t]
    var i1 = tri[3 * t + 1]
    var i2 = tri[3 * t + 2]
    return _in_circumcircle(
        work_x[i0],
        work_y[i0],
        work_x[i1],
        work_y[i1],
        work_x[i2],
        work_y[i2],
        px,
        py,
    )


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
    # are appended past the real ones so their indices are recognizable,
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

    # Triangles as flat vertex triples, with a neighbor per edge and a
    # tombstone flag. Edge `e` of triangle `t` runs from vertex `e` to
    # vertex `(e + 1) % 3`, and `nbr[3*t + e]` is the triangle across it
    # (-1 outside the super-triangle). Dead triangles are left in place
    # rather than compacted, so indices stay stable while the walk and
    # the flood fill hold them.
    var tri = List[Int]()
    var nbr = List[Int]()
    var dead = List[Bool]()
    tri.append(s0)
    tri.append(s1)
    tri.append(s2)
    nbr.append(-1)
    nbr.append(-1)
    nbr.append(-1)
    dead.append(False)

    var order = _grid_order(xs, ys, n)
    var here = 0

    var cavity = List[Int]()
    var stack = List[Int]()
    var edge_a = List[Int]()
    var edge_b = List[Int]()
    var edge_out = List[Int]()

    for oi in range(n):
        var p = order[oi]
        var px = work_x[p]
        var py = work_y[p]

        # --- locate: walk to the triangle containing the point --------
        # Each step crosses the one edge the point is on the far side of.
        # Starting from the last insertion's triangle, spatial ordering
        # keeps this to a few steps; the cap is a safety net for
        # degenerate input, where a walk can cycle between two triangles.
        if dead[here]:
            here = 0
            while here < len(dead) and dead[here]:
                here += 1
        var steps = 0
        var cap = 2 * len(dead) + 16
        var found = False
        while steps < cap:
            steps += 1
            var a = tri[3 * here]
            var b = tri[3 * here + 1]
            var c = tri[3 * here + 2]
            var moved = False
            if (
                _orient2d(work_x[a], work_y[a], work_x[b], work_y[b], px, py)
                < 0.0
            ):
                var nx = nbr[3 * here]
                if nx >= 0:
                    here = nx
                    moved = True
            if not moved and (
                _orient2d(work_x[b], work_y[b], work_x[c], work_y[c], px, py)
                < 0.0
            ):
                var nx = nbr[3 * here + 1]
                if nx >= 0:
                    here = nx
                    moved = True
            if not moved and (
                _orient2d(work_x[c], work_y[c], work_x[a], work_y[a], px, py)
                < 0.0
            ):
                var nx = nbr[3 * here + 2]
                if nx >= 0:
                    here = nx
                    moved = True
            if not moved:
                found = True
                break
        if not found:
            # Fall back to a scan when the adjacency walk cannot settle.
            for t2 in range(len(dead)):
                if dead[t2]:
                    continue
                var a = tri[3 * t2]
                var b = tri[3 * t2 + 1]
                var c = tri[3 * t2 + 2]
                if (
                    _orient2d(
                        work_x[a], work_y[a], work_x[b], work_y[b], px, py
                    )
                    >= 0.0
                    and _orient2d(
                        work_x[b], work_y[b], work_x[c], work_y[c], px, py
                    )
                    >= 0.0
                    and _orient2d(
                        work_x[c], work_y[c], work_x[a], work_y[a], px, py
                    )
                    >= 0.0
                ):
                    here = t2
                    break

        # --- cavity: flood out from it while circumcircles contain p ---
        # The triangles whose circumcircle holds the point form one
        # connected patch, so growing it across adjacency reaches all of
        # them without testing any triangle outside it.
        cavity.clear()
        stack.clear()
        edge_a.clear()
        edge_b.clear()
        edge_out.clear()

        if not _contains_in_circle(work_x, work_y, tri, here, px, py):
            # No triangle swallows the point: it is a duplicate of one
            # already inserted. Dropping it is what the scan version did.
            continue

        stack.append(here)
        cavity.append(here)
        dead[here] = True
        while len(stack) > 0:
            var cur = stack[len(stack) - 1]
            _ = stack.pop()
            for e in range(3):
                var opp = nbr[3 * cur + e]
                var a = tri[3 * cur + e]
                var b = tri[3 * cur + (e + 1) % 3]
                if (
                    opp >= 0
                    and not dead[opp]
                    and _contains_in_circle(work_x, work_y, tri, opp, px, py)
                ):
                    dead[opp] = True
                    cavity.append(opp)
                    stack.append(opp)
                elif opp < 0 or dead[opp]:
                    # `dead` is either a cavity member (interior edge, and
                    # the other side records it too) or a tombstone from an
                    # earlier insertion, which adjacency never points at.
                    if opp < 0 or not _in_list(cavity, opp):
                        edge_a.append(a)
                        edge_b.append(b)
                        edge_out.append(opp)
                else:
                    edge_a.append(a)
                    edge_b.append(b)
                    edge_out.append(opp)

        # --- refill: one new triangle per boundary edge ---------------
        # Wound (a, b, p) so it inherits the boundary edge's direction,
        # which keeps every triangle counter-clockwise for the walk.
        var first_new = len(dead)
        for k in range(len(edge_a)):
            tri.append(edge_a[k])
            tri.append(edge_b[k])
            tri.append(p)
            nbr.append(edge_out[k])
            nbr.append(-1)
            nbr.append(-1)
            dead.append(False)
            var t_new = len(dead) - 1
            # Point the outside triangle back at this one.
            var opp = edge_out[k]
            if opp >= 0:
                for e in range(3):
                    if (
                        tri[3 * opp + e] == edge_b[k]
                        and tri[3 * opp + (e + 1) % 3] == edge_a[k]
                    ):
                        nbr[3 * opp + e] = t_new
                        break

        # Link the new triangles to each other: each shares edge (b, p)
        # with the one whose (p, a) matches. The fan is small, so
        # matching by scan costs less than a map would.
        var made = len(edge_a)
        for i in range(made):
            var ti = first_new + i
            for j in range(made):
                if i == j:
                    continue
                var tj = first_new + j
                if tri[3 * tj] == tri[3 * ti + 1]:
                    nbr[3 * ti + 1] = tj
                if tri[3 * tj + 1] == tri[3 * ti]:
                    nbr[3 * ti + 2] = tj
        if made > 0:
            here = first_new

    # Drop anything dead or still touching the super-triangle.
    for t in range(len(dead)):
        if dead[t]:
            continue
        var i0 = tri[3 * t]
        var i1 = tri[3 * t + 1]
        var i2 = tri[3 * t + 2]
        if i0 >= s0 or i1 >= s0 or i2 >= s0:
            continue
        out.tri.append(i0)
        out.tri.append(i1)
        out.tri.append(i2)

    return out^
