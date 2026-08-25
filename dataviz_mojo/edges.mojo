"""The shared edge-list core behind the network family
(`Mark.CHORD`/`ARC_DIAGRAM`/`GRAPH`/`SANKEY`): every one of those marks
reads the same three columns from `Plot.encode_chord()` -- a `from`
name, a `to` name and a magnitude per row -- and every one needs the
same two answers about them before any mark-specific layout (a ring
sector, an arc, a node circle, a column) can be computed: are the
columns well-formed, and where does each endpoint sit in the node
domain.

Deliberately the exact shape `hierarchy.mojo` already has for the
hierarchy family (`Mark.SUNBURST`/`TREE`/`TREEMAP`) -- a family's shared data type plus the shared index it gets resolved into, in one
module the family's marks import.

`_EdgeData` lives here rather than on `Plot` beside each single-mark
struct for the same reason: four marks read it, so no one mark's file
is its home, and a shared shape sitting in its family's module is
what makes the sharing visible rather than something you discover by
grepping `from_categories` and noticing four unrelated marks in the
results.
"""

from std.collections import Dict

from dataviz_mojo.plot import Plot, _categorical_indices, _require_non_negative


struct _EdgeData(Movable):
    """
    Mark.CHORD only -- one (from node, to node, value) flow per row. See
    encode_chord()'s docstring.

    Grouped onto `Plot._edges` -- see `Plot`'s docstring.
    """

    var from_categories: List[String]
    var to_categories: List[String]
    var values: List[Float64]

    def __init__(out self):
        self.from_categories = List[String]()
        self.to_categories = List[String]()
        self.values = List[Float64]()


struct _EdgeNodeIndex(Movable):
    """`_edge_node_index`'s result: an edge list's `nodes` (every
    distinct name across both endpoint columns, in first-seen order --
    exactly what `_unique_categories` over the two concatenated
    returns, which is the domain `encode_chord()`'s docstring
    promises) plus `from_idx`/`to_idx`, that domain's position for
    each edge's two endpoints.

    `from_idx[e]`/`to_idx[e]` are edge `e`'s endpoints, so a caller
    never searches the node list by string equality at all.
    """

    var nodes: List[String]
    var from_idx: List[Int]
    var to_idx: List[Int]

    def __init__(
        out self, var nodes: List[String], var from_idx: List[Int], var to_idx: List[Int]
    ):
        self.nodes = nodes^
        self.from_idx = from_idx^
        self.to_idx = to_idx^


def _edge_node_index(
    from_categories: List[String], to_categories: List[String]
) raises -> _EdgeNodeIndex:
    """An edge list's node domain and both endpoint index columns,
    resolved together in one hashed pass -- what every edge-shaped mark
    (`Mark.CHORD`/`ARC_DIAGRAM`/`GRAPH`/`SANKEY`, all four sharing
    `encode_chord()`'s two-column shape) actually needs.

    Hashes each endpoint once (via `_categorical_indices`), making
    node resolution O(e) on average for `e` edges, with every later
    lookup a plain `from_idx[i]` array read.

    This is exactly the fix `_categorical_indices` already applies to
    `Mark.POINT`'s categorical color channel and to
    `Mark.HEATMAP`/`PUNCHCARD`'s axis domains -- see that function's
    docstring. The two columns concatenate into one call, and the
    resulting `indices` split back apart at `len(from_categories)`:
    the first half indexes the `from` column, the second the `to`
    column.

    First-seen order comes from the domain's append order
    (`from_categories` first), so each node's palette color and
    ring/layer position is deterministic across those two columns.
    """
    var combined = List[String](capacity=len(from_categories) + len(to_categories))
    for v in from_categories:
        combined.append(v)
    for v in to_categories:
        combined.append(v)

    var idx = _categorical_indices(combined)
    var split = len(from_categories)
    var total = len(idx.indices)
    var from_idx = List[Int](capacity=split)
    var to_idx = List[Int](capacity=len(to_categories))
    for i in range(split):
        from_idx.append(idx.indices[i])
    for i in range(split, total):
        to_idx.append(idx.indices[i])
    # Copied, not transferred: moving `domain` out of `idx` while
    # `idx.indices` is still being read is a partial move the compiler
    # rejects ("field destroyed out of the middle of a value"). The
    # copy is over the *distinct node names* only -- O(v), not the
    # O(e*v) this function exists to remove -- so it costs nothing the
    # old `_unique_categories` call didn't already spend building that
    # same list.
    return _EdgeNodeIndex(idx.domain.copy(), from_idx^, to_idx^)


def _validate_edge_encoding(plot: Plot, mark_name: String) raises:
    """`Plot.encode_chord()`'s length check plus its non-negative
    rule -- everything `Mark.CHORD`/`ARC_DIAGRAM`/`GRAPH`/`SANKEY` each
    need before laying out an edge list, shared in one place rather
    than duplicated per mark -- the validation counterpart to
    `_edge_node_index`'s node-resolution sharing above.
    """
    if len(plot._edges.from_categories) != len(plot._edges.to_categories) or len(plot._edges.values) != len(
        plot._edges.from_categories
    ):
        raise Error(
            "Plot.encode_chord(): from_categories, to_categories, and"
            " values must all have the same length (got "
            + String(len(plot._edges.from_categories))
            + " from_categories, "
            + String(len(plot._edges.to_categories))
            + " to_categories, "
            + String(len(plot._edges.values))
            + " values)"
        )
    _require_non_negative(plot._edges.values, mark_name)
