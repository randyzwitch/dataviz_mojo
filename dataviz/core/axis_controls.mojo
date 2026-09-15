"""Explicit control over a continuous axis: where its ticks go, which
direction it runs, and whether one data unit is the same length on both
axes (#368).

Everything here is off by default and reaches `_draw_continuous_axis_frame`
as one `_AxisControls` keyword, so the fifteen mark renders that share
that frame and have no opinion about any of it keep passing nothing.
"""

from std.math import log10

from dataviz.core.scale import Ticks, _label_decimals
from dataviz.core.scale import LinearScale


struct _TickOverride(Copyable, Movable):
    """Explicit major tick positions for one axis, from
    `Plot.scale_x_ticks()`/`scale_y_ticks()`, with optional labels.

    `has` is `False` until one of those sets it, which is what keeps the
    computed ticks the default. `labels` is either empty, meaning format
    the values the way computed ticks are formatted, or one string per
    value.
    """

    var has: Bool
    var values: List[Float64]
    var labels: List[String]

    def __init__(out self):
        """No override: the axis chooses its own ticks."""
        self.has = False
        self.values = List[Float64]()
        self.labels = List[String]()

    def __init__(out self, var values: List[Float64], var labels: List[String]):
        """Pin the ticks to `values`, labeled by `labels` when non-empty.

        Args:
            values: Tick positions in the axis's own units.
            labels: One label per value, or empty to format the values.
        """
        self.has = True
        self.values = values^
        self.labels = labels^


struct _AxisControls(Copyable, Movable):
    """The continuous-axis settings a `Plot` carries into its frame.

    Default-constructed means "nothing asked for", which is every caller
    that does not set one of `Plot`'s axis-control methods.
    """

    var x_ticks: _TickOverride
    var y_ticks: _TickOverride
    var x_reversed: Bool
    var y_reversed: Bool
    var equal_aspect: Bool

    def __init__(out self):
        """Today's behavior: computed ticks, both axes ascending, aspect
        free.
        """
        self.x_ticks = _TickOverride()
        self.y_ticks = _TickOverride()
        self.x_reversed = False
        self.y_reversed = False
        self.equal_aspect = False


def _in_domain(scale: LinearScale, value: Float64) -> Bool:
    """Whether `value` lands within `scale`'s domain, in the units the
    caller writes ticks in.

    A log scale's domain is in log10 space while its callers pass real
    units, the same split `LinearScale.to_pixel()` makes, so the
    comparison converts rather than the domain.

    Args:
        scale: The axis scale.
        value: A position in the caller's units.

    Returns:
        `True` when the value is inside the domain, ends included.
    """
    var v = value
    if scale.is_log:
        if value <= 0.0:
            return False
        v = log10(value)
    var lo = scale.domain_min
    var hi = scale.domain_max
    return v >= lo and v <= hi


def _override_ticks(
    override: _TickOverride, scale: LinearScale
) raises -> Ticks:
    """The caller's explicit ticks as a `Ticks`, dropped to those inside
    `scale`'s domain.

    Dropping rather than drawing them: a tick outside the domain has a
    pixel position outside the plot rect, so its label would print in the
    margin next to nothing. The caller asked where ticks go, not how far
    the axis reaches; `scale_x_domain()` is what moves the domain.

    With no labels given, every value is formatted at one decimal count,
    the widest any of them needs, so the column of labels reads as one
    set the way computed ticks do.

    Args:
        override: The caller's positions and labels.
        scale: The axis scale, for its domain.

    Returns:
        The ticks to draw, in the given order.

    Raises:
        Error: Never; the signature is `raises` because `Ticks` is.
    """
    var values = List[Float64]()
    var labels = List[String]()
    var has_labels = len(override.labels) > 0
    var decimals = 0
    for i in range(len(override.values)):
        var v = override.values[i]
        if not _in_domain(scale, v):
            continue
        values.append(v)
        if has_labels:
            labels.append(override.labels[i])
        else:
            var d = _label_decimals(v)
            if d > decimals:
                decimals = d
    return Ticks(values^, decimals, labels^)
