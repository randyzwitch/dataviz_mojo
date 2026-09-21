"""Splitting a frame into one sub-frame per level, for facets (#364)."""

from dataframe import DataFrame

from dataviz.core.frame_input import (
    _frame_floats,
    _frame_strings,
    _is_string_column,
)
from dataviz.core.missing import Missing


struct FacetPart(Copyable, Movable):
    """One level of a faceting column: its name, and the rows that carry
    it.

    The name is what a panel is titled by, and the frame is what a
    panel is drawn from, so a facet is two lines of caller code rather
    than a new overload per mark.
    """

    var name: String
    """The level, as it appears in the column. A row whose level is
    missing is gathered under `Theme.missing_category_label`."""
    var frame: DataFrame
    """That level's rows, in the order the table had them."""

    def __init__(out self, var name: String, var frame: DataFrame):
        self.name = name^
        self.frame = frame^


def facet_by(
    df: DataFrame,
    column: String,
    missing: Missing = Missing.DRAW,
    label: String = "(missing)",
) raises -> List[FacetPart]:
    """Split `df` into one part per distinct value of `column`, in
    first-appearance order (#364).

    This is what a faceted figure needs and what a plotting call cannot
    express: every mark already takes a frame, so a facet is a loop over
    the parts rather than a facet-shaped variant of each of the 78
    one-call functions.

    ```mojo
    var panels = List[Plot]()
    for part in facet_by(sales, "region"):
        panels.append(
            scatter(part.frame, x="spend", y="revenue", title=part.name)
        )
    save_facets(panels, 2, "by-region.png")
    ```

    Panels drawn this way have **independent domains**, because each is
    scaled from its own rows. When the comparison between panels is the
    point, pass the pooled extent to each panel's
    `scale_x_domain()`/`scale_y_domain()` -- `pooled_extent()` below
    computes it -- or hand the panels to
    `render_facets(shared_y_scale=True)`.

    The faceting column may be strings or numbers; numbers are named by
    their own formatting, which is what a reader sees on the panel.

    Args:
        df: The frame to split.
        column: The column whose distinct values become the parts.
        missing: The policy in force (`Theme.missing`).
        label: What an absent level is called
            (`Theme.missing_category_label`).

    Returns:
        One part per level, in first-appearance order.

    Raises:
        Error: No column of that name, or, under `Missing.RAISE`, a row
            whose level is absent.
    """
    comptime caller = "facet_by()"
    var levels: List[String]
    if _is_string_column(df, column):
        levels = _frame_strings(df, column, caller, missing, label)
    else:
        var numbers = _frame_floats(df, column, caller, missing)
        levels = List[String](capacity=len(numbers))
        for v in numbers:
            levels.append(String(v))

    var names = List[String]()
    var rows = List[List[Int]]()
    for i in range(len(levels)):
        var at = -1
        for k in range(len(names)):
            if names[k] == levels[i]:
                at = k
                break
        if at < 0:
            names.append(levels[i])
            rows.append(List[Int]())
            at = len(names) - 1
        rows[at].append(i)

    var parts = List[FacetPart]()
    for k in range(len(names)):
        parts.append(FacetPart(names[k], df.take(rows[k])))
    return parts^


def pooled_extent(
    df: DataFrame, column: String, missing: Missing = Missing.DRAW
) raises -> Tuple[Float64, Float64]:
    """The `(low, high)` of a numeric column over the **whole** frame,
    for giving every facet panel the same axis.

    A panel scaled from its own rows says nothing about the panel beside
    it: two peaks of different heights can be drawn the same size. Pass
    this to each panel's `scale_x_domain()` or `scale_y_domain()` and
    the comparison a faceted figure invites becomes a fair one.

    Missing values take no part, as everywhere else (#367).

    Args:
        df: The whole frame, before splitting.
        column: The numeric column to measure.
        missing: The policy in force (`Theme.missing`).

    Returns:
        The lowest and highest present value.

    Raises:
        Error: No such column, it is not numeric, or every value is
            missing.
    """
    var values = _frame_floats(df, column, "pooled_extent()", missing)
    var lo = Float64.MAX
    var hi = -Float64.MAX
    var seen = 0
    for v in values:
        if v != v:
            continue
        if v < lo:
            lo = v
        if v > hi:
            hi = v
        seen += 1
    if seen == 0:
        raise Error(
            'pooled_extent(): every value in "'
            + column
            + '" is missing, so it has no extent'
        )
    return (lo, hi)
