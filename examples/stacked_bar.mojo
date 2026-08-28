"""Demo: a stacked bar chart -- Mark.STACKED_BAR, each category's series stacked as segments on top of each other instead of Mark.
GROUPED_BAR's side-by-side sub-bars (Plot().mark_stacked_bar().encode_
grouped_bar(categories, series_names, values) -- the exact same data
shape/encode method Mark.GROUPED_BAR uses, only the mark differs; see
that method's docstring). Same quarterly-revenue-by-region data
examples/grouped_bar.mojo uses, so the two examples read as a direct
before/after comparison of the same numbers under each mark's convention: grouped answers "how do the regions compare to each other
each quarter," stacked answers "what's the total, and how is it
composed." Built via dataviz_mojo.stacked_bar() -- see
examples/scatter.mojo's docstring for what that trades away.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import stacked_bar
from dataviz_mojo.theme import Theme


def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
    var series_names: List[String] = ["North", "South", "East"]
    var values: List[List[Float64]] = [
        [42.0, 48.0, 45.0, 61.0],
        [30.0, 35.0, 33.0, 40.0],
        [55.0, 50.0, 58.0, 66.0],
    ]

    var c = stacked_bar(
        quarters,
        series_names,
        values,
        title="Quarterly Revenue by Region (stacked)",
        x_title="Quarter",
        y_title="Revenue ($M)",
    )
    save(c, "examples/out_stacked_bar.svg")
    save(c, "examples/out_stacked_bar.bmp")
    save(c, "examples/out_stacked_bar.png")
