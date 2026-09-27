"""Resolving a filled mark's per-name color and pattern (#848): the
chart's `fill_colors()`/`fill_patterns()` first, then the palette and the
pattern cycle by position.

One place so a renderer and its legend cannot disagree: each resolves
the whole list of names once and indexes it, and the legend is handed
the same two lists.
"""

from canvas.color import Color
from dataviz.core.chart_settings import _ChartSettings
from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.hatch import HatchStyle, _hatch_for_index


def _fill_palette(settings: _ChartSettings, names: List[String]) -> List[Color]:
    """One color per name: its `fill_colors()` entry, else the palette
    color for its position. With no names, the plain palette, so a
    caller indexing `i % len(palette)` never divides by zero."""
    var base = categorical_palette_for(settings.theme)
    if len(names) == 0:
        return base^
    var out = List[Color](capacity=len(names))
    for i in range(len(names)):
        var pinned = settings.fill_colors.get(names[i])
        if pinned:
            out.append(pinned.value())
        else:
            out.append(base[i % len(base)])
    return out^


def _fill_hatches(
    settings: _ChartSettings, names: List[String]
) -> List[HatchStyle]:
    """One pattern per name: its `fill_patterns()` entry, else the cycle's
    pattern for its position when `Theme.fill_pattern_by_category` is
    on, else `NONE`."""
    var out = List[HatchStyle](capacity=len(names))
    for i in range(len(names)):
        out.append(_fill_hatch(settings, names[i], i))
    return out^


def _fill_hatch(
    settings: _ChartSettings, name: String, index: Int
) -> HatchStyle:
    """`_fill_hatches` for one name at `index`."""
    var pinned = settings.fill_patterns.get(name)
    if pinned:
        return pinned.value()
    if settings.theme.fill_pattern_by_category:
        return _hatch_for_index(index)
    return HatchStyle.NONE
