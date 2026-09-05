"""Draw each bar's own value directly on the chart with
`Theme.show_data_labels=True` -- above a positive bar, below a
negative one, or centered inside a stacked segment.
"""
from dataviz.plot import Plot, save
from dataviz.theme import Theme


def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
    var revenue: List[Float64] = [42.5, 48.0, 45.2, 61.0]

    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=quarters, y=revenue)
        .theme(Theme(show_data_labels=True))
        .labels(title="Quarterly Revenue", y_title="Revenue ($M)")
    )
    save(plot, "docs/src/examples/out_data_labels.svg")
