"""`Mark.DENDROGRAM`: the merge tree agglomerative clustering produces,
drawn as brackets (#355).

Each leaf sits in its own band along the category axis, in the order the
tree implies, and each merge is a bracket whose crossbar sits at the
height the two clusters joined. Reading it: the lower a bracket, the
more alike the things under it, and cutting straight across at any
height gives the clusters at that level.

The layout is the same categorical frame a bar chart uses, which is what
puts the leaf labels where a reader expects them and lets a dendrogram
sit beside a heatmap of the same rows with the two lined up.

`dataviz.core.cluster` owns the numbers; nothing here decides what is
close to what.
"""

from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.cluster import (
    DistanceMetric,
    Linkage,
    linkage,
)
from dataviz.categorical.gantt import (
    _draw_horizontal_categorical_axis_frame,
)
from dataviz.core.frame import _draw_categorical_axis_frame
from dataviz.core.ordinal_scale import OrdinalScale
from dataviz.core.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.core.theme import Theme
from dataviz.plot import Plot, _RenderResult, _finished


def _dendrogram_bracket_label(height: Float64) -> String:
    """One merge's hover text (#681): the linkage distance the bracket's
    crossbar sits at -- the one number the axis only gives approximately."""
    return "height: " + _format_fixed(height, _label_decimals(height))


struct _DendrogramData(Copyable, Movable):
    """`Mark.DENDROGRAM`'s tree, flattened.

    `labels` names the leaves in the order they are drawn, so it is
    already the clustered order rather than the caller's original one.
    The three merge lists are parallel: merge `k` joins nodes
    `left[k]` and `right[k]` at `height[k]`, where an id below
    `len(labels)` is a leaf's position along the axis and `len(labels)
    + j` is merge `j`'s own node.
    """

    var left: List[Int]
    var right: List[Int]
    var height: List[Float64]
    var labels: List[String]
    var horizontal: Bool
    """Draw the leaves down the y-axis with the brackets reaching
    right, for a dendrogram that sits beside a matrix's rows rather
    than above its columns."""

    def __init__(out self):
        """An empty tree, for a `Plot` that is not a dendrogram."""
        self.left = List[Int]()
        self.right = List[Int]()
        self.height = List[Float64]()
        self.labels = List[String]()
        self.horizontal = False


def _node_positions(
    data: _DendrogramData,
    mut pos: List[Float64],
    mut hgt: List[Float64],
):
    """Every node's position along the leaf axis and its height.

    A leaf sits at its own index; an internal node sits midway between
    its two children, which is what makes a bracket symmetric about what
    it joins. One forward pass is enough because the merges are sorted
    so a node's children always come first.

    Args:
        data: The tree.
        pos: Filled with each node's position along the leaf axis,
            leaves first then merges.
        hgt: Filled with each node's height, in the same order.
    """
    var n = len(data.labels)
    for i in range(n):
        pos.append(Float64(i))
        hgt.append(0.0)
    for k in range(len(data.height)):
        var l = data.left[k]
        var r = data.right[k]
        pos.append((pos[l] + pos[r]) * 0.5)
        hgt.append(data.height[k])


