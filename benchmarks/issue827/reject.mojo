from dataviz.chart import Plot2, render


def main() raises:
    var cats: List[String] = ["a", "b", "c"]
    var start: List[Float64] = [0.0, 1.0, 2.0]
    var end: List[Float64] = [2.0, 3.0, 4.0]
    # A gantt chart has no continuous y axis: this must not compile.
    var c = Plot2().mark_gantt().encode_gantt(cats, start, end).scale_y_log()
    _ = render(c)
