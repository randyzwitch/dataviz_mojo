"""Where a legend sits relative to the plot area (#211)."""


struct LegendPosition(Copyable, ImplicitlyCopyable, Movable):
    """Which edge of the plot area a legend is reserved on and drawn
    against, set via `Theme.legend_position`.

    `RIGHT` and `LEFT` stack entries in a column and take width from the
    plot; `TOP` and `BOTTOM` lay them out in rows and take height. The
    horizontal forms wrap onto further rows when a row would run past
    the plot's width, so a chart with many series grows downward rather
    than off the edge.

    Which to use is a shape question: a column costs width, which a
    narrow chart or one with many series can't spare, while a row costs
    height, which is the usual convention on a wide chart.
    """

    var _value: Int

    comptime RIGHT = Self(0)
    """A column to the right of the plot. The default, and what every
    legend did before this setting existed."""
    comptime LEFT = Self(1)
    """A column to the left of the plot -- `RIGHT` mirrored, with the
    plot's left edge moving in instead of its right."""
    comptime TOP = Self(2)
    """A row above the plot, below the title, wrapping onto further rows
    as needed."""
    comptime BOTTOM = Self(3)
    """A row below the plot, under the x-axis labels, wrapping onto
    further rows as needed."""

    def __init__(out self, value: Int):
        """Prefer the `RIGHT`/`LEFT`/`TOP`/`BOTTOM` comptime constants over
        constructing one directly.

        Args:
            value: 0 for RIGHT, 1 for LEFT, 2 for TOP, 3 for BOTTOM.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def is_horizontal(self) -> Bool:
        """Whether entries lay out in rows rather than a column.

        Returns:
            True for `TOP`/`BOTTOM`, False for `RIGHT`/`LEFT`.
        """
        return self._value == 2 or self._value == 3
