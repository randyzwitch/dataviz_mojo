# title: Reference Band
"""Add a shaded horizontal band from `y0` to `y1` on the y-axis --
`y0`/`y1` don't need to be given low-to-high, and a band that only
partially overlaps the mark's own y-domain clips to the visible
portion instead of disappearing entirely.
"""
from dataviz_mojo.plot import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var latency: List[Float64] = [42.0, 48.0, 45.0, 61.0, 55.0, 58.0, 70.0, 63.0]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=latency)
        .labels(title="Response Time (ms)", subtitle="Against an acceptable range")
        .annotate_area(50.0, 60.0, label="acceptable range")
    )
    save(plot, "docs/src/examples/out_annotate_area.svg")
