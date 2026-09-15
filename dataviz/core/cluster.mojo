"""Agglomerative clustering of a matrix's rows: a distance, a linkage
rule, the merge tree they produce, and the leaf order that tree implies
(#355).

No drawing here. A clustermap's whole point is the *reordering* -- a
heatmap in arbitrary row order shows almost nothing, and the same matrix
with similar rows together shows its block structure at a glance -- and
the reordering is a numerical question with a right answer, testable
against a hand-worked example without rendering anything.

The algorithm is the nearest-neighbour chain, which is O(n^2) time and
O(n^2) memory rather than the O(n^3) of repeatedly scanning for the
closest pair. That matters here: #325 had just finished taking an
O(n^2) out of `delaunay()`, and the benchmark guard exists so the next
one is caught rather than shipped. `scripts/bench.mojo` carries this
from the start.

The chain works by walking from a cluster to its nearest neighbour, then
to *that* one's nearest neighbour, until two are each other's nearest --
a reciprocal pair, which is always safe to merge. Every linkage here is
"reducible", meaning a merge never makes some other pair closer than
both were to each other, which is exactly the property that makes the
walk valid. Lance-Williams gives the updated distance in constant time
per remaining cluster, so no distance is ever recomputed from the rows.
"""

from std.math import isfinite, sqrt


struct DistanceMetric(Copyable, ImplicitlyCopyable, Movable):
    """How far apart two rows are.

    The choice changes what "similar" means, and it changes the answer:
    `EUCLIDEAN` groups rows whose values are close, `CORRELATION` groups
    rows whose values move together whatever their level, which is
    usually what is wanted when the rows are measured in different units
    or at different baselines.
    """

    var _value: Int
    comptime EUCLIDEAN = Self(0)
    """Straight-line distance: `sqrt(sum((a - b)^2))`."""
    comptime CITYBLOCK = Self(1)
    """Sum of absolute differences, less swayed by one large gap."""
    comptime CORRELATION = Self(2)
    """`1 - r`, for Pearson's `r`: two rows that rise and fall together
    are close however far apart their levels are. A row with no
    variation has no correlation with anything, and is treated as
    maximally distant (`1.0`) from every other row rather than left
    undefined."""

    def __init__(out self, value: Int):
        """Construct from the integer tag.

        Args:
            value: The tag.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        """Whether two metrics are the same.

        Args:
            other: The metric to compare with.

        Returns:
            True when they match.
        """
        return self._value == other._value


struct Linkage(Copyable, ImplicitlyCopyable, Movable):
    """How far apart two *clusters* are, given how far apart their
    members are.

    All four are reducible, which is what lets the nearest-neighbour
    chain merge a reciprocal pair without checking anything else.
    """

    var _value: Int
    comptime SINGLE = Self(0)
    """The closest pair across the two clusters. Finds long straggling
    shapes, and chains through noise for the same reason."""
    comptime COMPLETE = Self(1)
    """The furthest pair. Compact, equally sized clusters, and one
    outlier holds a whole cluster away."""
    comptime AVERAGE = Self(2)
    """The mean over every cross pair. The usual choice, and the default
    here."""
    comptime WARD = Self(3)
    """The merge that adds least to the total within-cluster spread.
    Defined in terms of squared Euclidean distance, so it is only
    meaningful with `DistanceMetric.EUCLIDEAN`; `linkage()` raises on
    any other pairing rather than returning a number that looks fine."""

    def __init__(out self, value: Int):
        """Construct from the integer tag.

        Args:
            value: The tag.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        """Whether two linkages are the same.

        Args:
            other: The linkage to compare with.

        Returns:
            True when they match.
        """
        return self._value == other._value


