"""Step (stairs) interpolation for `Mark.LINE`."""


struct StepStyle(Copyable, ImplicitlyCopyable, Movable):
    """Where the vertical riser sits between two consecutive samples of a
    `Mark.LINE` plot, set via `Plot.mark_line(step=...)` or
    `line(step=...)`.

    A straight segment between two samples says the value moved
    gradually from one to the other. Plenty of series never do that: a
    price that ticks, a count that increments, a state machine, a
    survival curve, a histogram outline. Drawing those with straight
    interpolation asserts intermediate values that were never measured,
    which is a statement about the data rather than a style choice --
    hence a mark-level setting rather than something on `Theme`, which
    holds what a theme is allowed to restyle.

    The three non-`NONE` styles draw exactly the same plateaus and the
    same risers; they differ only in *which* x a riser is drawn at,
    which is the one thing the data itself cannot tell you. That
    ambiguity is why they are named rather than left to a `Bool`:
    "held since the last reading" (`POST`), "held until this reading"
    (`PRE`) and "changed somewhere in between" (`MID`) are three
    different claims about when the value changed, and only the caller
    knows which one is true.

    Same names and meanings as matplotlib's
    `drawstyle='steps-pre'/'steps-mid'/'steps-post'`, so a reader
    porting a plot does not have to re-derive which is which.

    Mutually exclusive with `Theme.line_smoothing`: a smoothed staircase
    rounds off the corners that carry the whole meaning, and the risers
    -- two points at the same x -- would pick up horizontal Catmull-Rom
    tangents and bow sideways. Asking for both raises at render time
    (`_check_step_smoothing`, validate.mojo) rather than silently
    winning one way or the other.
    """

    var _value: Int

    comptime NONE = Self(0)
    """Straight interpolation between consecutive samples -- the
    default, and what every line drew before this setting existed."""
    comptime PRE = Self(1)
    """The riser sits at the earlier sample's x: the interval
    `(x[i - 1], x[i]]` is drawn at `y[i]`. Read as "the value had
    already reached `y[i]` by the time `x[i]` was reached" -- the right
    choice when a reading reports what happened over the interval
    leading up to it."""
    comptime MID = Self(2)
    """The riser sits halfway between the two samples. Read as "the
    value changed somewhere between these two readings, and we do not
    know where" -- the honest choice for regular sampling with no reason
    to attribute the change to either endpoint, and the one that keeps
    the drawn plateau centered on its own sample."""
    comptime POST = Self(3)
    """The riser sits at the later sample's x: the interval
    `[x[i], x[i + 1])` is drawn at `y[i]`. Read as "the value held at
    `y[i]` from `x[i]` until it changed" -- the usual choice for a
    price, a counter, or any quantity that stays put between events."""

    def __init__(out self, value: Int):
        """Prefer the `NONE`/`PRE`/`MID`/`POST` comptime constants over
        constructing one directly.

        Args:
            value: 0 for NONE, 1 for PRE, 2 for MID, 3 for POST.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        return self._value != other._value

    def name(self) -> String:
        """This style's constant name, for error messages that have to
        say which one was asked for.

        Returns:
            "NONE", "PRE", "MID", "POST", or "StepStyle(<n>)" for a
            value outside the four constants.
        """
        if self._value == 0:
            return "NONE"
        if self._value == 1:
            return "PRE"
        if self._value == 2:
            return "MID"
        if self._value == 3:
            return "POST"
        return "StepStyle(" + String(self._value) + ")"
