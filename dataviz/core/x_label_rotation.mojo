"""Categorical x-axis label rotation modes."""


struct XAxisLabelRotation(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime AUTO = Self(0)
    """Choose 0, 45, or 90 degrees to avoid overlap."""
    comptime DEG_0 = Self(1)
    """Always draw labels horizontally, even if they overlap."""
    comptime DEG_45 = Self(2)
    """Always rotate labels 45 degrees."""
    comptime DEG_90 = Self(3)
    """Always rotate labels 90 degrees (fully vertical)."""

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