struct Merge(Copyable, ImplicitlyCopyable, Movable):
    """One join in a `Dendrogram`: two nodes and the distance they were
    joined at.

    `left` and `right` are node ids: `0 .. n-1` are the original rows and
    `n + k` is the node the `k`-th merge created, so a tree of `n` rows
    has `n - 1` merges and a root of `2n - 2`.
    """

    var left: Int
    var right: Int
    var height: Float64
    """The linkage distance between the two nodes when they joined; the
    height a dendrogram draws the bracket at."""
    var size: Int
    """How many original rows are under this node."""

    def __init__(out self, left: Int, right: Int, height: Float64, size: Int):
        """Record one merge.

        Args:
            left: The first node's id.
            right: The second node's id.
            height: The distance they joined at.
            size: How many rows are under the result.
        """
        self.left = left
        self.right = right
        self.height = height
        self.size = size


struct Dendrogram(Movable):
    """A finished merge tree: the joins in increasing height, and the
    leaf order they imply.

    `merges` is sorted by height and renumbered so a node's children
    always come before it, which is what lets anything walk the tree in
    one forward pass.
    """

    var merges: List[Merge]
    var leaf_order: List[Int]
    """The original row indices, left to right, as the tree lays them
    out: every cluster's rows are contiguous, which is the whole point.
    """

    def __init__(out self, var merges: List[Merge], var leaf_order: List[Int]):
        """Construct from already-computed merges and order.

        Args:
            merges: The joins, sorted by height.
            leaf_order: The row indices in tree order.
        """
        self.merges = merges^
        self.leaf_order = leaf_order^

    def height_of(self, index: Int) -> Float64:
        """The `index`-th merge's height.

        Args:
            index: Which merge.

        Returns:
            Its height, or 0.0 when out of range.
        """
        if index < 0 or index >= len(self.merges):
            return 0.0
        return self.merges[index].height


def _row_distance(
    a: List[Float64], b: List[Float64], metric: DistanceMetric
) -> Float64:
    """The distance between two rows under `metric`.

    Args:
        a: One row.
        b: The other, the same length.
        metric: Which distance.

    Returns:
        The distance, never negative.
    """
    var n = len(a)
    if metric == DistanceMetric.CITYBLOCK:
        var total = 0.0
        for i in range(n):
            var d = a[i] - b[i]
            total += d if d >= 0.0 else -d
        return total
    if metric == DistanceMetric.CORRELATION:
        var mean_a = 0.0
        var mean_b = 0.0
        for i in range(n):
            mean_a += a[i]
            mean_b += b[i]
        mean_a /= Float64(n)
        mean_b /= Float64(n)
        var num = 0.0
        var da = 0.0
        var db = 0.0
        for i in range(n):
            var xa = a[i] - mean_a
            var xb = b[i] - mean_b
            num += xa * xb
            da += xa * xa
            db += xb * xb
        if da <= 0.0 or db <= 0.0:
            # A flat row moves with nothing, so it correlates with
            # nothing. Reporting 1.0 keeps it as far away as any
            # anti-correlated row instead of leaving a NaN to spread
            # through every later distance.
            return 1.0
        return 1.0 - num / sqrt(da * db)
    var total = 0.0
    for i in range(n):
        var d = a[i] - b[i]
        total += d * d
    return sqrt(total)


def _lance_williams(
    method: Linkage,
    d_ik: Float64,
    d_jk: Float64,
    d_ij: Float64,
    n_i: Int,
    n_j: Int,
    n_k: Int,
) -> Float64:
    """The distance from the cluster `i + j` to cluster `k`, from the
    three distances among `i`, `j` and `k`.

    Constant time per remaining cluster, which is what keeps the whole
    algorithm quadratic: no distance is ever recomputed from the rows.

    Args:
        method: The linkage rule.
        d_ik: Distance from `i` to `k`.
        d_jk: Distance from `j` to `k`.
        d_ij: Distance from `i` to `j`, the height they merged at.
        n_i: Rows in `i`.
        n_j: Rows in `j`.
        n_k: Rows in `k`.

    Returns:
        The updated distance.
    """
    if method == Linkage.SINGLE:
        return d_ik if d_ik < d_jk else d_jk
    if method == Linkage.COMPLETE:
        return d_ik if d_ik > d_jk else d_jk
    if method == Linkage.AVERAGE:
        var wi = Float64(n_i)
        var wj = Float64(n_j)
        return (wi * d_ik + wj * d_jk) / (wi + wj)
    # Ward, in distance rather than squared-distance form.
    var a = Float64(n_i + n_k)
    var b = Float64(n_j + n_k)
    var c = Float64(n_k)
    var total = Float64(n_i + n_j + n_k)
    var value = (a * d_ik * d_ik + b * d_jk * d_jk - c * d_ij * d_ij) / total
    return sqrt(value) if value > 0.0 else 0.0


