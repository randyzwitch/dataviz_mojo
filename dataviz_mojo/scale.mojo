"""LinearScale -- maps a continuous data domain onto a pixel range,
and picks "nice" tick positions within that domain for axis labeling.
This is the piece canvas_mojo.geometry.Transform2D's docstring already
named as deferred here: `scale()`/`translate()` below compute exactly
the slope/intercept Transform2D's affine map takes, so Plot builds one
Transform2D from an x-scale and a y-scale (with the y-scale's range
reversed -- pixel y increases downward, data y conventionally
increases upward, the same "negative scale_y" trick Transform2D's docstring documents) rather than reimplementing the linear map here.

`ticks()` is the one genuinely new algorithm in this package: Paul
Heckbert's "nice numbers for graph labels" (Graphics Gems, 1990), the
same approach d3/matplotlib/most charting libraries use in spirit --
round the ideal step size for a target tick count up to the nearest
"nice" multiple (1, 2, 5, or 10 times a power of ten) so labels read
as 0.2/0.4/0.6, not 0.1934/0.3868/0.5802. Every example in this
module's docstring below was independently computed by hand.
"""

from std.math import ceil, floor, log10, pow

from canvas_mojo.geometry import _round_to_int


struct MinMax(ImplicitlyCopyable, Movable):
    """A column's [min, max] -- a small named struct rather than a
    positional tuple (see scale.mojo's sibling `Ticks`/`_NiceStep` for
    the same reasoning), and the shared starting point for every kind
    of domain this package computes: `Plot._data_extent` pads it for
    spatial (x/y) axes, `ColorScale`/size encoding use it exactly as-
    is (no padding -- a color/size legend's extremes should mean
    exactly the data's extremes, not a padded approximation of
    them)."""

    var min: Float64
    """The column's smallest value."""
    var max: Float64
    """The column's largest value."""

    def __init__(out self, min: Float64, max: Float64):
        """Construct a `MinMax` from an already-known min and max.

        Args:
            min: The column's smallest value.
            max: The column's largest value.
        """
        self.min = min
        self.max = max


def _min_max(data: List[Float64]) raises -> MinMax:
    """`data`'s [min, max]. Raises on an empty list rather than
    indexing `data[0]` out of bounds.

    No caller can currently reach that (every one guards on its data being non-empty first, and the render paths return early
    before this on an empty plot), so this raises rather than
    inventing a fallback: there is no honest [min, max] of nothing, and
    a silent `MinMax(0.0, 0.0)` would hand back a degenerate domain
    that renders as a real axis, which is exactly the "silently
    misrepresent the data" failure this package's encode/render
    checks exist to prevent. A clear error at the boundary beats a
    plausible-looking wrong chart.
    """
    if len(data) == 0:
        raise Error("_min_max(): can't take the min/max of an empty column")
    var lo = data[0]
    var hi = data[0]
    for v in data:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    return MinMax(lo, hi)


struct _NiceStep(ImplicitlyCopyable, Movable):
    """`_nice_step`'s result -- a small struct instead of a positional
    tuple, matching this workspace's general aversion to positional
    magic values (see e.g. canvas_mojo/tests/test_text.mojo's _InkBBox)."""

    var step: Float64
    var exponent: Int

    def __init__(out self, step: Float64, exponent: Int):
        self.step = step
        self.exponent = exponent


def _nice_step(domain_min: Float64, domain_max: Float64, target_count: Int) -> _NiceStep:
    """The step size and its base-10 exponent for `target_count`-ish
    ticks spanning [domain_min, domain_max]. The exponent is what
    tells _format_fixed how many decimal places a tick actually needs
    -- can't just be re-derived from the step value via another log10
    call afterward: a step of exactly 5.0 needs 0 decimals, but
    -log10(5.0) is positive, not the 0-or-negative value that
    reasoning alone would suggest without tracking the exponent
    through nice_m's possible bump to the next power of ten.

    Hand-verified (see this file's module docstring):
    domain [0,100], target 5 -> step 20.0 (raw step 20, already nice);
    domain [3,27], target 5 -> step 5.0 (raw step 4.8, rounds up to
    the next nice value, not down); domain [-50,50], target 5 -> step
    20.0 (negative domains work the same way, no special-casing
    needed since only the span and log10 of a positive raw step ever
    get computed).
    """
    var raw_step = (domain_max - domain_min) / Float64(target_count)
    var exponent = Int(floor(log10(raw_step)))
    var magnitude = pow(10.0, Float64(exponent))
    var normalized = raw_step / magnitude

    var nice_m = 10.0
    if normalized <= 1.0 + 1e-9:
        nice_m = 1.0
    elif normalized <= 2.0 + 1e-9:
        nice_m = 2.0
    elif normalized <= 5.0 + 1e-9:
        nice_m = 5.0

    if nice_m == 10.0:
        nice_m = 1.0
        exponent += 1

    return _NiceStep(nice_m * pow(10.0, Float64(exponent)), exponent)


