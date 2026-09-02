"""Override a violin's own KDE bandwidth to reveal real structure the
automatic estimate would smooth away -- the default rule picks one
bandwidth from a sample's size and spread alone, which can over-smooth
a genuinely bimodal distribution into a single hump.
"""
from dataviz import violin
from dataviz.plot import save
from dataviz.theme import Theme

def main() raises:
    var shifts: List[String] = ["Morning", "Evening"]
    var wait_minutes: List[List[Float64]] = [
        [4.0, 5.0, 4.5, 5.5, 4.0, 22.0, 23.0, 24.0, 22.5, 23.5, 24.5, 22.0, 4.5, 23.0, 5.0, 22.5],
        [10.0, 11.0, 10.5, 11.5, 10.0, 11.0, 10.5, 11.5, 10.0, 11.0, 10.5, 11.5, 10.0, 11.0, 10.5, 11.5],
    ]

    var plot = violin(
        shifts,
        wait_minutes,
        bandwidth=1.5,
        theme=Theme(),
        title="Support Wait Time",
        subtitle="A smaller bandwidth than the default keeps the morning shift's two peaks distinct",
    )
    save(plot, "docs/src/examples/out_violin_bandwidth.svg")
