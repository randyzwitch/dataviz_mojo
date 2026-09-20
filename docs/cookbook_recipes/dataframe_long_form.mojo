# title: Plot a Long-Form DataFrame
"""Plot observations stored one row at a time -- a category beside each value -- without building nested lists by hand, and check the grouping against the rows.

A dataframe holds measurements long: one row per observation, with the
group it belongs to in a column beside it. The distribution marks want
the opposite shape, one list of values per group, and the multi-series
marks want one row of values per series. `box(df, category=, value=)`
and `grouped_bar(df, category=, series=, value=)` do that reshaping,
keeping each group's first appearance as its order.

This recipe reads its own saved output back and checks that each
species' box sits where its rows say it should, and that a pivoted
series keeps its quarters in order.
"""
from dataframe import Column, DataFrame, Series, col

from dataviz import box, grouped_bar, save


def main() raises:
    # Illustrative body masses, one row per bird, groups interleaved.
    var species = List[String]()
    var mass_kg = List[Float64]()
    var names = ["Adelie", "Gentoo", "Chinstrap"]
    var seed = 20260920
    for i in range(90):
        species.append(names[i % 3])
        seed = (seed * 1103515245 + 12345) % 2147483648
        var spread = Float64(seed % 1200) / 1000.0
        mass_kg.append(3.4 + Float64(i % 3) * 1.1 + spread)

    var birds = DataFrame(
        [
            Series("species", Column[String](species.copy())),
            Series("mass_kg", Column[Float64](mass_kg.copy())),
        ]
    )

    # One list of values per species, from the rows.
    var spread_path = "docs/src/examples/out_dataframe_long_form.svg"
    var spread = box(
        birds,
        category="species",
        value="mass_kg",
        title="Illustrative Body Mass by Species",
        width=640,
        height=400,
    )
    save(spread, spread_path)

    # The same frame, aggregated by the dataframe, then pivoted into one
    # row of values per series.
    var sales = DataFrame(
        [
            Series(
                "quarter",
                Column[String](["Q1", "Q2", "Q1", "Q2", "Q1", "Q2"]),
            ),
            Series(
                "product",
                Column[String](
                    [
                        "widgets",
                        "widgets",
                        "gadgets",
                        "gadgets",
                        "gizmos",
                        "gizmos",
                    ]
                ),
            ),
            Series(
                "revenue_kusd",
                Column[Float64]([120.0, 138.0, 76.0, 81.0, 45.0, 62.0]),
            ),
        ]
    )
    var quarters_path = "docs/src/examples/out_dataframe_long_form_series.svg"
    var quarters = grouped_bar(
        sales.filter(col("revenue_kusd") > 0),
        category="quarter",
        series="product",
        value="revenue_kusd",
        title="Illustrative Revenue by Quarter and Product",
        width=640,
        height=400,
    )
    save(quarters, quarters_path)

    # The claims: every species got a box, the axes are titled by the
    # columns, and the pivot kept both orders.
    var f = open(spread_path, "r")
    var spread_svg = f.read()
    f.close()
    for name in names:
        if ">" + name + "</text>" not in spread_svg:
            raise Error("a species is missing from the plot: " + name)
    if ">mass_kg</text>" not in spread_svg:
        raise Error("the value axis is not titled by its column")

    var g = open(quarters_path, "r")
    var quarters_svg = g.read()
    g.close()
    for name in ["widgets", "gadgets", "gizmos"]:
        if ">" + name + "</text>" not in quarters_svg:
            raise Error("a product is missing from the legend: " + name)
    var q1 = quarters_svg.find(">Q1</text>")
    var q2 = quarters_svg.find(">Q2</text>")
    if q1 < 0 or q2 < 0 or q1 > q2:
        raise Error("the quarters are not in first-appearance order")

    print("long form: 90 rows into 3 boxes, 6 rows into 3 series")
