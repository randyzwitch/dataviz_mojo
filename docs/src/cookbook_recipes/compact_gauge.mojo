# title: Half-Circle Gauge
"""Sweep a gauge's dial across a flat-bottomed half circle instead of
the default three-quarter circle -- a shorter, wider dial that fits a
dashboard tile row better.
"""
from std.math import pi
from dataviz import gauge
from dataviz.plot import save
from dataviz.theme import Theme

def main() raises:
    var plot = gauge(
        72.0,
        theme=Theme(gauge_start_angle=pi, gauge_sweep_angle=pi),
        title="Server Load",
        width=400,
        height=260,
    )
    save(plot, "docs/src/examples/out_compact_gauge.svg")
