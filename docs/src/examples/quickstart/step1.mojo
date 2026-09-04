from dataviz import Plot, save


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = Plot().mark_point().encode(x=x, y=y)
    save(plot, "docs/src/examples/quickstart/out_step1.svg")