def _format_fixed(value: Float64, decimals: Int) -> String:
    """Format `value` to exactly `decimals` decimal places -- plain
    `String(Float64)` isn't usable for tick labels: e.g. 0.0 + 3*0.1
    prints as "0.30000000000000004", ordinary binary-floating-point
    drift with nothing to do with this module's math. Rounds to the
    nearest representable value at `decimals`
    places first (round-half-away-from-zero, via the same
    `_round_to_int` geometry.mojo's pixel rounding uses), then splits
    into integer and fractional parts and builds the string by hand
    rather than trusting float formatting a second time. `decimals` of
    0 skips the decimal point entirely rather than printing "20.".
    """
    if decimals <= 0:
        return String(_round_to_int(value))

    var scale = pow(10.0, Float64(decimals))
    var scaled = _round_to_int(value * scale)
    var sign = "-" if scaled < 0 else ""
    var digits = scaled if scaled >= 0 else -scaled
    var int_part = digits // Int(scale + 0.5)
    var frac_part = digits % Int(scale + 0.5)

    var frac_str = String(frac_part)
    while frac_str.byte_length() < decimals:
        frac_str = "0" + frac_str

    return sign + String(int_part) + "." + frac_str


def _log_ticks(domain_min: Float64, domain_max: Float64) -> Ticks:
    """Tick positions for a log10-scaled `LinearScale` -- `domain_min`/
    `domain_max` are already in log10-space (a log scale's own
    `domain_min`/`domain_max`, per `LinearScale.to_pixel()`'s
    docstring), so `10.0**domain_min`/`10.0**domain_max` are the
    real-unit bounds ticks must fall within. Returns real-unit values
    (1, 10, 100, ..., never their own log) -- ready to feed straight
    into the same `to_pixel()` every other value on this axis already
    goes through, which itself takes `log10()` of whatever it's given
    when `is_log` is set; passing an already-logged position here
    would double-transform it.

    Major ticks only (`1 * 10^k`) whenever the visible span covers
    more than 2 decades -- the standard log-axis convention
    (matplotlib's `LogLocator` does the same) to avoid a cluttered
    1/2/5-per-decade axis on a wide range. `1 * 10^k`/`2 * 10^k`/
    `5 * 10^k` within each covered decade otherwise, for a genuinely
    readable axis when there's only one or two decades to show.
    Hand-verified: domain `[0, 3]` (real `[1, 1000]`, a 3-decade span)
    -> majors only, `[1, 10, 100, 1000]`; domain `[0, 1]` (real
    `[1, 10]`, one decade) -> the full 1/2/5 set, `[1, 2, 5, 10]`.

    A degenerate zero-span domain (shouldn't reach here in practice --
    `_log_data_extent()` always pads -- but handled the same defensive
    way `LinearScale.ticks()`'s own zero-span case is) returns a
    single tick at the one real value. A domain narrow enough to miss
    every `1`/`2`/`5` multiple in its own decade (e.g. `[35, 40]`,
    between the `2*10^1` and `5*10^1` ticks) falls back to its own two
    real endpoints rather than an empty axis.
    """
    if domain_min == domain_max:
        var v = pow(10.0, domain_min)
        var single: List[Float64] = [v]
        var single_label: List[String] = [_format_fixed(v, max(0, -Int(floor(domain_min))))]
        return Ticks(single^, 0, single_label^)

    var start_exp = Int(floor(domain_min))
    var end_exp = Int(ceil(domain_max))
    var lo = pow(10.0, domain_min)
    var hi = pow(10.0, domain_max)
    var wide = (end_exp - start_exp) > 2

    var values = List[Float64]()
    var labels = List[String]()
    for e in range(start_exp, end_exp + 1):
        var decade = pow(10.0, Float64(e))
        var mults: List[Float64] = [1.0] if wide else [1.0, 2.0, 5.0]
        for m in mults:
            var v = m * decade
            # A tiny relative tolerance against the real bounds, not an
            # exact >=/<=, so a tick that should land exactly on a
            # padded boundary (computed through pow()/floor()/ceil())
            # isn't dropped by ordinary floating-point rounding --
            # the same reasoning LinearScale.ticks()'s own boundary-
            # inclusive comment gives for the linear case.
            if v >= lo * (1.0 - 1e-9) and v <= hi * (1.0 + 1e-9):
                values.append(v)
                labels.append(_format_fixed(v, max(0, -e)))

    if len(values) == 0:
        values = [lo, hi]
        labels = [
            _format_fixed(lo, max(0, -start_exp)),
            _format_fixed(hi, max(0, -end_exp)),
        ]

    return Ticks(values^, 0, labels^)


