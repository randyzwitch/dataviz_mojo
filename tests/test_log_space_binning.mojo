"""HEXBIN and HIST2D bin in log space on a log axis (#718).

Bins of equal width in data units are wildly unequal on a log axis, so a
bin's area stops meaning anything. Both marks now bin in `log10` space
when the axis is logarithmic.

The discriminating sample is log-uniform: spread evenly across decades.
Binned in log space it fills the bins about evenly. Binned in linear
units, the first bin swallows nearly every decade but the last, which
is the distortion this fixes.
"""

from std.testing import TestSuite, assert_raises, assert_true

from dataviz.binned.hexbin import hexbin
from dataviz.binned.hist2d import hist2d
from dataviz.binned.histogram import bin_edges, log_bin_edges
from dataviz.plot import Plot, render, render_svg


def _log_uniform(n: Int) -> List[Float64]:
    """Values spread evenly across three decades, 1 to 1000."""
    var out = List[Float64]()
    var seed = 20260918
    for _ in range(n):
        seed = (seed * 1103515245 + 12345) % 2147483648
        out.append(10.0 ** (3.0 * Float64(seed % 100000) / 100000.0))
    return out^


def _spread(n: Int) -> List[Float64]:
    var out = List[Float64]()
    var seed = 424242
    for _ in range(n):
        seed = (seed * 1103515245 + 12345) % 2147483648
        out.append(1.0 + Float64(seed % 1000) / 100.0)
    return out^


def _max_count(svg: String) raises -> Int:
    """The fullest bin, read from the `count: N` tooltips."""
    var best = 0
    var rest = svg
    while True:
        var at = rest.find("count: ")
        if at == -1:
            break
        var start = at + 7
        var end = start
        while end < rest.byte_length():
            var ch = String(rest[byte = end : end + 1])
            if ch < "0" or ch > "9":
                break
            end += 1
        var n = Int(String(rest[byte=start:end]))
        if n > best:
            best = n
        var tail = String(rest[byte=end:])
        rest = tail
    return best


def test_hexbin_spreads_a_log_uniform_sample_evenly_on_a_log_axis() raises:
    var x = _log_uniform(3000)
    var y = _spread(3000)
    var logged = _max_count(
        render_svg(hexbin(x, y, gridsize=12).scale_x_log()).to_string()
    )
    var linear = _max_count(render_svg(hexbin(x, y, gridsize=12)).to_string())
    assert_true(logged > 0 and linear > 0, "no count tooltips found")
    # Linear bins pile the first two decades into the leftmost column,
    # so its fullest cell is several times a log-binned one.
    assert_true(
        linear > 3 * logged,
        (
            "the fullest cell holds "
            + String(logged)
            + " binned in log space and "
            + String(linear)
            + " in linear units; linear binning should crowd far more into"
            " one cell"
        ),
    )


def test_log_bin_edges_span_equal_ratios() raises:
    var e = log_bin_edges(_log_uniform(500), 6)
    var ratio = e[1] / e[0]
    for i in range(2, len(e)):
        assert_true(
            abs(e[i] / e[i - 1] - ratio) < 1e-9 * ratio,
            "log_bin_edges are not equal ratios",
        )


def test_hist2d_log_x_bins_in_log_space() raises:
    var x = _log_uniform(2000)
    var y = _spread(2000)
    var plot = hist2d(x, y, 10, log_x=True)
    var e = plot._image.x_edges.copy()
    var ratio = e[1] / e[0]
    for i in range(2, len(e)):
        assert_true(
            abs(e[i] / e[i - 1] - ratio) < 1e-9 * ratio,
            "hist2d(log_x=True) x edges are not even in log space",
        )
    _ = render(plot)


def test_hist2d_refuses_a_log_axis_over_its_own_linear_bins() raises:
    # The trap this closes: hist2d() chose linear bins, and a log axis
    # added afterwards would draw them wildly unequal without a word.
    with assert_raises(contains="Pass log_x=True"):
        _ = render(hist2d(_log_uniform(200), _spread(200), 8).scale_x_log())


def test_hist2d_draws_caller_edges_on_a_log_axis() raises:
    # Edges a caller gives are theirs, linear or not, and drawn as given.
    var x = _log_uniform(200)
    var y = _spread(200)
    _ = render(
        Plot()
        .mark_hist2d()
        .encode_hist2d(x, y, log_bin_edges(x, 8), bin_edges(y, 8))
        .scale_x_log()
    )


def test_hexbin_refuses_symlog() raises:
    with assert_raises(contains="takes scale_x_log() only"):
        _ = render(hexbin(_log_uniform(50), _spread(50)).scale_x_symlog())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
