# title: Comparing Distributions (KDE + Rug)
"""Layer two KDE curves and a rug on one shared density axis for direct
comparison."""
from dataviz.colors import CORNFLOWERBLUE, TOMATO
from dataviz.kde import kdeplot, rugplot
from dataviz.plot import Plot, save_layers
from dataviz.theme import Theme


def main() raises:
    var control: List[Float64] = [
        12.0,
        14.0,
        15.0,
        15.0,
        16.0,
        16.0,
        17.0,
        18.0,
        19.0,
        21.0,
    ]
    var treatment: List[Float64] = [
        18.0,
        20.0,
        21.0,
        22.0,
        22.0,
        23.0,
        24.0,
        26.0,
        28.0,
        31.0,
    ]

    var control_curve = (
        Plot()
        .mark_kde(fill=True)
        .encode_kde(values=control)
        .theme(Theme(mark_color=CORNFLOWERBLUE))
        .series_name("Control")
        .labels(
            title="Response time by group",
            x_title="Milliseconds",
            y_title="Density",
        )
        .size(640, 400)
    )
    var treatment_curve = (
        Plot()
        .mark_kde()
        .encode_kde(values=treatment)
        .theme(Theme(mark_color=TOMATO, line_width=2.5))
        .series_name("Treatment")
        .size(640, 400)
    )
    # The rug rides the shared frame: its ticks land on the combined
    # x-scale, not on one of its own.
    var observations = (
        Plot()
        .mark_rug()
        .encode_kde(values=treatment)
        .theme(Theme(mark_color=TOMATO))
        .size(640, 400)
    )

    var plots: List[Plot] = [control_curve^, treatment_curve^, observations^]
    save_layers(plots, "docs/src/examples/out_kde_comparison.svg")
