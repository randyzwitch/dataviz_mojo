"""OrdinalScale -- maps a fixed-order list of discrete categories onto
evenly spaced pixel bands, the standard "band scale" every bar-chart-
style categorical axis needs (matches d3's `scaleBand` in spirit: one
`padding` fraction, applied as an equal gap on both sides of every
band, not separate inner/outer padding knobs).

Purely index-based (`band_start(i)`/`center(i)`, not `band_start
(category_string)`) -- a bar chart's data already gives each row's
category and its position in that same row, so there's never a need
to search the domain by string equality to answer "where does this
category go." `Plot`'s `x_categories` list *is* this scale's
domain, index for index; a caller wanting repeated categories
(grouped/stacked bars) uses a different encoding (`Plot.encode_
grouped_bar()`), not this one.
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
        """The pixel width of one category's full slot, band plus its
        padding -- 0.0 for an empty domain rather than dividing by
        zero (an empty categorical axis is a real, if unusual, input:
        a bar chart with no data at all).

        Returns:
            The pixel width of one full slot.
        """
        if len(self.domain) == 0:
            return 0.0
        return (self.range_max - self.range_min) / Float64(len(self.domain))

    def bandwidth(self) -> Float64:
        """The pixel width of the band itself (a bar's width),
        `step()` minus the padding taken off both sides.

        Returns:
            The pixel width of the band itself.
        """
        return self.step() * (1.0 - self.padding)

    def band_start(self, index: Int) -> Float64:
        """The left pixel edge of the band at `index` -- half the
        step's padding in from that index's slot start, so the
        padding is split evenly between a band and each of its
        neighbors.

        Args:
            index: The category's position in `domain`.

        Returns:
            The band's left pixel edge.
        """
        var s = self.step()
        return self.range_min + s * Float64(index) + s * self.padding / 2.0

    def center(self, index: Int) -> Float64:
        """The horizontal pixel center of the band at `index` --
        `band_start(index)` plus half `bandwidth()`.

        Args:
            index: The category's position in `domain`.

        Returns:
            The band's horizontal pixel center.
        """
        return self.band_start(index) + self.bandwidth() / 2.0
