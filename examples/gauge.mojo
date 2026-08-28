"""Demo: a gauge chart -- Mark.GAUGE, a single value (Plot.
encode_gauge(), clamped to [min_value, max_value] rather than rejected
out of range) shown as a needle over a 270-degree color-banded dial
(green/blue/red at the default 20%/80%/100% breakpoints -- see
gauge.mojo's docstring). Built via dataviz_mojo.gauge() -- see
examples/scatter.mojo's docstring for what that trades away.

Server CPU usage -- ECharts.jl's gauge() example, the chart
type's classic use (a single live metric against a known-good/
known-bad range, read at a glance the way a real analog dial is).
"""

from dataviz_mojo.plot import save
from dataviz_mojo import gauge
from dataviz_mojo.theme import Theme


def main() raises:
    var cpu_usage = 67.0

    var c = gauge(cpu_usage)
    save(c, "examples/out_gauge.svg")
    save(c, "examples/out_gauge.bmp")
    save(c, "examples/out_gauge.png")
