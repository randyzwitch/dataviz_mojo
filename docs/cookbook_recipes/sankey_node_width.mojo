"""Widen a Sankey diagram's own node bars -- the default width reads
as a thin accent next to wide flows, but a chart built to emphasize
the nodes themselves (not just the flows between them) benefits from
a heavier bar.
"""
from dataviz import sankey
from dataviz.plot import save


def main() raises:
    var from_categories: List[String] = [
        "Visits",
        "Visits",
        "Signups",
        "Signups",
    ]
    var to_categories: List[String] = [
        "Signups",
        "Bounced",
        "Purchased",
        "Churned",
    ]
    var values: List[Float64] = [420.0, 580.0, 260.0, 160.0]

    var plot = sankey(
        from_categories,
        to_categories,
        values,
        node_width=28.0,
        title="Funnel Flow",
    )
    save(plot, "docs/src/examples/out_sankey_node_width.svg")
