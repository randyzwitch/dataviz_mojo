"""Dashed, dotted and dash-dot strokes (#331)."""


struct LineStyle(Copyable, ImplicitlyCopyable, Movable):
    """How a stroke is broken up along its length, set via
    `Theme.gridline_style`/`Theme.annotation_line_style` or
    `Plot.mark_line(style=...)`.

    A dash pattern is not decoration. A reference line and a fitted
    trend are not data, and dashing them is the conventional way of
    saying so -- a solid `annotate_hline` reads as another series. It
    also distinguishes series without relying on hue, which matters for
    print and for readers who cannot separate the palette's colours.

    The patterns are in multiples of the stroke's own scale rather than
    absolute pixels, so a dash looks the same at any `Theme.scale`; see
    `dashes()`.
    """

    var _value: Int

    comptime SOLID = Self(0)
    """An unbroken stroke. The default, and what every line drew before
    this setting existed."""
    comptime DASHED = Self(1)
    """Long dashes with gaps a little shorter -- the usual "this is a
    threshold, not a measurement" line."""
    comptime DOTTED = Self(2)
    """Round-ish dots at a tight spacing, for a line that should stay
    legible without competing with the data. The usual choice for
    gridlines."""
    comptime DASH_DOT = Self(3)
    """Alternating long dash and dot, for when a chart already uses both
    `DASHED` and `DOTTED` and needs a third."""

    def __init__(out self, value: Int):
        """Prefer the `SOLID`/`DASHED`/`DOTTED`/`DASH_DOT` comptime
        constants over constructing one directly.

        Args:
            value: 0 for SOLID, 1 for DASHED, 2 for DOTTED, 3 for
                DASH_DOT.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        return self._value != other._value

    def dashes(self, scale: Float64) -> List[Float64]:
        """The on/off lengths canvas's `dashes=` wants, in pixels.

        Multiplied by `scale` -- pass `_Scaled.scale`, the same factor
        every other piece of furniture is sized by -- so a dash keeps
        its proportions when `Theme.scale` changes. A pattern in fixed
        pixels would turn into a nearly solid line on a dense chart and
        a row of specks on a sparse one.

        `SOLID` returns an empty list, which is what canvas reads as
        "no dashing", so a caller can pass the result unconditionally.

        Args:
            scale: The theme's scale factor.

        Returns:
            On/off lengths, empty for `SOLID`.
        """
        if self._value == 1:
            return [6.0 * scale, 4.0 * scale]
        if self._value == 2:
            return [1.5 * scale, 3.0 * scale]
        if self._value == 3:
            return [6.0 * scale, 3.0 * scale, 1.5 * scale, 3.0 * scale]
        return List[Float64]()
