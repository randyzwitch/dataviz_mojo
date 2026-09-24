"""The shared edge-list core behind the network family
(`Mark.CHORD`/`ARC_DIAGRAM`/`GRAPH`/`SANKEY`). All four read the same
three columns from `Plot.encode_chord()` (a `from` name, a `to` name,
and a magnitude per row) and need the same two things before any
mark-specific layout: validation of those columns, and each
endpoint's position in the node domain.

Same shape as `hierarchy.mojo` for the hierarchy family: the family's
shared data type plus the shared index it resolves into, in one module
the family's marks import. `_EdgeData` lives here rather than on
`Plot` because four marks read it.
"""


from dataviz.plot import Plot
from dataviz.core.frame import _categorical_indices
from dataviz.core.validate import _require_non_empty, _require_non_negative
from dataviz.core.graph_layout import GraphLayout
from dataviz.core.mark import Mark, _require_mark


struct _EdgeData(Copyable, Movable):
    """One (from node, to node, value) flow per row, for `Mark.CHORD`/
    `ARC_DIAGRAM`/`GRAPH`/`SANKEY`. See `encode_chord()`. Stored on
    `Plot._edges`.
    """

    var from_categories: List[String]
    var to_categories: List[String]
    var values: List[Float64]

    def __init__(out self):
        self.from_categories = List[String]()
        self.to_categories = List[String]()
        self.values = List[Float64]()


struct _EdgeNodeIndex(Movable):
    """`_edge_node_index`'s result: `nodes` (every distinct name across both
    endpoint columns, in first-seen order, the domain `encode_chord()`
    documents) plus `from_idx`/`to_idx`, each edge's endpoint positions in
    that domain.
    """

    var nodes: List[String]
    var from_idx: List[Int]
    var to_idx: List[Int]

    def __init__(
        out self,
        var nodes: List[String],
        var from_idx: List[Int],
        var to_idx: List[Int],
    ):
        self.nodes = nodes^
        self.from_idx = from_idx^
        self.to_idx = to_idx^


def _edge_node_index(
    from_categories: List[String], to_categories: List[String]
) raises -> _EdgeNodeIndex:
    """Resolve an edge list's node domain and both endpoint index columns in
    one hashed pass. The two columns are concatenated into a single
    `_categorical_indices` call (`from_categories` first, so first-seen
    order is deterministic) and the resulting indices split back apart at
    `len(from_categories)`.
    """
    var combined = List[String](
        capacity=len(from_categories) + len(to_categories)
    )
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
    # Copied, not moved: moving `domain` out of `idx` while `idx.indices` is
    # still being read is a partial move the compiler rejects. The copy
    # covers only the distinct node names.
    return _EdgeNodeIndex(idx.domain.copy(), from_idx^, to_idx^)


def _validate_edge_encoding(edge_data: _EdgeData, mark_name: String) raises:
    """`Plot.encode_chord()`'s length check, its non-negative rule, and its
    empty-data check (`_require_non_empty`), shared by `Mark.CHORD`/
    `ARC_DIAGRAM`/`GRAPH`/`SANKEY`.
    """
    if len(edge_data.from_categories) != len(edge_data.to_categories) or len(
        edge_data.values
    ) != len(edge_data.from_categories):
        raise Error(
            "Plot.encode_chord(): from_categories, to_categories, and"
            " values must all have the same length (got "
            + String(len(edge_data.from_categories))
            + " from_categories, "
            + String(len(edge_data.to_categories))
            + " to_categories, "
            + String(len(edge_data.values))
            + " values)"
        )
    _require_non_empty(
        len(edge_data.from_categories),
        "Plot.encode_chord() (" + mark_name + ")",
    )
    _require_non_negative(edge_data.values, mark_name)


def _encode_chord(
    mut plot: Plot,
    from_categories: List[String],
    to_categories: List[String],
    values: List[Float64],
) raises:
    """`Plot.encode_chord()`'s body, which forwards here with
    every argument; see that method for the contract."""
    var _ok_encode_chord = List[Mark]()
    _ok_encode_chord.append(Mark.CHORD)
    _ok_encode_chord.append(Mark.ARC_DIAGRAM)
    _ok_encode_chord.append(Mark.GRAPH)
    _ok_encode_chord.append(Mark.SANKEY)
    _require_mark(plot._mark, "encode_chord", "mark_chord()", _ok_encode_chord^)
    plot._categorical.x = List[String]()
    plot._continuous.x = List[Float64]()
    plot._continuous.y = List[Float64]()
    plot._edges.from_categories = from_categories.copy()
    plot._edges.to_categories = to_categories.copy()
    plot._edges.values = values.copy()
