"""The resolved color, shape and size channels of a point mark, built
once per render so the legend reservation and the point layer agree."""

from canvas.color import Color

from dataviz.core.color_scale import (
    ColorScale,
    _ColorDomainOverride,
    _color_scale_for,
    categorical_palette_for,
)
from dataviz.core.frame import _CategoricalIndex, _categorical_indices
from dataviz.core.marker import PointShape, default_marker_shapes
from dataviz.core.plot_fields import _ChannelData
from dataviz.core.scale import LinearScale, MinMax, _min_max
from dataviz.core.text import _Scaled
from dataviz.core.theme import Theme


struct _PointChannels(Movable):
    """Every derived value `Mark.POINT`'s optional data-driven channels
    (categorical color, continuous color, continuous size; see
    `Plot.encode`) need: which are encoded, the categorical domain and
    palette a discrete color column indexes into, and the `ColorScale`/
    `LinearScale` a continuous column maps through. Built
    unconditionally, with placeholder scales when a channel isn't
    encoded.

    A struct because these are needed at two points in one render:
    before the plot rect is finalized, to size the legend column
    (`_legend_reserve_for`), and after, to color/size each point and draw
    the legend (`_draw_point_layer`). Computing them once keeps the two
    consistent.
    """

    var has_color: Bool
    var has_color_categories: Bool
    var has_size: Bool
    # The categorical color column's domain and each row's index into it,
    # resolved once (`_categorical_indices`). Held as the whole
    # `_CategoricalIndex` since Mojo won't let a returned struct's fields
    # be moved out individually. Both halves are empty when the channel
    # isn't encoded.
    var cat: _CategoricalIndex
    # One color per `cat.domain` entry, sized to the domain exactly with
    # `Plot.encode()`'s `color_map` overrides folded in, so readers index
    # it directly by domain position.
    var palette: List[Color]
    # One shape per `cat.domain` entry, same indexing as `palette`; empty
    # unless both `has_color_categories` and `Theme.shape_by_category` are
    # true. `has_shapes` names that combination.
    var has_shapes: Bool
    var shapes: List[PointShape]
    var color_scale: ColorScale
    var size_mm: MinMax
    var size_scale: LinearScale

    def __init__(
        out self,
        channels: _ChannelData,
        theme: Theme,
        color_domain: _ColorDomainOverride,
        sc: _Scaled,
    ) raises:
        self.has_color = len(channels.color) > 0
        self.has_color_categories = len(channels.color_categories) > 0
        self.has_size = len(channels.size) > 0
        # Branch rather than resolving an empty column: `channels` is borrowed, so
        # a ternary would need a full copy of `color_categories`.
        if self.has_color_categories:
            self.cat = _categorical_indices(channels.color_categories)
        else:
            self.cat = _CategoricalIndex(List[String](), List[Int]())
        self.palette = List[Color]()
        if self.has_color_categories:
            var default_palette = categorical_palette_for(theme)
            for i in range(len(self.cat.domain)):
                var name = self.cat.domain[i]
                if name in channels.color_map:
                    self.palette.append(channels.color_map[name])
                else:
                    self.palette.append(
                        default_palette[i % len(default_palette)]
                    )
        self.has_shapes = self.has_color_categories and theme.shape_by_category
        self.shapes = List[PointShape]()
        if self.has_shapes:
            var default_shapes = default_marker_shapes()
            for i in range(len(self.cat.domain)):
                # By name first, by position otherwise -- the same rule
                # the palette above follows, so a figure can pin both
                # channels the same way (#365).
                var name = self.cat.domain[i]
                if name in channels.shape_map:
                    self.shapes.append(channels.shape_map[name])
                else:
                    self.shapes.append(default_shapes[i % len(default_shapes)])
        var color_mm = _min_max(channels.color) if self.has_color else MinMax(
            0.0, 1.0
        )
        # Only a numeric color channel has a domain for an override to
        # act on; a categorical or absent one leaves the scale unused, so
        # asking `_color_scale_for` about it would raise over a setting
        # `_validate_color_domain` has already refused for this plot.
        self.color_scale = _color_scale_for(
            theme, color_domain, color_mm.min, color_mm.max
        ) if self.has_color else ColorScale.from_theme(
            theme, color_mm.min, color_mm.max
        )
        self.size_mm = _min_max(channels.size) if self.has_size else MinMax(
            0.0, 1.0
        )
        self.size_scale = LinearScale(
            self.size_mm.min,
            self.size_mm.max,
            sc.size_range_min,
            sc.size_range_max,
        )
