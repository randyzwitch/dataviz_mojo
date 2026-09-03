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


from dataviz.plot import Plot, _categorical_indices, _require_non_negative


struct _EdgeData(Movable):
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
        out self, var nodes: List[String], var from_idx: List[Int], var to_idx: List[Int]
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
    # Copied, not moved: moving `domain` out of `idx` while `idx.indices` is
    # still being read is a partial move the compiler rejects. The copy
    # covers only the distinct node names.
    return _EdgeNodeIndex(idx.domain.copy(), from_idx^, to_idx^)


def _validate_edge_encoding(plot: Plot, mark_name: String) raises:
    """`Plot.encode_chord()`'s length check plus its non-negative rule,
    shared by `Mark.CHORD`/`ARC_DIAGRAM`/`GRAPH`/`SANKEY`.
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
