"""Where a graph mark places its nodes, a setting `Plot.mark_graph()`
takes and `_MarkStyle` stores."""


struct GraphLayout(Copyable, ImplicitlyCopyable, Movable):
    """Where `Mark.GRAPH` puts its nodes (#157).

    - `GraphLayout.CIRCLE` (the default): evenly spaced around a circle,
      in first-seen order. Every node is equally easy to find, and the
      picture does not depend on the edges.
    - `GraphLayout.FORCE`: a force-directed layout. Every pair of nodes
      repels and every edge pulls its two ends together, so connected
      nodes gather and clusters separate -- the shape of the network,
      rather than a fixed ring.
    """

    var _value: Int

    comptime CIRCLE = Self(0)
    comptime FORCE = Self(1)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
