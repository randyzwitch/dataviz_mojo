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
module's docstring below was independently computed by hand
before trusting the Mojo implementation.
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
    var max: Float64

    def __init__(out self, min: Float64, max: Float64):
        self.min = min
        self.max = max


def _min_max(data: List[Float64]) raises -> MinMax:
    """`data`'s [min, max]. Raises on an empty list rather than
    indexing out of bounds, which is what it used to do -- `data[0]`
    with no length check at all.

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
    `String(Float64)` isn't usable for tick labels: confirmed by probe
    that e.g. 0.0 + 3*0.1 prints as "0.30000000000000004", ordinary
    binary-floating-point drift with nothing to do with this module's math. Rounds to the nearest representable value at `decimals`
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


struct Ticks(Movable):
    """LinearScale.ticks()'s result: the tick positions themselves
    plus how many decimal places they need for display -- both
    returned together since the decimal count falls straight out of
    the same step computation _nice_step already did, not a separate
    thing to re-derive from a tick value afterward."""

    var values: List[Float64]
    var decimals: Int

    def __init__(out self, var values: List[Float64], decimals: Int):
        self.values = values^
        self.decimals = decimals

    def labels(self) -> List[String]:
        """Each tick value formatted via _format_fixed at this
        Ticks' `decimals` -- the convenience an axis-drawing
        caller actually wants, without needing to know
        _format_fixed exists."""
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
    var domain_max: Float64
    var range_min: Float64
    var range_max: Float64

    def __init__(
        out self, domain_min: Float64, domain_max: Float64, range_min: Float64, range_max: Float64
    ):
        self.domain_min = domain_min
        self.domain_max = domain_max
        self.range_min = range_min
        self.range_max = range_max

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
        approximately, confirmed directly in
        test_linear_scale_endpoints_map_to_range_exactly)."""
        return self.range_min - self.domain_min * self.scale()

    def to_pixel(self, value: Float64) -> Float64:
        return value * self.scale() + self.translate()

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
        """
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
