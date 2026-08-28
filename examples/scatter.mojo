"""Demo: a basic scatter plot -- Mark.POINT, default theme, axes and
gridlines computed automatically from the data's domain. Built via
dataviz_mojo.scatter() -- the one-call convenience wrapper around
Plot().mark_point().encode(...).theme(...) -- rather than the builder
spelled out by hand; see plot.mojo's module docstring (its "one-call
convenience functions" section) for what it trades away (facets,
layering, color/size encoding still need Plot directly). scatter()
returns a plain, un-rendered `Plot`, exactly as if built by hand --
save() below is what actually renders and writes it out.

Raster (PNG/BMP) output is supersampled internally by render() itself
before it's ever written (see `_RASTER_SUPERSAMPLE`'s docstring,
plot.mojo) -- automatic for any `Plot`, hand-built or from a one-call
convenience function like scatter() here; nothing in this file, or any
other example, has to ask for that.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import scatter
from dataviz_mojo.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

    var c = scatter(x, y)
    save(c, "examples/out_scatter.svg")
    save(c, "examples/out_scatter.bmp")
    save(c, "examples/out_scatter.png")

