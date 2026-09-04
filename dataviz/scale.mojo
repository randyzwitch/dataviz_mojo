"""LinearScale maps a continuous data domain onto a pixel range and
picks "nice" tick positions within that domain for axis labeling.
`scale()`/`translate()` compute the slope/intercept
`canvas.geometry.Transform2D`'s affine map takes, so `Plot` builds a
Transform2D from an x-scale and a y-scale (the y-scale's range
reversed, since pixel y increases downward).

`ticks()` implements Paul Heckbert's "nice numbers for graph labels"
(Graphics Gems, 1990), the approach d3/matplotlib use: round the
ideal step for a target tick count up to the nearest 1, 2, 5, or 10
times a power of ten, so labels read as 0.2/0.4/0.6 rather than
0.1934/0.3868/0.5802.
"""

from std.math import ceil, floor, log10, pow

from canvas.geometry import _round_to_int


struct MinMax(ImplicitlyCopyable, Movable):
    """A column's [min, max], the starting point for every domain this
    package computes: `Plot._data_extent` pads it for spatial axes;
    `ColorScale`/size encoding use it as-is, so a legend's extremes are
    exactly the data's.
    """

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
    """`data`'s [min, max]. Raises on an empty list. No caller can currently
    reach that (each guards on non-empty data first), and there is no
    honest [min, max] of nothing; a silent `MinMax(0.0, 0.0)` would render
    as a real axis.
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
    """`_nice_step`'s result."""

    var step: Float64
    var exponent: Int

    def __init__(out self, step: Float64, exponent: Int):
        self.step = step
        self.exponent = exponent


