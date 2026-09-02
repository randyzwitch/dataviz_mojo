"""ColorScale -- maps a continuous data domain onto a color gradient,
for data-driven color encoding (`Plot.encode(color=...)`). Shares its
stop-interpolation logic with `canvas.gradient`'s `LinearGradient`/
`RadialGradient` via that module's `_color_at_t`/`_GradientStop`
-- identical math (bracket the two nearest stops, linearly
interpolate), only the projection differs: those two project a pixel
position (an axis, or a radial distance) onto [0, 1]; this one
projects a *data value* onto [0, 1] via a plain domain, the same
domain-to-[0,1] idea `LinearScale` uses for position, generalized to
color instead of a pixel coordinate.
"""

from canvas.color import Color
from canvas.gradient import _GradientStop, _color_at_t
from dataviz.theme import Theme


struct ColorScale(Movable):
    """A linear color gradient over [domain_min, domain_max] -- no
    "pixel range" the way LinearScale has, since a color has no
    spatial position to map onto; `color_at(value)` is the whole
    interface. A zero-span domain (every value identical) always
    projects to t=0.0 -- the lowest-offset stop's color (not
    necessarily whichever was added first; see `_color_at_t`'s
    bracketing-by-offset-value search), not a crash -- the same
    degenerate-domain handling `LinearScale.scale()` gives.
    """

    var domain_min: Float64
    """The low end of the data domain this scale's colors span."""
    var domain_max: Float64
    """The high end of the data domain this scale's colors span."""
    var stops: List[_GradientStop]
    """The gradient's own color stops, added via `add_stop()`."""
    # The smallest-/largest-offset stop so far -- tracked incrementally
    # here instead of scanned from `stops` by _color_at_t on every
    # call, matching LinearGradient/RadialGradient's pattern (see
    # canvas.gradient's docstring for why _color_at_t takes
    # these pre-found rather than scanning itself).
    var _lowest: _GradientStop
    var _highest: _GradientStop

    def __init__(out self, domain_min: Float64, domain_max: Float64):
        """Construct an empty `ColorScale` over `[domain_min,
        domain_max]` -- a real, valid starting point with no stops
        yet; add them via `add_stop()`, or build one pre-filled with
        `Theme`'s own stops via `from_theme()`.

        Args:
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.
        """
        self.domain_min = domain_min
        self.domain_max = domain_max
        self.stops = List[_GradientStop]()
        # Overwritten by the first real add_stop() call; _color_at_t
        # never reads these unless len(stops) >= 2, so this placeholder
        # (transparent black at offset 0.0) is never actually observed.
        self._lowest = _GradientStop(0.0, Color(0, 0, 0, 0))
        self._highest = self._lowest

    def add_stop(mut self, offset: Float64, color: Color):
        """Add one color stop to the gradient.

        Args:
            offset: The stop's position in `[0.0, 1.0]` along the
                gradient.
            color: The color at that offset.
        """
        var stop = _GradientStop(offset, color)
        if len(self.stops) == 0 or offset < self._lowest.offset:
            self._lowest = stop
        if len(self.stops) == 0 or offset > self._highest.offset:
            self._highest = stop
        self.stops.append(stop)

    def color_at(self, value: Float64) -> Color:
        """Project `value` onto this scale's `[domain_min,
        domain_max]` domain, then interpolate its color between the
        two nearest stops (see this struct's own docstring for the
        zero-span-domain case).

        Args:
            value: The data value to look up a color for.

        Returns:
            The interpolated color at `value`.
        """
        var span = self.domain_max - self.domain_min
        var t = 0.0
        if span != 0.0:
            t = (value - self.domain_min) / span
        return _color_at_t(self.stops, self._lowest, self._highest, t)

    @staticmethod
    def from_theme(theme: Theme, domain_min: Float64, domain_max: Float64) -> Self:
        """The one, shared way every continuous color-encoded mark in
        this package (`Plot.encode(color=...)`'s point channel,
        `Mark.HEATMAP`/`CORRPLOT`/`CALENDAR_HEATMAP`) builds its
        `ColorScale` from `theme`'s three color-scale stops -- `low` at
        offset `0.0`, `mid` at `0.5`, `high` at `1.0`, not just `low`/
        `high` alone -- see `Theme.color_scale_mid`'s docstring for the
        real, rendering-caught readability bug a missing middle stop
        causes.

        A plain `@staticmethod`, not a change to `__init__` itself --
        `ColorScale(domain_min, domain_max)` alone (no stops) stays a
        real, valid, if empty, starting point (`tests/test_color_scale.
        mojo`'s hand-built black/white and blue/red scales, for
        instance, have nothing to do with any `Theme` at all and
        shouldn't need one just to construct a `ColorScale`).

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
    """A default qualitative (discrete, unordered) color palette for
    categorical color encoding -- 8 colors chosen to read as visually
    distinct from each other (the same well-known "tab10"-style set
    most charting libraries ship a version of), cycled via modulo if a
    column has more unique categories than this (see
    `Plot.encode`'s docstring).

    Deliberately a plain function, not a `Theme` field: adding a
    `List` field to `Theme` would break its `ImplicitlyCopyable`
    conformance -- Mojo can't synthesize an implicit copy constructor
    once a struct holds a `List` -- which every existing `var theme =
    plot._theme`-style copy throughout
    this package already depends on. The same reasoning keeps named
    palettes out of `canvas.Color` itself: a fixed default is
    enough until per-Theme palette customization is an actual,
    concrete need, not a reason to change how `Theme` itself copies
    today.

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
