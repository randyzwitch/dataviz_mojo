"""OrdinalScale maps a fixed-order list of discrete categories onto
evenly spaced pixel bands, the band scale every bar-chart-style
categorical axis uses (like d3's `scaleBand`, with a single `padding`
fraction applied as an equal gap on both sides of every band).

Index-based (`band_start(i)`/`center(i)`), never looked up by category
string: `Plot.x_categories` is this scale's domain, index for index.
Repeated categories (grouped/stacked bars) go through
`Plot.encode_grouped_bar()` instead.
"""


struct OrdinalScale(Movable):
    var domain: List[String]
    """The fixed-order category list this scale's bands index into --
    `Plot`'s own `x_categories`, index for index."""
    var range_min: Float64
    """The pixel position the first category's band starts from."""
    var range_max: Float64
    """The pixel position the last category's band ends at."""
    var padding: Float64
    """The fraction of each category's slot left as a gap, split
    evenly between a band and each of its neighbors; defaults to
    `0.2`."""

    def __init__(
        out self,
        var domain: List[String],
        range_min: Float64,
        range_max: Float64,
        padding: Float64 = 0.2,
    ):
        """Construct an `OrdinalScale` over `domain`, banded across
        `[range_min, range_max]`.

        Args:
            domain: The fixed-order category list, index for index.
            range_min: The pixel position the first band starts from.
            range_max: The pixel position the last band ends at.
            padding: The fraction of each slot left as a gap; defaults
                to `0.2`.
        """
        self.domain = domain^
        self.range_min = range_min
        self.range_max = range_max
        self.padding = padding

    def step(self) -> Float64:
        """The pixel width of one category's full slot, band plus padding; 0.0
        for an empty domain.

        Returns:
            The pixel width of one full slot.
        """
        if len(self.domain) == 0:
            return 0.0
        return (self.range_max - self.range_min) / Float64(len(self.domain))

    def bandwidth(self) -> Float64:
        """The pixel width of the band itself (a bar's width): `step()` minus the
        padding on both sides.

        Returns:
            The pixel width of the band itself.
        """
        return self.step() * (1.0 - self.padding)

    def band_start(self, index: Int) -> Float64:
        """The left pixel edge of the band at `index`: half the slot's padding in
        from the slot start.

        Args:
            index: The category's position in `domain`.

        Returns:
            The band's left pixel edge.
        """
        var s = self.step()
        return self.range_min + s * Float64(index) + s * self.padding / 2.0

    def band_end(self, index: Int) -> Float64:
        """The right pixel edge of the band at `index`: half the slot's
        padding in from the *next* slot's start.

        Deliberately not `band_start(index) + bandwidth()`, which is the
        same number in exact arithmetic and not always the same
        `Float64` (#379). That form accumulates as
        `(range_min + s*i) + s`, while the neighbor's
        `band_start(index + 1)` evaluates `range_min + s*(i+1)`, and
        floating-point addition is not associative -- at
        420px x 24 categories the two came out 186.99999999999997 and
        187.0. Snapping each to the pixel grid then rounded them to
        different boundaries and left a one-pixel column of background
        between two cells that should have touched.

        Computing from `range_min + s * (index + 1)`, the identical
        expression the neighbor's `band_start` uses, makes the two
        bitwise equal whenever the padding is zero, so adjacent bands
        cannot disagree about where their shared boundary is.

        Args:
            index: The category's position in `domain`.

        Returns:
            The band's right pixel edge.
        """
        var s = self.step()
        return self.range_min + s * Float64(index + 1) - s * self.padding / 2.0

    def center(self, index: Int) -> Float64:
        """The horizontal pixel center of the band at `index` --
        `band_start(index)` plus half `bandwidth()`.

        Args:
            index: The category's position in `domain`.

        Returns:
            The band's horizontal pixel center.
        """
        return self.band_start(index) + self.bandwidth() / 2.0