def _render_dendrogram[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.DENDROGRAM` plot: one bracket per merge over the
    categorical frame every leaf-labeled mark shares.

    A bracket is one path of four points -- up from the left child, across
    at the merge height, down to the right child -- stroked rather than
    drawn as three segments, so the corners meet cleanly instead of
    showing the pale seams two antialiased ends leave where they
    overlap.

    Args:
        target: The draw target.
        plot: The chart.
        ox0: Left bound.
        oy0: Top bound.
        ox1: Right bound.
        oy1: Bottom bound.
        cache: Shared font cache.

    Returns:
        The finished render.

    Raises:
        Error: The tree is empty or malformed.
    """
    ref data = plot._dendrogram
    _validate_dendrogram(plot)
    var theme = plot._theme
    var tallest = 0.0
    for h in data.height:
        if h > tallest:
            tallest = h
    # A hair of headroom so the root's crossbar is not drawn on the
    # frame itself, and a floor so a tree of identical rows still has an
    # axis rather than a zero-span one.
    var top = tallest * 1.05 if tallest > 0.0 else 1.0
    var pos = List[Float64]()
    var hgt = List[Float64]()
    _node_positions(data, pos, hgt)
    if data.horizontal:
        # Leaves down the y-axis, heights running right: the form that
        # sits beside a matrix's rows. Same tree, same brackets, the two
        # axes swapped.
        var hframe = _draw_horizontal_categorical_axis_frame(
            target,
            data.labels,
            LinearScale(0.0, top, 0.0, 1.0),
            theme,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )
        for k in range(len(data.height)):
            var l = data.left[k]
            var r = data.right[k]
            var bar = hframe.x_scale.to_pixel(data.height[k])
            var bracket = _bracket_path(
                _leaf_pixel(hframe.y_scale, pos[l]),
                hframe.x_scale.to_pixel(hgt[l]),
                _leaf_pixel(hframe.y_scale, pos[r]),
                hframe.x_scale.to_pixel(hgt[r]),
                bar,
                swap=True,
            )
            if theme.svg_tooltips:
                target.begin_annotated_group(
                    _dendrogram_bracket_label(data.height[k])
                )
            target.stroke_path_aa(
                bracket, theme.mark_color, width=hframe.sc.line_width
            )
            if theme.svg_tooltips:
                target.end_annotated_group()
        return hframe.result()
    var frame = _draw_categorical_axis_frame(
        target,
        data.labels,
        LinearScale(0.0, top, 0.0, 1.0),
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    for k in range(len(data.height)):
        var l = data.left[k]
        var r = data.right[k]
        var bar = frame.y_scale.to_pixel(data.height[k])
        var bracket = _bracket_path(
            _leaf_pixel(frame.x_scale, pos[l]),
            frame.y_scale.to_pixel(hgt[l]),
            _leaf_pixel(frame.x_scale, pos[r]),
            frame.y_scale.to_pixel(hgt[r]),
            bar,
        )
        if theme.svg_tooltips:
            target.begin_annotated_group(
                _dendrogram_bracket_label(data.height[k])
            )
        target.stroke_path_aa(
            bracket, theme.mark_color, width=frame.sc.line_width
        )
        if theme.svg_tooltips:
            target.end_annotated_group()
    return frame.result()


def _leaf_pixel(scale: OrdinalScale, position: Float64) -> Float64:
    """The pixel a node's position along the leaf axis lands on.

    A leaf's position is a whole index, which the ordinal scale can
    place directly; an internal node's is halfway between two of them,
    so it is interpolated between the two neighboring band centers
    rather than rounded to one of them.

    Args:
        scale: The leaf axis.
        position: The node's position, possibly fractional.

    Returns:
        The pixel.
    """
    var low = Int(position)
    var frac = position - Float64(low)
    if frac <= 0.0:
        return scale.center(low)
    return (
        scale.center(low) + (scale.center(low + 1) - scale.center(low)) * frac
    )


def _bracket_path(
    x_left: Float64,
    y_left: Float64,
    x_right: Float64,
    y_right: Float64,
    y_bar: Float64,
    swap: Bool = False,
) raises -> Path:
    """One merge's bracket: up from the left child, across at the merge
    height, down to the right child.

    One path rather than three strokes. Two antialiased segments meeting
    at a right angle each cover half of the corner pixel, and the result
    is a pale notch at every corner of every bracket; a single stroked
    path has no seam because there is nothing to meet.

    Args:
        x_left: The left child's pixel along the leaf axis.
        y_left: The left child's own height in pixels.
        x_right: The right child's pixel.
        y_right: The right child's height in pixels.
        y_bar: The merge height in pixels.
        swap: Exchange the two axes, for a tree drawn with its leaves
            down the y-axis.

    Returns:
        The path.

    Raises:
        Error: Whatever building the path raises.
    """
    var path = Path()
    if swap:
        path.move_to(y_left, x_left)
        path.line_to(y_bar, x_left)
        path.line_to(y_bar, x_right)
        path.line_to(y_right, x_right)
        return path^
    path.move_to(x_left, y_left)
    path.line_to(x_left, y_bar)
    path.line_to(x_right, y_bar)
    path.line_to(x_right, y_right)
    return path^


def _validate_dendrogram(plot: Plot) raises:
    """`Mark.DENDROGRAM`'s pre-draw checks.

    Args:
        plot: The chart.

    Raises:
        Error: No leaves, a merge count that does not match, or a node
            id outside the tree.
    """
    ref data = plot._dendrogram
    var n = len(data.labels)
    if n < 2:
        raise Error(
            "Mark.DENDROGRAM: needs at least two leaves -- got " + String(n)
        )
    if len(data.left) != len(data.right) or len(data.left) != len(data.height):
        raise Error(
            "Plot.encode_dendrogram(): left, right and height must have the"
            " same length -- got "
            + String(len(data.left))
            + ", "
            + String(len(data.right))
            + " and "
            + String(len(data.height))
        )
    if len(data.height) != n - 1:
        raise Error(
            "Plot.encode_dendrogram(): a tree over "
            + String(n)
            + " leaves has "
            + String(n - 1)
            + " merges -- got "
            + String(len(data.height))
        )
    for k in range(len(data.height)):
        var limit = n + k
        if (
            data.left[k] < 0
            or data.left[k] >= limit
            or data.right[k] < 0
            or data.right[k] >= limit
        ):
            raise Error(
                "Plot.encode_dendrogram(): merge "
                + String(k)
                + " names a node that does not exist yet -- ids must be a"
                " leaf (0 to "
                + String(n - 1)
                + ") or an earlier merge"
            )


def dendrogram(
    rows: List[List[Float64]],
    labels: List[String] = List[String](),
    metric: DistanceMetric = DistanceMetric.EUCLIDEAN,
    method: Linkage = Linkage.AVERAGE,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Cluster `rows` and draw the merge tree as brackets (#355).

    The chart for "what is like what" before deciding anything else: the
    lower two things join, the more alike they are, and a horizontal cut
    at any height reads off the clusters at that level. Leaves come out
    in the tree's own order, so things that group together sit together.

    Example:
        ```mojo
        from dataviz import dendrogram, save

        def main() raises:
            # Four cities' illustrative monthly rainfall, in mm.
            var rows: List[List[Float64]] = [
                [80.0, 70.0, 65.0, 55.0, 45.0, 30.0],
                [75.0, 68.0, 60.0, 52.0, 40.0, 28.0],
                [10.0, 12.0, 18.0, 30.0, 55.0, 70.0],
                [12.0, 15.0, 20.0, 34.0, 58.0, 75.0],
            ]
            var names: List[String] = [
                "Porto",
                "Bilbao",
                "Perth",
                "Adelaide",
            ]
            var c = dendrogram(
                rows,
                names,
                title="Rainfall profiles, clustered",
                y_title="Distance",
            )
            save(c, "docs/src/examples/out_dendrogram.svg")
        ```

    Args:
        rows: One list per thing being clustered, all the same length.
        labels: One name per row; empty numbers them from 0.
        metric: How far apart two rows are.
        method: How far apart two clusters are.
        theme: Full styling knobs beyond this function's own arguments.
        width: Canvas width in points.
        height: Canvas height in points.
        title: Chart title; empty for none.
        subtitle: Chart subtitle; empty for none.
        x_title: X-axis title; empty for none.
        y_title: Y-axis title; empty for none.

    Returns:
        The finished `Plot`, ready to `render()` or `save()`.

    Raises:
        Error: Fewer than two rows, a label count that does not match,
            or anything `linkage()` raises.
    """
    if len(labels) > 0 and len(labels) != len(rows):
        raise Error(
            "dendrogram(): one label per row, so "
            + String(len(rows))
            + " -- got "
            + String(len(labels))
        )
    var tree = linkage(rows, metric, method)
    var names = List[String](capacity=len(rows))
    for i in range(len(tree.leaf_order)):
        var source = tree.leaf_order[i]
        names.append(labels[source] if len(labels) > 0 else String(source))
    var plot = (
        Plot()
        .mark_dendrogram()
        .encode_dendrogram(tree, names, horizontal=False)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
