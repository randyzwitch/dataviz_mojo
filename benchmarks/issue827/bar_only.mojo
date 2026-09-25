from canvas.io.png import write_png

from dataviz.chart import Plot2, render, render_svg


def main() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var c = (
        Plot2()
        .mark_bar()
        .encode_categorical(cats, vals)
        .labels(title="Typed bar")
    )
    var png = render(c)
    var svg = render_svg(c)
    print(png.width, png.height, svg.to_string().byte_length())
