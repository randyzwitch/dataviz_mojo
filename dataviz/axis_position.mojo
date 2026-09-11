"""Where an axis line (matplotlib's spine) sits."""


struct AxisPosition(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime EDGE = Self(0)
    """At the edge of the plot rect: the bottom for the x-axis, the left
    for the y-axis. The default, and what every chart did before."""
    comptime ZERO = Self(1)
    """At zero on the axis it is positioned along, so the line crosses
    the data instead of bounding it -- matplotlib's
    `spine.set_position("zero")`.

    Falls back to `EDGE`, rather than drawing a line outside the plot
    rect, unless that axis is continuous and its domain spans zero. So a
    categorical or polar chart ignores this, and so does a scatter whose
    values are all positive.
    """

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
