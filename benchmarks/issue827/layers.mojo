from dataviz.chart import Plot2, render_layers


def main() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var start: List[Float64] = [0.0, 1.0, 2.0]
    var end: List[Float64] = [2.0, 3.0, 4.0]
    var bars = Plot2().mark_bar().encode_categorical(cats, vals)
    var spans = Plot2().mark_gantt().encode_gantt(cats, start, end)
    var png = render_layers(bars, spans)
    print(png.width, png.height)
