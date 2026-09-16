# title: Mathematical Labels
"""Write a title, axis caption, legend entry or annotation as an expression -- subscripts, superscripts, Greek letters and a fraction -- by wrapping it in `$...$`.

Inside the dollars, Latin letters are set italic as variables and
everything else upright; `^` and `_` attach scripts, `\\frac{a}{b}`
stacks a fraction, and `\\alpha`, `\\sigma`, `\\Delta` and the like
name Greek letters. A lone `$`, as in a price, is left alone; write
`\\$` for a literal one next to math. Space a label needs above or
below the line is measured and reserved, so a fraction in a title is
not clipped by a band sized for one line of text.
"""
from std.math import exp

from dataviz import Plot, save


def main() raises:
    # Illustrative decay: samples of exp(-t / tau) at two half-lives.
    var t = List[Float64]()
    var fast = List[Float64]()
    var slow = List[Float64]()
    for i in range(25):
        var ti = Float64(i) * 0.25
        t.append(ti)
        fast.append(exp(-ti / 1.5))
        slow.append(exp(-ti / 4.0))
    var series = List[String]()
    for _ in range(25):
        series.append("$\\tau_1 = 1.5$")
    var both_t = List[Float64]()
    var both_y = List[Float64]()
    for i in range(25):
        both_t.append(t[i])
        both_y.append(fast[i])
    for i in range(25):
        both_t.append(t[i])
        both_y.append(slow[i])
        series.append("$\\tau_2 = 4$")

    var plot = (
        Plot()
        .mark_point()
        .encode(x=both_t, y=both_y, color_categories=series)
        .labels(
            title="Decay $N(t) = N_0 \\, e^{-t/\\tau}$",
            x_title="$t$ (s)",
            y_title="$\\frac{N(t)}{N_0}$",
        )
        .annotate_point(1.5, exp(-1.0), label="$t = \\tau_1$")
    )
    save(plot, "docs/src/examples/out_math_labels.svg")
