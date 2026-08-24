"""The shared tree-indexing core behind the hierarchy family
(`Mark.SUNBURST`/`TREE`/`TREEMAP`): every one of those marks needs the
exact same three answers about `Plot.encode_hierarchy()`'s flat
`ids`/`parent_ids`/`values` rows -- who is whose child, how deep is
each node, and what's each node's subtree total -- before any
mark-specific layout (a ring sector, a node position, a rectangle) can
be computed. Shared by all three callers -- the same "one more real
caller doesn't justify a shared abstraction until it's the *third*
one" tolerance `_draw_categorical_axis_frame`'s docstring already
establishes for the categorical-axis cores.

A flat `(id, parent_id, value)` row list rather than a real tree/graph
type of its own -- the same "the data already says what's needed"
precedent `encode_heatmap()`'s two-categorical-axis shape and `encode_
chord()`'s edge list already set: exactly `d3.stratify()`'s flattening trick (a parent-pointer array instead of nested objects),
chosen so this package's "plain columnar arrays, no Table" data
model (see the wiki) covers a hierarchy without inventing a new kind
of value to hold one.
"""

from std.collections import Dict


struct _HierarchyData(Movable):
    """
    Mark.SUNBURST/TREE/TREEMAP only -- a flattened hierarchy, one (id,
    parent_id, value) row per node. See encode_hierarchy()'s docstring.

    Grouped onto `Plot._hierarchy` -- see `Plot`'s docstring.
    """

    var ids: List[String]
    var parent_ids: List[String]
    var values: List[Float64]

    def __init__(out self):
        self.ids = List[String]()
        self.parent_ids = List[String]()
        self.values = List[Float64]()


struct _HierarchyIndex(Movable):
    """`_build_hierarchy_index`'s finished result -- see that
    function's docstring for what each field means."""

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
    """Turn `encode_hierarchy()`'s flat rows into what every mark
    in the hierarchy family actually needs: `children[i]` (every row
    index whose `parent_ids` points at `ids[i]`), `depth[i]` (0 at
    the single root, +1 per level -- computed by one BFS pass from the
    root, the same "root's children have index 0 at the top"
    top-down reading `_draw_horizontal_categorical_axis_frame`'s category order already establishes elsewhere), and `subtree_value
    [i]` (a leaf's `values[i]`; an internal node's *sum of
    every descendant leaf's value*, not whatever `values[i]` happened
    to be given as -- the standard "a parent's size is its
    children's total" convention every real treemap/sunburst uses,
    computed bottom-up in one reverse-BFS pass once `depth` is known,
    deepest nodes first).

    An empty `parent_ids[i]` (`""`) marks the single root -- raises if
    zero or more than one row qualifies, the same "raise on a
    genuinely inconsistent input" stance `Mark.CALENDAR_HEATMAP`'s single-year requirement already takes: a forest (multiple roots)
    is a real, if less common, hierarchy shape, but out of scope (see
    this module's docstring's `d3.stratify()` comparison -- that
    function has the identical single-root restriction by default).
    Also raises on a duplicate `id`, or
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

    # Every row must be reachable from the root. The checks above catch
    # duplicate ids, unresolvable parent_ids, and a wrong root count --
    # but none of them catches a *cycle*, because every node in one
    # still has exactly one parent that resolves fine. Given
    #     ids     = ["root", "leaf", "a", "b"]
    #     parent_ids = ["",   "root", "b", "a"]
    # "a" and "b" are each other's parent: a two-node cycle hanging off
    # nothing. Every existing check passes, the traversal above simply
    # never reaches either one, and both rows -- with their values --
    # would silently vanish from the chart.
    #
    # This is the same "raise, don't silently misrepresent the data"
    # stance `mark_arc()`'s non-negative check already takes: a
    # chart that quietly drops rows is worse than one that refuses to
    # draw, because nothing about the result looks wrong. Comparing the
    # traversal's reach against `n` catches cycles and disconnected
    # components alike, without a separate cycle-detection pass.
    #
    # It also guarantees the thing tree.mojo's recursive
    # `_assign_branch_colors`/`_assign_leaf_positions` quietly depend
    # on: that the structure they walk really is a tree. A cycle can
    # never be *reachable* from the root anyway -- each row names
    # exactly one parent, so a node inside a cycle can't also be some
    # reachable node's child -- which is why those two functions have
    # never actually been able to recurse forever, whatever the
    # compiler's "self recursive call will cause an infinite loop"
    # warning on that file suggests (that warning is a false positive:
    # the recursion is over `children[node]`, which is empty at every
    # leaf).
    if len(order) != n:
        raise Error(
            "Plot.encode_hierarchy(): "
            + String(n - len(order))
            + " row(s) are not reachable from the root -- the parent_id"
            " graph has a cycle or a disconnected component"
        )

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
