"""Splitting a frame into one sub-frame per level, for facets (#364)."""

from dataframe import DataFrame

from dataviz.core.color_scale import shared_color_map
from dataviz.plot import Plot
from dataviz.core.theme import Theme

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


def _check_level_order(
    observed: List[String], requested: List[String], caller: String
) raises:
    """Explicit orders may reserve absent levels, but must name every present one.
    """
    for i in range(len(requested)):
        for j in range(i):
            if requested[i] == requested[j]:
                raise Error(
                    caller + ': duplicate level "' + requested[i] + '" in order'
                )
    for name in observed:
        var found = False
        for candidate in requested:
            if candidate == name:
                found = True
                break
        if not found:
            raise Error(caller + ': level "' + name + '" is missing from order')


def facet_by(
    df: DataFrame,
    column: String,
    missing: Missing = Missing.DRAW,
    label: String = "(missing)",
    order: List[String] = List[String](),
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
        order: Optional panel order. It must name every observed level;
            absent levels are reserved but do not create empty panels.

    Returns:
        One part per level, in first-appearance order.

    Raises:
        Error: No column of that name, or, under `Missing.RAISE`, a row
            whose level is absent.
    """
    comptime caller = "facet_by()"
    var levels: List[String]
    if _is_string_column(df, column, caller):
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
    if len(order) > 0:
        _check_level_order(names, order, caller)
        for name in order:
            for k in range(len(names)):
                if names[k] == name:
                    parts.append(FacetPart(names[k], df.take(rows[k])))
                    break
    else:
        for k in range(len(names)):
            parts.append(FacetPart(names[k], df.take(rows[k])))
    return parts^


def scatter_facets(
    df: DataFrame,
    x: String,
    y: String,
    facet: String,
    color: String = "",
    facet_order: List[String] = List[String](),
    color_order: List[String] = List[String](),
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
) raises -> List[Plot]:
    """Build grouped scatter panels from named DataFrame columns (#364).

    Each facet receives its own rows, title, and x/y column labels. A
    string `color` column groups points, with one color map shared by all
    panels even when a group is absent from some. `facet_order` and
    `color_order` make panel and group colors independent of row order.
    Pass the returned plots to `render_facets()` or `save_facets()`.

    Args:
        df: The source frame.
        x: Numeric x column.
        y: Numeric y column.
        facet: String or numeric panel column.
        color: Optional string group column.
        facet_order: Optional explicit panel order.
        color_order: Optional explicit group-color order.
        theme: Styling applied to every panel.
        width: Width of each panel.
        height: Height of each panel.

    Returns:
        One plot per present facet level.

    Raises:
        Error: Unknown or wrong-type columns, mismatched lengths, or an
            explicit order missing an observed level.
    """
    comptime caller = "scatter_facets()"
    if color.byte_length() == 0 and len(color_order) > 0:
        raise Error(caller + ": color_order requires a color column")
    var parts = facet_by(
        df, facet, theme.missing, theme.missing_category_label, facet_order
    )
    var colors = List[List[String]]()
    if color.byte_length() > 0:
        var whole = _frame_strings(
            df, color, caller, theme.missing, theme.missing_category_label
        )
        if len(color_order) > 0:
            _check_level_order(whole, color_order, caller)
            colors.append(color_order.copy())
        else:
            colors.append(whole^)
    var mapping = shared_color_map(colors, theme)
    var out = List[Plot]()
    for part in parts:
        var xs = _frame_floats(part.frame, x, caller, theme.missing)
        var ys = _frame_floats(part.frame, y, caller, theme.missing)
        if len(xs) != len(ys):
            raise Error(caller + ": x and y columns have different lengths")
        var plot = Plot().mark_point().theme(theme)
        if color.byte_length() > 0:
            var groups = _frame_strings(
                part.frame,
                color,
                caller,
                theme.missing,
                theme.missing_category_label,
            )
            if len(groups) != len(xs):
                raise Error(caller + ": color column has a different length")
            plot = plot^.encode(
                x=xs, y=ys, color_categories=groups, color_map=mapping
            )
        else:
            plot = plot^.encode(x=xs, y=ys)
        out.append(
            plot
            ^.labels(title=part.name, x_title=x, y_title=y).size(width, height)
        )
    return out^


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
