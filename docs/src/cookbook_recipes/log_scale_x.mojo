# title: Log Scale (X-Axis)
"""Scale the x-axis logarithmically (base 10) instead of linearly.
"""
from dataviz.plot import Plot, save

def main() raises:
    var frequency: List[Float64] = [
        20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0
    ]
    var response_db: List[Float64] = [-2.0, -1.0, 0.0, 0.5, 1.0, 0.0, -1.5, -3.0, -6.0, -10.0]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=frequency, y=response_db)
        .labels(title="Frequency Response", x_title="Frequency (Hz)", y_title="Gain (dB)")
        .scale_x_log()
    )
    save(plot, "docs/src/examples/out_scale_x_log.svg")
