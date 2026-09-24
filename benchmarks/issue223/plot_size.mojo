"""Plot's size and copy cost, for #223: `size_of[Plot]()` and the median
time to copy a small line plot and a small 3D surface plot 20,000 times.
Run against the baseline and the prototype tree."""

from std.sys import size_of
from std.time import perf_counter_ns

from dataviz.plot import (Plot)


def _copies(plot: Plot, n: Int) -> Int:
    var total = 0
    var t0 = perf_counter_ns()
    for _ in range(n):
        var c = plot.copy()
        total += c.width
    var t1 = perf_counter_ns()
    if total == 0:
        print("unreachable")
    return Int(t1 - t0)


def _median_ns_per_copy(plot: Plot) -> Float64:
    var n = 20000
    var samples = List[Int]()
    for _ in range(5):
        samples.append(_copies(plot, n))
    sort(samples)
    return Float64(samples[2]) / Float64(n)


def main() raises:
    var xs: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var ys: List[Float64] = [2.0, 4.0, 1.0, 3.0, 5.0]
    var line = Plot().mark_line().encode(x=xs, y=ys)
    var z: List[List[Float64]] = [[1.0, 2.0], [3.0, 4.0]]
    var surface = Plot().mark_surface3d().encode_surface(z)
    print("size_of[Plot]:", size_of[Plot]())
    print("copy line plot, ns:", _median_ns_per_copy(line))
    print("copy surface3d plot, ns:", _median_ns_per_copy(surface))
