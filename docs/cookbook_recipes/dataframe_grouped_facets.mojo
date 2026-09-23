# title: Grouped DataFrame Facets
"""Compare campaign spend and revenue by region and product.

The frame stays long: each row is one campaign. `scatter_facets()` reads
named columns, splits panels by region, and keeps each product's color
fixed across panels even though North has no campaign for Product B.
The requested orders are independent of row order.
"""
from dataframe import Column, DataFrame, Series
from dataviz import save_facets, scatter_facets


def main() raises:
    var region: List[String] = [
        "South",
        "North",
        "South",
        "East",
        "North",
        "East",
    ]
    var product: List[String] = [
        "Product B",
        "Product A",
        "Product A",
        "Product B",
        "Product A",
        "Product A",
    ]
    var spend: List[Float64] = [8.0, 6.0, 11.0, 9.0, 13.0, 15.0]
    var revenue: List[Float64] = [12.0, 10.0, 16.0, 13.0, 20.0, 22.0]
    var campaigns = DataFrame(
        [
            Series("region", Column[String](region.copy())),
            Series("product", Column[String](product.copy())),
            Series("spend", Column[Float64](spend.copy())),
            Series("revenue", Column[Float64](revenue.copy())),
        ]
    )
    var panels = scatter_facets(
        campaigns,
        x="spend",
        y="revenue",
        facet="region",
        color="product",
        facet_order=["North", "South", "East"],
        color_order=["Product A", "Product B"],
        width=320,
        height=260,
    )
    save_facets(
        panels,
        2,
        "docs/src/examples/out_dataframe_grouped_facets.svg",
        shared_y_scale=True,
    )
