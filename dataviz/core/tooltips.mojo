"""When a chart's data gets SVG hover tooltips."""

comptime AUTO_TOOLTIP_LIMIT = 1000
"""The default for `Theme.auto_tooltip_limit`: the most tooltips
`Tooltips.AUTO` draws on one plot. Above it, AUTO draws none.

Each tooltip is an SVG `<title>` wrapped in a `<g>`, measured at about
37 bytes per datum on a scatter, roughly 60% on top of the point
itself. 1,000 tooltips adds about 37 KB. A chart with more points than
that is also one where points overlap enough that hovering a single one
tells a reader little."""


struct Tooltips(Copyable, ImplicitlyCopyable, Movable):
    """Whether each datum gets an SVG `<title>`, which a browser shows as
    a hover tooltip. Set for every chart through `Theme.tooltips`, and
    for one chart through `Plot.tooltips()`, which takes precedence.

    `ON` and `OFF` mean the same thing on every mark. `AUTO`, the
    default, is `ON` for a plot that would draw at most
    `Theme.auto_tooltip_limit` tooltips (`AUTO_TOOLTIP_LIMIT`, 1,000,
    by default) and `OFF` above that, so a dense
    scatter does not carry thousands of titles nobody can hover
    individually. The count is per plot, so each layer of
    `render_layers()` and each panel of a facet grid decides on its own.

    Which marks draw tooltips is `Mark.supports(Feature.TOOLTIPS)`
    (mark.mojo). `ON` on any other mark raises when the chart renders,
    as `Theme.show_data_labels` does (#676); `OFF` and `AUTO` never
    raise. The raster and PDF backends draw no tooltips whatever the
    setting.
    """

    var _value: Int

    comptime AUTO = Self(0)
    """Tooltips on a plot that would draw at most
    `Theme.auto_tooltip_limit` of them, none above that. The default."""
    comptime ON = Self(1)
    """A tooltip on every datum, however many there are."""
    comptime OFF = Self(2)
    """No tooltips."""

    def __init__(out self, value: Int):
        """Prefer the `AUTO`/`ON`/`OFF` comptime constants over
        constructing one directly.

        Args:
            value: 0 for AUTO, 1 for ON, 2 for OFF.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        return self._value != other._value

    def draws(self, count: Int, limit: Int) -> Bool:
        """Whether a plot that would draw `count` tooltips draws them.

        Args:
            count: How many tooltips this plot would draw.
            limit: `AUTO`'s limit, `Theme.auto_tooltip_limit`.

        Returns:
            True for `ON`; False for `OFF`; for `AUTO`, whether `count`
            is at most `limit`.
        """
        if self == Self.ON:
            return True
        if self == Self.OFF:
            return False
        return count <= limit
