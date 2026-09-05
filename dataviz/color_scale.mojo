"""ColorScale maps a continuous data domain onto a color gradient, for
data-driven color encoding (`Plot.encode(color=...)`). Stop
interpolation is shared with `canvas.gradient`'s `LinearGradient`/
`RadialGradient` through its `GradientStops`, which became public in
canvas_mojo v0.18.0 (the same code was reached through `_color_at_t`/
`_GradientStop`/`_insert_stop` before). Only the projection differs:
those project a pixel position onto [0, 1]; this projects a data
value, the way `LinearScale` does for position.
"""

from canvas.color import Color
from canvas.gradient import GradientStops
from dataviz.theme import Theme


struct ColorScale(Movable):
    """A linear color gradient over [domain_min, domain_max]. There is no
    pixel range as in LinearScale; `color_at(value)` is the whole
    interface. A zero-span domain projects every value to t=0.0, the
    lowest-offset stop's color.
    """

    var domain_min: Float64
    """The low end of the data domain this scale's colors span."""
    var domain_max: Float64
    """The high end of the data domain this scale's colors span."""
    var stops: GradientStops
    """The gradient's own color stops, added via `add_stop()`. A
    `GradientStops` keeps itself sorted by offset so `color_at` can
    binary-search for the bracketing pair."""

    def __init__(out self, domain_min: Float64, domain_max: Float64):
        """Construct an empty `ColorScale` over `[domain_min, domain_max]`. Add
        stops via `add_stop()`, or use `from_theme()` for one pre-filled with
        `Theme`'s stops.

        Args:
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.
        """
        self.domain_min = domain_min
        self.domain_max = domain_max
        self.stops = GradientStops()

    def add_stop(mut self, offset: Float64, color: Color):
        """Add one color stop to the gradient.

        Args:
            offset: The stop's position in `[0.0, 1.0]` along the
                gradient. Stops need not be added in offset order; each is
                inserted into place.
            color: The color at that offset.
        """
        self.stops.add_stop(offset, color)

    def color_at(self, value: Float64) -> Color:
        """Project `value` onto `[domain_min, domain_max]`, then interpolate
        between the two nearest stops (see the struct docstring for the
        zero-span case).

        Args:
            value: The data value to look up a color for.

        Returns:
            The interpolated color at `value`.
        """
        var span = self.domain_max - self.domain_min
        var t = 0.0
        if span != 0.0:
            t = (value - self.domain_min) / span
        return self.stops.color_at(t)

    @staticmethod
    def from_theme(
        theme: Theme, domain_min: Float64, domain_max: Float64
    ) -> Self:
        """How every continuous color-encoded mark (`Plot.encode(color=...)`,
        `Mark.HEATMAP`/`CORRPLOT`/`CALENDAR_HEATMAP`) builds its `ColorScale`
        from `theme`'s three stops: `low` at `0.0`, `mid` at `0.5`, `high` at
        `1.0`. See `Theme.color_scale_mid` for why the middle stop exists. A
        `@staticmethod` so `ColorScale(domain_min, domain_max)` with no stops
        stays a valid starting point.

        Args:
            theme: Supplies the three color-scale stops
                (`color_scale_low`/`mid`/`high`).
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.

        Returns:
            A `ColorScale` pre-filled with `theme`'s three stops.
        """
        var scale = Self(domain_min, domain_max)
        scale.add_stop(0.0, theme.color_scale_low)
        scale.add_stop(0.5, theme.color_scale_mid)
        scale.add_stop(1.0, theme.color_scale_high)
        return scale^


def default_categorical_palette() -> List[Color]:
    """A default qualitative color palette for categorical color encoding: 8
    visually distinct colors (the common "tab10"-style set), cycled via
    modulo when a column has more unique categories (see `Plot.encode`).

    A plain function rather than a `Theme` field: a `List` field would
    break `Theme`'s `ImplicitlyCopyable` conformance, which the
    `var theme = plot._theme` copies throughout the package depend on.

    Returns:
        8 visually distinct colors, cycled via modulo for more
        categories than that.
    """
    return [
        Color(31, 119, 180),
        Color(255, 127, 14),
        Color(44, 160, 44),
        Color(214, 39, 40),
        Color(148, 103, 189),
        Color(140, 86, 75),
        Color(227, 119, 194),
        Color(127, 127, 127),
    ]
