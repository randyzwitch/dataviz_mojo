from dataviz import bar, render, render_svg


def main() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var c = bar(cats, vals, title="Typed bar")
    var png = render(c)
    var svg = render_svg(c)
    print(png.width, png.height, svg.to_string().byte_length())
