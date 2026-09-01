"""Plot `List[Int]`/`List[Float32]` data directly -- `Plot.encode()`
accepts any numeric list type, not just `List[Float64]`, converting
losslessly (a real widening cast, not integer division) and still
showing whole-number labels as `"10"`, never `"10.0"`.
"""
from dataviz_mojo.plot import Plot, save
from dataviz_mojo.theme import Theme

def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
    var units_sold: List[Int] = [420, 385, 510, 601]

    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=quarters, y=units_sold)
        .theme(Theme(show_data_labels=True))
        .labels(title="Units Sold (List[Int])", y_title="Units")
    )
    save(plot, "docs/src/examples/out_numeric_types.svg")
