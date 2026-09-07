"""Where a stack of series sits on the y-axis (#337)."""


struct StackBaseline(Copyable, ImplicitlyCopyable, Movable):
    """Which baseline `Mark.STREAMGRAPH` stacks its series from, set via
    `Plot.mark_streamgraph(baseline=...)`.

    The stacking itself is the same either way -- each series is laid on
    the running total of the ones below it. Only where that total starts
    differs, and the two answers are two different charts.
    """

    var _value: Int

    comptime WIGGLE = Self(0)
    """Each category's stack is centered on zero, starting at
    `-total / 2`, so the silhouette is symmetric about the middle. The
    streamgraph proper, and the default -- what this mark drew before
    this setting existed.

    Reading a value off it means comparing two wavy edges, which is why
    it is an editorial form: it shows *composition* changing over time
    when the totals themselves are not the point."""
    comptime ZERO = Self(1)
    """Every category's stack starts at a flat zero, giving the ordinary
    stacked area chart (matplotlib's `stackplot`, and what
    `stacked_area()` selects).

    The bottom series then sits on a straight axis and can actually be
    read against it, and the top edge is the running total. That is the
    one to reach for when the totals matter -- which is most of the
    time."""

    def __init__(out self, value: Int):
        """Prefer the `WIGGLE`/`ZERO` comptime constants over
        constructing one directly.

        Args:
            value: 0 for WIGGLE, 1 for ZERO.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        """Whether both name the same baseline.

        Args:
            other: The baseline to compare against.

        Returns:
            True when they match.
        """
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        """Whether the two name different baselines.

        Args:
            other: The baseline to compare against.

        Returns:
            True when they differ.
        """
        return self._value != other._value
