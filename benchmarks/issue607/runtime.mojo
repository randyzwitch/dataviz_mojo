"""Untimed warmup, then individual render samples for two marks/backends."""
from std.time import perf_counter
from std.math import sin, cos
from dataviz import Plot, line, hexbin, render, render_svg


def main() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(128):
        x.append(Float64(i) / 128)
        y.append(sin(Float64(i)) + cos(Float64(i) / 7))
    var plots = List[Plot]()
    plots.append(line(x, y))
    plots.append(hexbin(x, y))
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
