"""`Theme.x_label_rotation`: whether/how far a categorical x-axis's tick
labels rotate when they would otherwise overlap. Same small-struct-
with-comptime-constants-and-`__eq__` pattern as `Mark`/`OutputFormat`.
"""


struct XAxisLabelRotation(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime AUTO = Self(0)
    """Rotate only if the widest label would overlap its neighbor: 0
    degrees if every label fits within its category's band width
    (`OrdinalScale.step()`), 45 if that alone clears it, 90 otherwise.
    The default."""
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
