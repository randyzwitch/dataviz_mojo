from dataviz import bar, render_svg as render_svg_plot
from dataviz.chart import Plot2, render_svg


def main() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var typed = (
        Plot2()
        .mark_bar()
        .encode_categorical(cats, vals)
        .labels(title="Typed bar")
    )
    var untyped = bar(cats, vals, title="Typed bar")
    var a = render_svg(typed).to_string()
    var b = render_svg_plot(untyped).to_string()
    print("svg identical:", a == b, a.byte_length(), b.byte_length())
