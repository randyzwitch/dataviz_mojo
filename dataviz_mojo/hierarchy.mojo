"""The shared tree-indexing core behind Phase 7's hierarchy family
(`Mark.SUNBURST`/`TREE`/`TREEMAP`): every one of those marks needs the
exact same three answers about `Plot.encode_hierarchy()`'s own flat
`ids`/`parent_ids`/`values` rows -- who is whose child, how deep is
each node, and what's each node's own subtree total -- before any
mark-specific layout (a ring sector, a node position, a rectangle) can
be computed. Factored out once a third caller needed it, the same
"one more real caller doesn't justify a shared abstraction until it's
the *third* one" tolerance `_draw_categorical_axis_frame`'s own
docstring already established for the categorical-axis cores.

A flat `(id, parent_id, value)` row list rather than a real tree/graph
type of its own -- the same "the data already says what's needed"
precedent `encode_heatmap()`'s two-categorical-axis shape and `encode_
chord()`'s own edge list already set: exactly `d3.stratify()`'s own
flattening trick (a parent-pointer array instead of nested objects),
chosen so this package's own "plain columnar arrays, no Table" data
model (see the wiki) covers a hierarchy without inventing a new kind
of value to hold one.
"""

from std.collections import Dict


struct _HierarchyIndex(Movable):
    """`_build_hierarchy_index`'s own finished result -- see that
    function's own docstring for what each field means."""

    var children: List[List[Int]]
    var subtree_value: List[Float64]
    var depth: List[Int]
    var root: Int
    var max_depth: Int

    def __init__(
        out self,
        var children: List[List[Int]],
        var subtree_value: List[Float64],
        var depth: List[Int],
        root: Int,
        max_depth: Int,
    ):
        self.children = children^
        self.subtree_value = subtree_value^
        self.depth = depth^
        self.root = root
        self.max_depth = max_depth


def _build_hierarchy_index(
    ids: List[String], parent_ids: List[String], values: List[Float64]
) raises -> _HierarchyIndex:
    """Turn `encode_hierarchy()`'s own flat rows into what every mark
    in the hierarchy family actually needs: `children[i]` (every row
    index whose own `parent_ids` points at `ids[i]`), `depth[i]` (0 at
    the single root, +1 per level -- computed by one BFS pass from the
    root, the same "root's own children have index 0 at the top"
    top-down reading `_draw_horizontal_categorical_axis_frame`'s own
    category order already establishes elsewhere), and `subtree_value
    [i]` (a leaf's own `values[i]`; an internal node's own *sum of
    every descendant leaf's value*, not whatever `values[i]` happened
    to be given as -- the standard "a parent's own size is its
    children's total" convention every real treemap/sunburst uses,
    computed bottom-up in one reverse-BFS pass once `depth` is known,
    deepest nodes first).

    An empty `parent_ids[i]` (`""`) marks the single root -- raises if
    zero or more than one row qualifies, the same "raise on a
    genuinely inconsistent input" stance `Mark.CALENDAR_HEATMAP`'s own
    single-year requirement already takes: a forest (multiple roots)
    is a real, if less common, hierarchy shape, but out of scope for
    this first version (see this module's own docstring's `d3.
    stratify()` comparison -- that function has the identical single-
    root restriction by default). Also raises on a duplicate `id`, or
    a `parent_ids[i]` that doesn't match any given `id` (other than
    the empty-string root sentinel).
    """
    var n = len(ids)
    var id_to_row = Dict[String, Int]()
    for i in range(n):
        if ids[i] in id_to_row:
            raise Error("Plot.encode_hierarchy(): duplicate id " + ids[i])
        id_to_row[ids[i]] = i

    var children = List[List[Int]]()
    for _ in range(n):
        children.append(List[Int]())

    var root = -1
    for i in range(n):
        if parent_ids[i] == "":
            if root != -1:
                raise Error(
                    "Plot.encode_hierarchy(): more than one root (empty parent_id) found -- "
                    + ids[root]
                    + " and "
                    + ids[i]
                )
            root = i
        else:
            if parent_ids[i] not in id_to_row:
                raise Error(
                    "Plot.encode_hierarchy(): parent_id " + parent_ids[i] + " not found among ids"
                )
            children[id_to_row[parent_ids[i]]].append(i)
    if root == -1:
        raise Error("Plot.encode_hierarchy(): no root found (exactly one row must have an empty parent_id)")

    var depth = List[Int](capacity=n)
    for _ in range(n):
        depth.append(-1)
    depth[root] = 0
    var max_depth = 0
    var order = List[Int](capacity=n)
    order.append(root)
    var qi = 0
    while qi < len(order):
        var node = order[qi]
        qi += 1
        for c in children[node]:
            depth[c] = depth[node] + 1
            if depth[c] > max_depth:
                max_depth = depth[c]
            order.append(c)

    var subtree_value = List[Float64](capacity=n)
    for _ in range(n):
        subtree_value.append(0.0)
    for i in range(len(order) - 1, -1, -1):
        var node = order[i]
        if len(children[node]) == 0:
            subtree_value[node] = values[node]
        else:
            var total = 0.0
            for c in children[node]:
                total += subtree_value[c]
            subtree_value[node] = total

    return _HierarchyIndex(children^, subtree_value^, depth^, root, max_depth)
