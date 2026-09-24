"""The hover text each kind of datum carries in SVG tooltips: a
category and value, a series, a point, an xyz triple, a cell, a span,
or an edge. Split out of plot.mojo, which imports every name here
back."""

from dataviz.core.mark import Mark
from dataviz.core.scale import _format_fixed, _label_decimals
from dataviz.core.plot_fields import _ChannelData


def _tooltip_label(category: String, value: Float64) -> String:
    """One datum's hover text: `"Group A: 42"`, formatted with
    `_label_decimals` like `Theme.show_data_labels`. No escaping here;
    canvas_mojo's `begin_annotated_group` escapes the title for XML
    itself.
    """
    return category + ": " + _format_fixed(value, _label_decimals(value))


def _series_tooltip_label(
    category: String, series: String, value: Float64
) -> String:
    """A grouped/stacked datum's hover text: `"Group A / Q1: 42"`. Both
    names, since one bar per (category, series) pair needs both to be
    identified.
    """
    return (
        category
        + " / "
        + series
        + ": "
        + _format_fixed(value, _label_decimals(value))
    )


def _point_tooltip_label(
    channels: _ChannelData,
    x_data: List[Float64],
    y_data: List[Float64],
    mark: Mark,
    i: Int,
) -> String:
    """One scatter point's hover text: the row's `encode(labels=...)` entry
    when it has one, otherwise its coordinates, `"3.5, 12"`.

    `Mark.SINGLE_AXIS` gets the value alone. It draws through this same
    layer but has no y channel -- `encode_single_axis()` leaves that
    column zero -- so the pair form read `"3.5, 0"` and reported a
    coordinate the chart does not have (#683).
    """
    if len(channels.point_labels) > 0 and channels.point_labels[i] != "":
        return channels.point_labels[i]
    var x = _format_fixed(x_data[i], _label_decimals(x_data[i]))
    if mark == Mark.SINGLE_AXIS:
        return x
    return x + ", " + _format_fixed(y_data[i], _label_decimals(y_data[i]))


def _xyz_tooltip_label(x: Float64, y: Float64, z: Float64) -> String:
    """One 3D datum's hover text, `"1, 2, 3"`: the same shape as
    `_point_tooltip_label`'s coordinate fallback with the third axis
    added (#683). A projected point is the case that needs a tooltip
    most -- two points that look adjacent on the page can be far apart
    along the view direction, and the title is the only way to tell.
    """
    return (
        _format_fixed(x, _label_decimals(x))
        + ", "
        + _format_fixed(y, _label_decimals(y))
        + ", "
        + _format_fixed(z, _label_decimals(z))
    )


def _cell_tooltip_label(
    first: String, second: String, value: Float64
) -> String:
    """One grid cell's hover text, `"Mon / 09:00: 42"`: both keys and
    the value, formatted like `_tooltip_label`'s single key (#679).

    A grid mark encodes its value as a color or a radius, so the cell
    is the one shape in the library a reader cannot get a number out of
    by looking. The title is what makes it readable.
    """
    return (
        first
        + " / "
        + second
        + ": "
        + _format_fixed(value, _label_decimals(value))
    )


def _span_tooltip_label(
    category: String, start: Float64, end: Float64
) -> String:
    """A bar that spans two values rather than reaching one, as a
    Gantt row does: `"deploy: 3 to 7"` (#677). `_tooltip_label`'s
    single number cannot say what this bar encodes -- its length is
    the datum, and either end alone loses half of it.
    """
    return (
        category
        + ": "
        + _format_fixed(start, _label_decimals(start))
        + " to "
        + _format_fixed(end, _label_decimals(end))
    )


def _edge_tooltip_label(
    source: String, target_name: String, value: Float64
) -> String:
    """One edge's hover text, `"Coal -> Power: 42"` (#682).

    The relationship marks draw every node's name as visible text
    already; what no edge shows is its weight, and the weight is the
    whole of what the ribbon's thickness encodes. So the title goes on
    the edges rather than repeating a name that is on the page a
    centimetre away.

    An ASCII arrow, matching the plain-text style the rest of the
    package writes in.
    """
    return (
        source
        + " -> "
        + target_name
        + ": "
        + _format_fixed(value, _label_decimals(value))
    )
