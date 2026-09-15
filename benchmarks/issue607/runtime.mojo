"""Untimed warmup, then individual render samples for two marks/backends."""
from std.time import perf_counter
from std.math import sin, cos
from dataviz import Plot, line, hexbin, render, render_svg, render_pdf


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
        var warm_p = render_pdf(plots[i])
        check += warm_r.width + warm_s.width + warm_p.width
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
            t = perf_counter()
            var pdf = render_pdf(plots[i])
            elapsed = perf_counter() - t
            check += pdf.width
            print(i, "pdf", elapsed)
    print("check", check)