struct Ticks(Movable):
    """LinearScale.ticks()'s result: the tick positions themselves
    plus how many decimal places they need for display -- both
    returned together since the decimal count falls straight out of
    the same step computation _nice_step already did, not a separate
    thing to re-derive from a tick value afterward."""

    var values: List[Float64]
    """The tick positions themselves, in the scale's data domain."""
    var decimals: Int
    """How many decimal places every tick value needs for display --
    falls straight out of `_nice_step`'s own step computation. Unused
    (but still present) whenever `override_labels` is non-empty."""
    var override_labels: List[String]
    """Pre-formatted labels, one per `values` entry, empty (the
    default) for the ordinary case where every tick shares one
    `decimals` count. Non-empty only for `_log_ticks()`'s log-scaled
    ticks, where a decade-spanning axis needs a *different* decimal
    count per tick (0.01 needs 2 places, 100 needs 0) -- something one
    shared `decimals` can't express, unlike every linear-scale case
    `_nice_step` ever produces."""

    def __init__(
        out self, var values: List[Float64], decimals: Int, var override_labels: List[String] = List[String]()
    ):
        """Construct a `Ticks` from already-computed positions and a
        decimal count -- normally built by `LinearScale.ticks()`, not
        called directly.

        Args:
            values: The tick positions, in the scale's data domain.
            decimals: How many decimal places every tick value needs
                for display. Ignored if `override_labels` is given.
            override_labels: Pre-formatted labels, one per `values`
                entry; left empty (the default) to format every tick
                via `decimals` instead.
        """
        self.values = values^
        self.decimals = decimals
        self.override_labels = override_labels^

    def labels(self) -> List[String]:
        """Each tick value formatted via _format_fixed at this
        Ticks' `decimals` -- the convenience an axis-drawing
        caller actually wants, without needing to know
        _format_fixed exists. Returns `override_labels` unchanged
        instead, when set (see its own docstring for why).

        Returns:
            One formatted string per `values` entry, same order.
        """
        if len(self.override_labels) > 0:
            return self.override_labels.copy()
        var result = List[String](capacity=len(self.values))
        for v in self.values:
            result.append(_format_fixed(v, self.decimals))
        return result^


