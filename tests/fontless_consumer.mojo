"""Package consumer used by the fontless-container CI job (#767)."""

from dataviz import save, bar


def main() raises:
    var cats: List[String] = ["north", "south"]
    var vals: List[Float64] = [3.0, 5.0]
    var plot = bar(cats, vals, title="No system fonts")
    save(plot, "fontless.png")
    save(plot, "fontless.pdf")
    print("fontless export ok")
