"""Untimed warmup, then individual render samples for four marks, three
of which read a payload struct per point or per cell (#223)."""

from std.math import cos, sin
from std.time import perf_counter

from dataviz import Plot, heatmap, hexbin, line, render, render_svg, scatter3d


def main() raises:
    var n = 2000
    var x = List[Float64]()
    var y = List[Float64]()
    var z = List[Float64]()
    for i in range(n):
        x.append(Float64(i) / Float64(n))
        y.append(sin(Float64(i)) + cos(Float64(i) / 7))
        z.append(cos(Float64(i) / 3))
    var side = 64
    var hx = List[String]()
    var hy = List[String]()
    var hv = List[Float64]()
    for r in range(side):
        for c in range(side):
            hx.append(String(c))
            hy.append(String(r))
            hv.append(sin(Float64(c) / 9) * cos(Float64(r) / 7))
    var plots = List[Plot]()
    plots.append(line(x, y))
    plots.append(hexbin(x, y))
    plots.append(scatter3d(x, y, z))
    plots.append(heatmap(hx, hy, hv))
    var check = 0
    for i in range(len(plots)):
        var warm_r = render(plots[i])
        var warm_s = render_svg(plots[i])
        check += warm_r.width + warm_s.width
        for _ in range(41):
            var t = perf_counter()
            var raster = render(plots[i])
            var elapsed = perf_counter() - t
            check += raster.width
            print(i, "raster", elapsed)
            t = perf_counter()
            var svg = render_svg(plots[i])
            elapsed = perf_counter() - t
            check += svg.width
            print(i, "svg", elapsed)
    print("check", check)
