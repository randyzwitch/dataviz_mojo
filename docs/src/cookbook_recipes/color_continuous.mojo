# title: Color by Continuous Variable
"""Map a continuous data column onto point color via a gradient scale.
"""
from dataviz.plot import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var y: List[Float64] = [12.0, 18.0, 15.0, 22.0, 19.0, 25.0, 21.0, 28.0]
    var temperature: List[Float64] = [58.0, 61.0, 64.0, 70.0, 74.0, 79.0, 82.0, 88.0]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color=temperature)
        .labels(title="Readings by Temperature", subtitle="Color mapped to a continuous variable")
    )
    save(plot, "docs/src/examples/out_color_continuous.svg")