def linkage(
    rows: List[List[Float64]],
    metric: DistanceMetric = DistanceMetric.EUCLIDEAN,
    method: Linkage = Linkage.AVERAGE,
) raises -> Dendrogram:
    """Cluster `rows` and return the merge tree and leaf order (#355).

    Nearest-neighbour chain: walk from a cluster to its nearest
    neighbour and on to that one's, until two are each other's nearest.
    Such a pair is always safe to merge under a reducible linkage, which
    all four here are, so the walk never has to be undone. That is
    O(n^2) work against the O(n^3) of rescanning for the closest pair
    each round, and it is the reason this is usable past a few dozen
    rows.

    Args:
        rows: One list per row, all the same length and at least two
            rows.
        metric: How far apart two rows are.
        method: How far apart two clusters are.

    Returns:
        The merge tree, sorted by height, with its leaf order.

    Raises:
        Error: Fewer than two rows, rows of differing length, an empty
            row, a non-finite value, or `Linkage.WARD` with a metric
            other than `EUCLIDEAN`.
    """
    var n = len(rows)
    if n < 2:
        raise Error(
            "linkage(): needs at least two rows to cluster -- got " + String(n)
        )
    if len(rows[0]) == 0:
        raise Error("linkage(): rows must have at least one column")
    for i in range(n):
        if len(rows[i]) != len(rows[0]):
            raise Error(
                "linkage(): every row needs the same number of columns --"
                " row 0 has "
                + String(len(rows[0]))
                + " and row "
                + String(i)
                + " has "
                + String(len(rows[i]))
            )
        for j in range(len(rows[i])):
            if not isfinite(rows[i][j]):
                raise Error(
                    "linkage(): every value must be finite -- got "
                    + String(rows[i][j])
                    + " at row "
                    + String(i)
                    + ", column "
                    + String(j)
                )
    if method == Linkage.WARD and not (metric == DistanceMetric.EUCLIDEAN):
        raise Error(
            "linkage(): Linkage.WARD is defined in terms of squared"
            " Euclidean distance, so it only means anything with"
            " DistanceMetric.EUCLIDEAN -- pass that, or choose"
            " Linkage.AVERAGE/COMPLETE/SINGLE for this metric"
        )

    # Full matrix rather than a condensed one: the chain reads a whole
    # row looking for a nearest neighbour, which a condensed layout
    # makes an index puzzle for no memory saved that matters at the row
    # counts this is for.
    var total = 2 * n - 1
    var dist = List[Float64](capacity=total * total)
    for _ in range(total * total):
        dist.append(0.0)
    for i in range(n):
        for j in range(i + 1, n):
            var d = _row_distance(rows[i], rows[j], metric)
            dist[i * total + j] = d
            dist[j * total + i] = d

    var active = List[Bool](capacity=total)
    var size = List[Int](capacity=total)
    for i in range(total):
        active.append(i < n)
        size.append(1 if i < n else 0)

    var merges = List[Merge]()
    var chain = List[Int]()
    var next_id = n
    while len(merges) < n - 1:
        if len(chain) == 0:
            for i in range(total):
                if active[i]:
                    chain.append(i)
                    break
        var a = chain[len(chain) - 1]
        # `a`'s nearest active neighbour. Ties go to the lowest id, so
        # the same input always produces the same tree.
        var b = -1
        var best = 0.0
        for i in range(total):
            if not active[i] or i == a:
                continue
            var d = dist[a * total + i]
            if b < 0 or d < best:
                b = i
                best = d
        if len(chain) >= 2 and b == chain[len(chain) - 2]:
            # Reciprocal pair: `a` and `b` are each other's nearest, so
            # nothing else can come between them. Merge.
            _ = chain.pop()
            _ = chain.pop()
            var new_id = next_id
            next_id += 1
            merges.append(Merge(a, b, best, size[a] + size[b]))
            for k in range(total):
                if not active[k] or k == a or k == b:
                    continue
                var updated = _lance_williams(
                    method,
                    dist[a * total + k],
                    dist[b * total + k],
                    best,
                    size[a],
                    size[b],
                    size[k],
                )
                dist[new_id * total + k] = updated
                dist[k * total + new_id] = updated
            active[a] = False
            active[b] = False
            size[new_id] = size[a] + size[b]
            active[new_id] = True
        else:
            chain.append(b)

    return _finish(merges^, n)


