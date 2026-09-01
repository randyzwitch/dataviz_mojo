# title: Reference Line
"""Add a horizontal reference line at `value` on the y-axis. Outside
the mark's (padded) y-domain, draws nothing rather than clipping to an
edge -- callable more than once, so a target line and an average line
can both be added to the same chart.
"""
from dataviz.plot import Plot, save

def main() raises:
    var months: List[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    var revenue: List[Float64] = [42.0, 48.0, 45.0, 61.0, 55.0, 58.0]

    var plot = Plot().mark_bar().encode_categorical(x=months, y=revenue).labels(
        title="Monthly Revenue", subtitle="Actual vs. target, $M"
    ).annotate_line(60.0, label="target").annotate_line(51.5, label="average")
    save(plot, "docs/src/examples/out_annotate_line.svg")
