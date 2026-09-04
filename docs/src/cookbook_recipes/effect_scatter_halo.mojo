"""Dim `Mark.EFFECT_SCATTER`'s glowing halo around each point -- the
default opacity reads as a clean bloom for a sparse scatter, but
overlapping halos on a denser one stack into an opaque blob.
"""
from dataviz import effect_scatter
from dataviz.plot import save
from dataviz.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 1.3, 1.6, 2.0, 2.3, 2.7, 3.0, 3.4, 3.8, 4.1]
    var y: List[Float64] = [
        12.0,
        13.5,
        12.8,
        15.0,
        14.2,
        16.5,
        15.8,
        17.0,
        16.2,
        18.5,
    ]

    var plot = effect_scatter(
        x,
        y,
        theme=Theme(halo_alpha=35),
        title="Cluster Readings",
        subtitle="A dimmer halo for dense, overlapping points",
    )
    save(plot, "docs/src/examples/out_effect_scatter_halo.svg")
