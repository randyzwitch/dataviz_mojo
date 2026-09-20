"""What a chart does with a missing observation (#367)."""


struct Missing(Copyable, ImplicitlyCopyable, Movable):
    """How a plot treats a missing value, which every column carries as
    `NaN` once it is inside a `Plot`.

    A dataframe column's validity bitmap becomes `NaN` when it is read
    (frame_input.mojo), and a caller passing lists writes `NaN` for the
    same meaning, so one marker reaches every mark, scale and statistic.
    The cost of that choice is stated plainly: a computed `NaN` -- 0/0
    in a caller's own arithmetic -- is indistinguishable from an absent
    measurement, and reads as missing.

    `DRAW`, the default, treats the two kinds of column differently,
    because they are different questions.

    A **value** column holds a number, and a number that was never
    measured has nowhere to sit on an axis: the observation drops out.
    A line breaks rather than bridging the hole, a point is not drawn, a
    matrix cell stays empty, and a statistic is computed from what is
    there. The one thing no mark does is join the two sides of a gap,
    which would claim a measurement that was never made.

    A **category** column is not a measurement but a label, and "not
    recorded" is a label a reader often wants to see: those rows become
    their own category, named by `Theme.missing_category_label`
    ("(missing)" by default), keeping their values in the chart rather
    than dropping observations that are perfectly good apart from a
    blank field. Set the policy to `RAISE` to refuse them instead.

    `RAISE` keeps the old strictness: any `NaN` in a numeric channel is
    refused at encode time, naming the column and index. Infinity is
    refused under both, always: it is not a missing value, it is a
    number no axis can place.
    """

    var _value: Int

    comptime DRAW = Self(0)
    """Draw what is there and leave the gaps visible. The default."""
    comptime RAISE = Self(1)
    """Refuse any missing value, as this package did before #367."""

    def __init__(out self, value: Int):
        """Prefer the `DRAW`/`RAISE` comptime constants over constructing
        one directly.

        Args:
            value: 0 for DRAW, 1 for RAISE.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        return self._value != other._value