struct LinearScale(ImplicitlyCopyable, Movable):
    """A linear map from [domain_min, domain_max] to [range_min,
    range_max] -- `range_min`/`range_max` are the pixel positions
    `domain_min`/`domain_max` land on, not necessarily numerically
    increasing (a y-axis scale passes range_min=plot_bottom_pixel,
    range_max=plot_top_pixel, a *smaller* pixel value, since pixel y
    increases downward -- the map comes out with a negative slope
    automatically, no separate "flip" flag needed).
    """

    var domain_min: Float64
    """The low end of the data domain this scale maps from."""
    var domain_max: Float64
    """The high end of the data domain this scale maps from."""
    var range_min: Float64
    """The pixel position `domain_min` maps to."""
    var range_max: Float64
    """The pixel position `domain_max` maps to -- not necessarily
    greater than `range_min` (a y-axis scale passes a *smaller* pixel
    value here, since pixel y increases downward)."""
    var is_log: Bool
    """`False` (the default -- every pre-existing `LinearScale` keeps
    mapping exactly as it always has) for a plain linear scale.
    `True` for a log10-scaled axis (`Plot.scale_y_log()`/
    `scale_x_log()`): `domain_min`/`domain_max` are then themselves
    already in log10-space (see `_log_data_extent()`, plot.mojo), and
    `to_pixel()` takes `log10()` of whatever real-unit value it's
    given before applying the same affine map -- every caller
    (data points, gridlines, tick marks, `Plot.annotate_line()`/
    `annotate_area()`/`annotate_vline()`/`annotate_point()`, all of
    which already go through `to_pixel()`/`_axis_pixel()`, plot.mojo)
    keeps passing real-unit values exactly as it does for a linear
    scale, unaware which kind of scale it's actually talking to."""

    def __init__(
        out self,
        domain_min: Float64,
        domain_max: Float64,
        range_min: Float64,
        range_max: Float64,
        is_log: Bool = False,
    ):
        """Construct a `LinearScale` from an already-known domain and
        pixel range.

        Args:
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.
            range_min: The pixel position `domain_min` maps to.
            range_max: The pixel position `domain_max` maps to.
            is_log: Whether `domain_min`/`domain_max` are in log10-
                space and `to_pixel()` should log-transform its input
                first; see this field's own docstring.
        """
        self.domain_min = domain_min
        self.domain_max = domain_max
        self.range_min = range_min
        self.range_max = range_max
        self.is_log = is_log

    def scale(self) -> Float64:
        """The slope for a Transform2D built from this axis --
        (range_max - range_min) / (domain_max - domain_min). Zero
        domain span (a constant-valued column) returns 0.0 rather than
        dividing by zero; every input then maps to range_min via
        to_pixel's translate term, a single point/line rather than
        a crash.
        """
        var span = self.domain_max - self.domain_min
        if span == 0.0:
            return 0.0
        return (self.range_max - self.range_min) / span

    def translate(self) -> Float64:
        """The intercept for a Transform2D built from this axis --
        derived from scale() so domain_min always maps to exactly
        range_min (to_pixel(domain_min) == range_min, not just
        approximately -- see
        test_linear_scale_endpoints_map_to_range_exactly)."""
        return self.range_min - self.domain_min * self.scale()

    def to_pixel(self, value: Float64) -> Float64:
        """Map a data value onto its pixel position -- `scale()`'s
        slope times `value`, plus `translate()`'s intercept. Takes
        `log10(value)` first when `is_log` is set (see that field's
        docstring) -- `value` itself is always the real, untransformed
        data value; every caller stays the same either way.

        Args:
            value: The data value to map, in real units (never
                pre-logged, even when `is_log` is set).

        Returns:
            The pixel position `value` lands on.
        """
        var v = log10(value) if self.is_log else value
        return v * self.scale() + self.translate()

    def ticks(self, target_count: Int = 5) -> Ticks:
        """"Nice" tick positions within [domain_min, domain_max] (see
        _nice_step), generated *within* the domain, not extending it
        -- ceil(domain_min/step)*step up to floor(domain_max/step)*step
        -- so an axis's visible range always matches its scale's domain exactly; a tick landing exactly on a boundary is
        included (matches this file's hand-verified examples,
        e.g. domain [0,100] includes both the 0 and 100 ticks).

        A zero-span domain (every data value identical) returns a
        single tick at domain_min with 0 decimals rather than running
        the nice-step math against a zero raw step (which would need
        log10(0), undefined) -- a real, reachable case (e.g. a column
        of constant values), not just a defensive check.

        Args:
            target_count: Roughly how many ticks to aim for; the
                actual count depends on which "nice" step size the
                domain rounds to. Defaults to `5`.

        Returns:
            The computed tick positions and their shared decimal
            count.
        """
        if self.is_log:
            return _log_ticks(self.domain_min, self.domain_max)
        if self.domain_min == self.domain_max:
            var single: List[Float64] = [self.domain_min]
            return Ticks(single^, 0)

        var nice = _nice_step(self.domain_min, self.domain_max, target_count)
        var decimals = max(0, -nice.exponent)

        var start = ceil(self.domain_min / nice.step) * nice.step
        var stop = floor(self.domain_max / nice.step) * nice.step
        var count = _round_to_int((stop - start) / nice.step) + 1

        var result = List[Float64](capacity=count)
        for i in range(count):
            result.append(start + Float64(i) * nice.step)

        return Ticks(result^, decimals)
