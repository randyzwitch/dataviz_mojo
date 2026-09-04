"""The shared tree-indexing core behind the hierarchy family
(`Mark.SUNBURST`/`TREE`/`TREEMAP`). All three need the same three
things from `Plot.encode_hierarchy()`'s flat `ids`/`parent_ids`/
`values` rows before any mark-specific layout: who is whose child, how
deep each node is, and each node's subtree total.

A flat `(id, parent_id, value)` row list rather than a tree type, the
same flattening `d3.stratify()` uses, so the package's
plain-columnar-arrays data model covers a hierarchy without a new kind
of value.
"""

from std.collections import Dict


struct _HierarchyData(Copyable, Movable):
    """A flattened hierarchy, one (id, parent_id, value) row per node, for
    `Mark.SUNBURST`/`TREE`/`TREEMAP`. See `encode_hierarchy()`. Stored on
    `Plot._hierarchy`.
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
    """Turn `encode_hierarchy()`'s flat rows into what the hierarchy family
    needs: `children[i]` (every row index whose `parent_ids` points at
    `ids[i]`), `depth[i]` (0 at the root, +1 per level, from one BFS
    pass), and `subtree_value[i]` (a leaf's `values[i]`; an internal
    node's sum of every descendant leaf's value, ignoring its own
    `values[i]`, computed bottom-up in one reverse-BFS pass).

    An empty `parent_ids[i]` (`""`) marks the single root. Raises if zero
    or more than one row qualifies (a forest is out of scope, matching
    `d3.stratify()`'s default), on a duplicate `id`, or on a
    `parent_ids[i]` that matches no `id`.
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

    # Every row must be reachable from the root. The checks above don't
    # catch a cycle: given
    #     ids        = ["root", "leaf", "a", "b"]
    #     parent_ids = ["",     "root", "b", "a"]
    # "a" and "b" are each other's parent, every check passes, the BFS
    # never reaches either, and both rows would silently vanish from the
    # chart. Comparing the traversal's reach against `n` catches cycles and
    # disconnected components alike.
    #
    # This also guarantees that tree.mojo's recursive
    # `_assign_branch_colors`/`_assign_leaf_positions` walk a real tree. The
    # compiler's "self recursive call will cause an infinite loop" warning
    # on that file is a false positive: the recursion is over
    # `children[node]`, which is empty at every leaf.
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
