"""Map a continuous data column onto point size.
"""
from dataviz_mojo.plot import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var y: List[Float64] = [12.0, 18.0, 15.0, 22.0, 19.0, 25.0, 21.0, 28.0]
    var population: List[Float64] = [4.0, 12.0, 7.0, 20.0, 9.0, 25.0, 15.0, 30.0]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, size=population)
        .labels(title="Readings by Population", subtitle="Point size mapped to a continuous variable")
    )
    save(plot, "docs/src/examples/out_bubble_size.svg")
