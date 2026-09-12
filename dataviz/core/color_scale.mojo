"""ColorScale maps a continuous data domain onto a color gradient, for
data-driven color encoding (`Plot.encode(color=...)`). Stop
interpolation is shared with `canvas.gradient`'s `LinearGradient`/
`RadialGradient` through its `GradientStops`, which became public in
canvas_mojo v0.18.0 (the same code was reached through `_color_at_t`/
`_GradientStop`/`_insert_stop` before). Only the projection differs:
those project a pixel position onto the unit interval; this projects a data
value, the way `LinearScale` does for position.

Normalization -- *which* data values the ramp spans, and where its
middle color lands -- is kept separate from that interpolation.
`_ColorDomainOverride` carries the caller's answer from
`Plot.scale_color_domain()`/`Plot.scale_color_center()` down to the
marks, `_color_scale_for()` is the one place every mark turns it into a
`ColorScale`, and `shared_color_domain()` computes one domain over
several charts' data so they can be compared (the color counterpart to
`shared_bin_edges()`).
"""

from canvas.color import Color
from canvas.gradient import GradientStops
from dataviz.core.scale import MinMax, _min_max
from dataviz.core.theme import Theme


struct ColorScale(Movable):
    """A linear color gradient from `domain_min` to `domain_max`. There is no
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
    var has_center: Bool
    """Whether this scale was built by `from_theme_centered()`. Recorded
    only so a legend can label the center; `color_at()` never reads it,
    because centering is already baked into `stops`."""
    var center: Float64
    """The value the ramp's middle color sits on when `has_center`;
    meaningless otherwise. See `from_theme_centered()`."""

    def __init__(out self, domain_min: Float64, domain_max: Float64):
        """Construct an empty `ColorScale` from `domain_min` to `domain_max`. Add
        stops via `add_stop()`, or use `from_theme()` for one pre-filled with
        `Theme`'s stops.

        Args:
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.
        """
        self.domain_min = domain_min
        self.domain_max = domain_max
        self.stops = GradientStops()
        self.has_center = False
        self.center = 0.0

    def add_stop(mut self, offset: Float64, color: Color):
        """Add one color stop to the gradient.

        Args:
            offset: The stop's position from 0.0 to 1.0 along the
                gradient. Stops need not be added in offset order; each is
                inserted into place.
            color: The color at that offset.
        """
        self.stops.add_stop(offset, color)

    def color_at(self, value: Float64) -> Color:
        """Project `value` onto the domain, then interpolate
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
        from `theme`'s stops: `low` at `0.0`, `mid` at `0.5`, `high` at
        `1.0`. See `Theme.color_scale_mid` for why the middle stop exists. A
        `@staticmethod` so `ColorScale(domain_min, domain_max)` with no stops
        stays a valid starting point.

        A non-empty `Theme.color_ramp` replaces all three, spread evenly
        over the unit interval -- that is how a perceptually uniform map like
        `colormaps.viridis()` reaches a mark. Three stops cannot
        express one; see the field's own docstring. A single-entry ramp
        is a flat color, which is degenerate but well defined, so it is
        not rejected.

        Args:
            theme: Supplies the stops -- `color_ramp` when it is
                non-empty, otherwise `color_scale_low`/`mid`/`high`.
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.

        Returns:
            A `ColorScale` pre-filled with `theme`'s stops.
        """
        var scale = Self(domain_min, domain_max)
        var n = len(theme.color_ramp)
        if n == 0:
            scale.add_stop(0.0, theme.color_scale_low)
            scale.add_stop(0.5, theme.color_scale_mid)
            scale.add_stop(1.0, theme.color_scale_high)
            return scale^
        if n == 1:
            scale.add_stop(0.0, theme.color_ramp[0])
            return scale^
        for i in range(n):
            scale.add_stop(Float64(i) / Float64(n - 1), theme.color_ramp[i])
        return scale^

    @staticmethod
    def from_theme_centered(
        theme: Theme,
        domain_min: Float64,
        domain_max: Float64,
        center: Float64,
    ) -> Self:
        """`from_theme()`, but with the ramp's middle color pinned to
        `center` instead of to the numeric midpoint of the domain. For a
        diverging ramp whose meaning lives at one value -- usually zero,
        sometimes a baseline or a target -- over data that is not
        symmetric about it. `Plot.scale_color_center()` is how a chart
        reaches this.

        The domain is left exactly as given: only the *stops* move. A
        stop at offset `u` is re-placed at `_center_offset(u, t)`, where
        `t` is where `center` falls in `[domain_min, domain_max]`. That
        sends `0.0` to `0.0`, `0.5` to `t`, and `1.0` to `1.0`, so the
        two arms of the ramp cover unequal fractions of the bar while
        both ends still mean what they did before.

        Moving the stops rather than bending `color_at()`'s projection is
        the whole point. Three things then follow for free instead of
        needing their own code: `color_at()` stays a single linear
        projection, `stops` stays the honest description of the gradient,
        and `_draw_continuous_color_legend` -- which builds its bar
        straight out of `stops` -- draws the asymmetric ramp the mark
        actually used without knowing centering exists. A special case
        inside `color_at()` would have left the legend showing a
        symmetric bar for an asymmetric mapping, which is the exact class
        of silent disagreement this API was added to remove.

        The result is matplotlib's `TwoSlopeNorm` by another route, and
        agrees with it value for value: each arm of the remap is linear,
        stop interpolation is linear, so compressing the ramp's offsets
        into an arm and compressing the values into it give the same
        color. Only `t` has to be computed here; `TwoSlopeNorm`
        normalizes every value twice.

        Centering is defined for any ramp, not only a three-stop
        diverging one -- it means "the color at offset 0.5 lands on
        `center`" whatever the stops are. It is rarely what you want for
        a sequential ramp like `colormaps.viridis()`, but `Theme` does
        not record whether a ramp diverges, so guessing and rejecting
        would be a worse answer than a documented one.

        Args:
            theme: Supplies the stops, exactly as `from_theme()` reads
                them.
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.
            center: The value the ramp's middle color sits on. Must be
                strictly inside the domain; `_color_scale_for()` is
                where that is checked, since it is the one place that
                knows the resolved domain.

        Returns:
            A `ColorScale` over the same domain whose stops are
            re-placed around `center`.
        """
        var base = Self.from_theme(theme, domain_min, domain_max)
        var span = domain_max - domain_min
        # A zero-span domain already sends every value to t=0.0, so there
        # is no arm to compress and nothing centering can say.
        if span == 0.0:
            return base^
        var t = (center - domain_min) / span
        var scale = Self(domain_min, domain_max)
        scale.has_center = True
        scale.center = center
        for stop in base.stops:
            scale.add_stop(_center_offset(stop.offset, t), stop.color)
        return scale^


def _center_offset(offset: Float64, t: Float64) -> Float64:
    """Where a stop at `offset` moves to when the ramp is centered on a
    value sitting at `t` in the domain: the piecewise-linear map that
    stretches `[0, 0.5]` onto `[0, t]` and `[0.5, 1]` onto `[t, 1]`.

    Its own function so `from_theme_centered()` and the tests can state
    the same three fixed points -- 0 stays 0, 0.5 becomes `t`, 1 stays 1
    -- rather than re-deriving them from a formula spelled out inline.

    Args:
        offset: A stop's original offset in `[0, 1]`.
        t: Where the center value falls in the domain, in `[0, 1]`.

    Returns:
        The re-placed offset.
    """
    if offset <= 0.5:
        return offset * 2.0 * t
    return t + (offset - 0.5) * 2.0 * (1.0 - t)


struct _ColorDomainOverride(Copyable, ImplicitlyCopyable, Movable):
    """An explicit color domain and/or ramp center, set via
    `Plot.scale_color_domain()`/`Plot.scale_color_center()`, overriding
    the `[min, max]` a continuous-color mark would otherwise take from
    its own data. `_DomainOverride` (plot.mojo) is the same idea for a
    spatial axis; this one is separate because a color domain has a
    third thing to say (`center`) and applies to a different, much
    larger set of marks. Stored on `Plot._color_domain`.

    `has` and `has_center` move independently: a center on its own
    re-places the ramp inside the data's own limits, and a domain on its
    own leaves the ramp symmetric. Both default to `False`, which is the
    behavior every mark had before this existed.
    """

    var has: Bool
    var min: Float64
    var max: Float64
    var has_center: Bool
    var center: Float64

    def __init__(out self):
        self.has = False
        self.min = 0.0
        self.max = 0.0
        self.has_center = False
        self.center = 0.0


def _color_scale_for(
    theme: Theme,
    domain: _ColorDomainOverride,
    data_min: Float64,
    data_max: Float64,
) raises -> ColorScale:
    """The one call every continuous-color mark makes instead of
    `ColorScale.from_theme(theme, <its own min>, <its own max>)`.

    Each mark still computes the limits its own data implies and passes
    them as `data_min`/`data_max`; this decides whether they win. They
    do unless `Plot.scale_color_domain()` said otherwise, which is what
    makes two charts comparable: without it, two facets of the same
    quantity get two different color scales and look identical while
    meaning different things.

    Routing every mark through one function is deliberate. The
    alternative -- each mark reading `plot._color_domain` and branching
    for itself -- is how the limits got out of step in the first place,
    and it would put the center check in fifteen places or, more likely,
    in none of them.

    Args:
        theme: Supplies the ramp's stops.
        domain: The chart's override, usually `Plot._color_domain`.
        data_min: The low limit this mark's own data implies.
        data_max: The high limit this mark's own data implies.

    Returns:
        The `ColorScale` the mark should color with, and hand to its
        legend.

    Raises:
        Error: The override's `min` is not below its `max`, or the
            center does not lie strictly inside the resolved domain.
    """
    var lo = domain.min if domain.has else data_min
    var hi = domain.max if domain.has else data_max
    if domain.has and lo >= hi:
        raise Error(
            "Plot.scale_color_domain(): min must be less than max (got min="
            + String(lo)
            + ", max="
            + String(hi)
            + ")"
        )
    if not domain.has_center:
        return ColorScale.from_theme(theme, lo, hi)
    if domain.center <= lo or domain.center >= hi:
        raise Error(
            "Plot.scale_color_center(): the center must lie strictly inside"
            " the color domain (got center="
            + String(domain.center)
            + " for a domain of ["
            + String(lo)
            + ", "
            + String(hi)
            + "]) -- widen it with Plot.scale_color_domain(min, max)"
        )
    return ColorScale.from_theme_centered(theme, lo, hi, domain.center)


def shared_color_domain(samples: List[List[Float64]]) raises -> MinMax:
    """One color domain covering every list in `samples`: the smallest
    value anywhere to the largest value anywhere. Hand it to each
    chart's `Plot.scale_color_domain()` and they become comparable.

    The color counterpart to `shared_bin_edges()`, and for the same
    reason. Two heatmaps drawn beside each other read as one picture,
    so a reader compares the shades across them -- but each chart
    colors against its own `[min, max]`, so the same shade is a
    different number in each, and nothing on either chart says so. The
    two charts have to be told the answer, because neither can see the
    other.

    Returning the domain rather than applying it keeps this usable for
    the cases that are not a facet grid: two standalone charts, a chart
    compared against last quarter's, or a domain rounded to something
    presentable before being set.

    Args:
        samples: One list of colored values per chart. Empty lists are
            allowed and contribute nothing, as long as at least one list
            has a value.

    Returns:
        The pooled minimum and maximum, for
        `Plot.scale_color_domain(d.min, d.max)`.

    Raises:
        Error: `samples` is empty or every list is, or any value is
            `NaN`/infinite (`_min_max()`'s own check).
    """
    var pooled = List[Float64]()
    for s in samples:
        for v in s:
            pooled.append(v)
    if len(pooled) == 0:
        raise Error(
            "shared_color_domain(): samples must contain at least one value"
            " across all charts"
        )
    return _min_max(pooled)


def shared_color_domain(grids: List[List[List[Float64]]]) raises -> MinMax:
    """`shared_color_domain()` over 2-D grids -- the `z` that
    `Plot.encode_imshow()`, `encode_pcolormesh()`, `encode_contour()`
    and friends take -- rather than flat lists.

    An overload rather than a differently named function, and rather
    than asking the caller to flatten: a grid mark's data is already
    shaped `List[List[Float64]]`, so flattening at the call site is
    boilerplate whose only failure mode is doing it wrong. The two
    overloads are unambiguous because the argument types differ, the
    same way `bin_edges()` overloads on a count versus a `BinRule`.

    Args:
        grids: One grid per chart. Empty grids and empty rows
            contribute nothing, as long as at least one value exists.

    Returns:
        The pooled minimum and maximum across every grid.

    Raises:
        Error: `grids` is empty or holds no values at all, or any value
            is `NaN`/infinite.
    """
    var pooled = List[Float64]()
    for g in grids:
        for row in g:
            for v in row:
                pooled.append(v)
    if len(pooled) == 0:
        raise Error(
            "shared_color_domain(): grids must contain at least one value"
            " across all charts"
        )
    return _min_max(pooled)


def categorical_palette_for(theme: Theme) -> List[Color]:
    """The palette a chart under `theme` cycles its categories through:
    `theme.categorical_palette` when set, else
    `default_categorical_palette()`. The one place the fallback is
    decided, so every mark file asks the same question the same way.

    Args:
        theme: The chart's theme.

    Returns:
        At least one color, cycled via modulo by the caller.
    """
    if len(theme.categorical_palette) > 0:
        return theme.categorical_palette.colors()
    return default_categorical_palette()


def default_categorical_palette() -> List[Color]:
    """A default qualitative color palette for categorical color encoding: 8
    visually distinct colors (the common "tab10"-style set), cycled via
    modulo when a column has more unique categories (see `Plot.encode`).

    The fallback for `Theme.categorical_palette` (a packed
    `ColorPalette`, so `Theme` stays implicitly copyable); mark files
    reach it through `categorical_palette_for(theme)` rather than
    calling this directly.

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