def _nice_step(
    domain_min: Float64, domain_max: Float64, target_count: Int
) -> _NiceStep:
    """The step size and its base-10 exponent for `target_count`-ish ticks
    spanning [domain_min, domain_max]. The exponent tells `_format_fixed`
    how many decimal places a tick needs; it can't be re-derived from the
    step via log10 afterward (a step of exactly 5.0 needs 0 decimals, but
    log10(5.0) is positive), and must track `nice_m`'s possible bump to
    the next power of ten.

    Examples: domain [0,100], target 5 -> step 20.0; domain [3,27],
    target 5 -> step 5.0 (raw step 4.8 rounds up); domain [-50,50],
    target 5 -> step 20.0 (only the span and log10 of a positive raw step
    are ever computed, so negative domains need no special case).
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


comptime _FORMAT_FIXED_MAX_EXACT_MAGNITUDE = 9007199254740992.0
"""2^53, the largest magnitude at or below which every integer is
exactly representable in a `Float64` (a `Float64` has a 52-bit mantissa
plus an implicit leading bit; 2^53 itself is exact, 2^53+1 is the first
value that isn't). `_format_fixed`'s digit-by-digit path rounds `value
* 10^decimals` through `_round_to_int`'s `Int(Float64)` cast, which is
exact only up to this bound and silently wraps to garbage past it
(`Int` overflow on a float-to-int conversion is not checked); well
before that, `Int`'s own range (~9.223e18) would overflow outright for
a large enough `value`/`decimals` combination. Since a `Float64` past
this magnitude already has no representable fractional bits, treating
it as more precise than its own `String(Float64)` conversion is false
in the first place, so `_format_fixed`/`_label_decimals` defer to
`_format_fixed_overflow`/return `0` rather than risk either failure
mode (#205).
"""


def _format_fixed_overflow(value: Float64) -> String:
    """`_format_fixed`'s fallback for `abs(value) * 10^decimals` past
    `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE`: Mojo's own `String(Float64)`,
    which switches to scientific notation at exactly this kind of
    magnitude ("1e+19", "-3e+18") and never overflows, unlike the
    digit-by-digit `Int`-based path this replaces. `decimals` is ignored
    here -- a magnitude this large has no representable fractional
    digits for it to mean anything against. Plain fixed/scientific
    notation, not the SI-prefixed or significant-digit-limited form a
    real large-magnitude tick formatter would use (see #210); this
    exists only so `_format_fixed` never produces incorrect output,
    not to make it pretty.
    """
    return String(value)


def _format_fixed(value: Float64, decimals: Int) -> String:
    """Format `value` to exactly `decimals` decimal places. Plain
    `String(Float64)` isn't usable for tick labels (0.0 + 3*0.1 prints as
    "0.30000000000000004"). Rounds to the nearest representable value at
    `decimals` places first (round-half-away-from-zero via
    `_round_to_int`), then builds the string from integer and fractional
    parts by hand. `decimals` of 0 skips the decimal point rather than
    printing "20.".

    Falls back to `_format_fixed_overflow` when `abs(value) *
    10^decimals` exceeds `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE`: past that
    point the digit-by-digit path below silently produces wrong digits
    (or, past `Int`'s own range, outright garbage -- see
    `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE`'s own docstring) rather than
    raising, so this must catch it before ever calling `_round_to_int`.
    """
    if decimals <= 0:
        if abs(value) > _FORMAT_FIXED_MAX_EXACT_MAGNITUDE:
            return _format_fixed_overflow(value)
        return String(_round_to_int(value))

    var scale = pow(10.0, Float64(decimals))
    if abs(value) * scale > _FORMAT_FIXED_MAX_EXACT_MAGNITUDE:
        return _format_fixed_overflow(value)
    var scaled = _round_to_int(value * scale)
    var sign = "-" if scaled < 0 else ""
    var digits = scaled if scaled >= 0 else -scaled
    var int_part = digits // Int(scale + 0.5)
    var frac_part = digits % Int(scale + 0.5)

    var frac_str = String(frac_part)
    while frac_str.byte_length() < decimals:
        frac_str = "0" + frac_str

    return sign + String(int_part) + "." + frac_str


def _label_decimals(value: Float64, max_decimals: Int = 2) -> Int:
    """The fewest decimal places (up to `max_decimals`) that represent
    `value` with no visible rounding error, for `Theme.show_data_labels`.
    Not tied to the axis's `Ticks.decimals`: an axis stepping by whole
    10s still needs a data label to show `15.3` as `15.3`.

    Checked by re-scaling and rounding at each candidate count with a
    1e-9 tolerance rather than exact float equality. Returns
    `max_decimals` if no smaller count clears that tolerance.

    Returns `0` immediately for `abs(value) >
    _FORMAT_FIXED_MAX_EXACT_MAGNITUDE` rather than entering the loop: a
    `Float64` that large has no representable fractional part for any
    decimal count to expose, and the loop's own `_round_to_int(value *
    scale)` would hit the same overflow `_format_fixed` guards against
    (#205).
    """
    if abs(value) > _FORMAT_FIXED_MAX_EXACT_MAGNITUDE:
        return 0
    for d in range(max_decimals + 1):
        var scale = pow(10.0, Float64(d))
        var rounded = Float64(_round_to_int(value * scale)) / scale
        if abs(value - rounded) < 1e-9:
            return d
    return max_decimals


def _log_ticks(domain_min: Float64, domain_max: Float64) -> Ticks:
    """Tick positions for a log10-scaled `LinearScale`. `domain_min`/
    `domain_max` are in log10-space (per `LinearScale.to_pixel()`), so
    `10.0**domain_min`/`10.0**domain_max` are the real-unit bounds.
    Returns real-unit values (1, 10, 100, ...), since `to_pixel()` takes
    `log10()` of its input itself when `is_log` is set.

    Major ticks only (`1 * 10^k`) when the visible span covers more than
    2 decades (matplotlib's `LogLocator` convention); `1`/`2`/`5 * 10^k`
    per decade otherwise. Domain `[0, 3]` (real `[1, 1000]`) gives
    `[1, 10, 100, 1000]`; domain `[0, 1]` (real `[1, 10]`) gives
    `[1, 2, 5, 10]`.

    A zero-span domain returns a single tick at the one real value. A
    domain too narrow to contain any `1`/`2`/`5` multiple (e.g.
    `[35, 40]`) falls back to its two real endpoints.
    """
    if domain_min == domain_max:
        var v = pow(10.0, domain_min)
        var single: List[Float64] = [v]
        var single_label: List[String] = [
            _format_fixed(v, max(0, -Int(floor(domain_min))))
        ]
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
            # A tiny relative tolerance against the real bounds, so a tick that
            # should land exactly on a padded boundary (computed through
            # pow()/floor()/ceil()) isn't dropped by floating-point rounding.
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
    """`LinearScale.ticks()`'s result: the tick positions plus how many
    decimal places they need for display, both from the same
    `_nice_step` computation.
    """

    var values: List[Float64]
    """The tick positions themselves, in the scale's data domain."""
    var decimals: Int
    """How many decimal places every tick value needs for display, from
    `_nice_step`. Unused when `override_labels` is non-empty.
    """
    var override_labels: List[String]
    """Pre-formatted labels, one per `values` entry; empty (the default)
    when every tick shares one `decimals` count. Non-empty only for
    `_log_ticks()`, where each tick needs its own decimal count (0.01
    needs 2 places, 100 needs 0).
    """

    def __init__(
        out self,
        var values: List[Float64],
        decimals: Int,
        var override_labels: List[String] = List[String](),
    ):
        """Construct a `Ticks` from already-computed positions and a decimal
        count; normally built by `LinearScale.ticks()`.

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
        """Each tick value formatted via `_format_fixed` at this `Ticks`'
        `decimals`, or `override_labels` unchanged when set.

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
    """A linear map from [domain_min, domain_max] to [range_min, range_max].
    `range_min`/`range_max` are the pixel positions `domain_min`/
    `domain_max` land on, not necessarily increasing: a y-axis scale
    passes range_min=plot_bottom_pixel and range_max=plot_top_pixel, and
    the map comes out with a negative slope.
    """

    var domain_min: Float64
    """The low end of the data domain this scale maps from."""
    var domain_max: Float64
    """The high end of the data domain this scale maps from."""
    var range_min: Float64
    """The pixel position `domain_min` maps to."""
    var range_max: Float64
    """The pixel position `domain_max` maps to; not necessarily greater
    than `range_min` (a y-axis scale passes a smaller pixel value here).
    """
    var is_log: Bool
    """`False` (the default) for a plain linear scale. `True` for a
    log10-scaled axis (`Plot.scale_y_log()`/`scale_x_log()`):
    `domain_min`/`domain_max` are then in log10-space (see
    `_log_data_extent()`, plot.mojo) and `to_pixel()` takes `log10()` of
    the real-unit value it's given before applying the affine map, so
    every caller keeps passing real-unit values.
    """

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
        """The slope for a Transform2D built from this axis:
        (range_max - range_min) / (domain_max - domain_min). A zero domain
        span returns 0.0 rather than dividing by zero; every input then maps
        to range_min.
        """
        var span = self.domain_max - self.domain_min
        if span == 0.0:
            return 0.0
        return (self.range_max - self.range_min) / span

    def translate(self) -> Float64:
        """The intercept for a Transform2D built from this axis, derived from
        scale() so `to_pixel(domain_min) == range_min` exactly.
        """
        return self.range_min - self.domain_min * self.scale()

    def to_pixel(self, value: Float64) -> Float64:
        """Map a data value onto its pixel position: `scale()` times `value`
        plus `translate()`. Takes `log10(value)` first when `is_log` is set;
        `value` is always the real, untransformed data value.

        Args:
            value: The data value to map, in real units (never
                pre-logged, even when `is_log` is set).

        Returns:
            The pixel position `value` lands on.
        """
        var v = log10(value) if self.is_log else value
        return v * self.scale() + self.translate()

    def ticks(self, target_count: Int = 5) -> Ticks:
        """ "Nice" tick positions within [domain_min, domain_max] (see
        `_nice_step`), from ceil(domain_min/step)*step to
        floor(domain_max/step)*step, so ticks never extend past the domain; a
        tick landing exactly on a boundary is included (domain [0,100]
        includes both 0 and 100).

        A zero-span domain returns a single tick at domain_min with 0
        decimals, since the nice-step math would need log10(0).

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