def _finish(var merges: List[Merge], n: Int) raises -> Dendrogram:
    """Sort `merges` by height, renumber the nodes to match, and read off
    the leaf order.

    The chain produces merges in the order it happened to find them,
    which is not height order. Sorting makes a node's children always
    come before it, so anything reading the tree can do it in one
    forward pass; the renumbering is what keeps the ids pointing at the
    right nodes afterwards.

    Args:
        merges: The joins as produced.
        n: How many original rows.

    Returns:
        The finished dendrogram.

    Raises:
        Error: The tree is malformed, which would be a bug here.
    """
    var order = List[Int](capacity=len(merges))
    for i in range(len(merges)):
        order.append(i)
    # Insertion sort on height: the list is n-1 long and nearly sorted
    # already, and a stable sort keeps ties in the order they happened.
    for a in range(1, len(order)):
        var key = order[a]
        var key_h = merges[key].height
        var b = a - 1
        while b >= 0 and merges[order[b]].height > key_h:
            order[b + 1] = order[b]
            b -= 1
        order[b + 1] = key

    # old node id -> new node id, for the internal nodes only; leaves
    # keep their own indices.
    var remap = List[Int](capacity=n + len(merges))
    for i in range(n + len(merges)):
        remap.append(i)
    for position in range(len(order)):
        remap[n + order[position]] = n + position

    var sorted_merges = List[Merge](capacity=len(merges))
    for position in range(len(order)):
        var m = merges[order[position]]
        # Smaller id first. The chain hands back whichever of the pair
        # it happened to be standing on, which is not a fact about the
        # data; fixing an order here makes the tree, and so the leaf
        # order, the same every run. Smaller means "merged earlier or a
        # lower row index", so a tie-free set of rows comes out in its
        # own order rather than reversed.
        var lo = remap[m.left]
        var hi = remap[m.right]
        if hi < lo:
            var swap = lo
            lo = hi
            hi = swap
        sorted_merges.append(Merge(lo, hi, m.height, m.size))

    # Leaf order: walk the tree from the root, left subtree first, with
    # an explicit stack rather than recursion.
    var leaf_order = List[Int]()
    if len(sorted_merges) > 0:
        var stack = List[Int]()
        stack.append(n + len(sorted_merges) - 1)
        while len(stack) > 0:
            var node = stack.pop()
            if node < n:
                leaf_order.append(node)
                continue
            var m = sorted_merges[node - n]
            # Pushed right first so the left subtree comes off next.
            stack.append(m.right)
            stack.append(m.left)
    if len(leaf_order) != n:
        raise Error(
            "linkage(): the merge tree does not cover every row -- got "
            + String(len(leaf_order))
            + " leaves for "
            + String(n)
            + " rows"
        )
    return Dendrogram(sorted_merges^, leaf_order^)
