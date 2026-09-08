"""Draw a series that holds constant between samples as a staircase
rather than a slope, and choose where each step falls with `StepStyle`.

A straight segment between two samples claims the value moved smoothly
from one to the other. For a quantity that changes at discrete moments
and holds in between -- a policy rate, a price tier, a headcount, an
inventory level -- that is a claim the data does not support, and the
slope invents readings at every x in between.

The three styles differ only in where the riser sits relative to the
samples, which is easier to tell apart by eye than by description:
`PRE` steps up as soon as the previous sample ends, `POST` holds the old
value until the new sample's x, and `MID` splits the difference. `PRE`
and `POST` disagree by a whole interval about when a change happened, so
the choice is a statement about the data, not a style preference.

Note `Theme.line_smoothing` and a non-`NONE` step are mutually
exclusive and raise together: a staircase has nothing meaningful to
curve through.
"""
from dataviz import StepStyle
from dataviz.colors import CORNFLOWERBLUE, SEAGREEN, TOMATO
from dataviz.plot import Plot, save_facets
from dataviz.theme import Theme


def main() raises:
    # A central-bank policy rate: it holds flat between meetings and
    # moves only on the day of a decision, which is exactly the shape a
    # straight interpolation misrepresents.
    var meeting: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var rate: List[Float64] = [0.5, 0.5, 1.25, 2.0, 2.0, 3.25]

    var pre = (
        Plot()
        .size(320, 240)
        .mark_line(step=StepStyle.PRE)
        .encode(x=meeting, y=rate)
        .labels(title="PRE", y_title="Rate (%)")
        .theme(Theme(mark_color=CORNFLOWERBLUE))
    )
    var mid = (
        Plot()
        .size(320, 240)
        .mark_line(step=StepStyle.MID)
        .encode(x=meeting, y=rate)
        .labels(title="MID", y_title="Rate (%)")
        .theme(Theme(mark_color=SEAGREEN))
    )
    var post = (
        Plot()
        .size(320, 240)
        .mark_line(step=StepStyle.POST)
        .encode(x=meeting, y=rate)
        .labels(title="POST", y_title="Rate (%)")
        .theme(Theme(mark_color=TOMATO))
    )
    # NONE is the default straight interpolation, shown alongside so the
    # difference is visible rather than asserted.
    var none = (
        Plot()
        .size(320, 240)
        .mark_line()
        .encode(x=meeting, y=rate)
        .labels(title="NONE (default)", y_title="Rate (%)")
        .theme(Theme(mark_color=CORNFLOWERBLUE))
    )

    var plots: List[Plot] = [pre^, mid^, post^, none^]
    save_facets(plots, 2, "docs/src/examples/out_step_interpolation.svg")
