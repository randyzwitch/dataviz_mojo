"""Ready-made dark, minimal, high-contrast, and print-safe themes.

```mojo
from dataviz.plot import Plot, save
from dataviz.themes import dark

var plot = Plot().mark_line().encode(x=x, y=y).theme(dark())
```

Preset fields can be overridden before applying the theme:

```mojo
var t = dark()
t.mark_color = CORNFLOWERBLUE
t.show_gridlines = False
var plot = Plot().mark_line().encode(x=x, y=y).theme(t)
```

Presets do not compose. Choose the closest preset and override its fields.
"""

from canvas.color import Color

from dataviz.color_ramp import ColorRamp
from dataviz.colormaps import cividis, viridis
from dataviz.colors import WHITE
from dataviz.line_style import LineStyle
from dataviz.theme import Theme


def dark() -> Theme:
    """Return a theme for charts on dark backgrounds.

    Returns:
        A `Theme` for a dark background, ready to override.
    """
    return Theme(
        background=Color(24, 26, 31),
        mark_color=Color(90, 165, 255),
        axis_color=Color(150, 154, 163),
        gridline_color=Color(52, 56, 64),
        text_color=Color(232, 234, 238),
        minor_gridline_color=Color(38, 41, 48),
        color_scale_low=Color(90, 150, 235),
        color_scale_mid=Color(74, 77, 84),
        color_scale_high=Color(244, 132, 80),
        mark_color_negative=Color(244, 120, 110),
        bullet_range_color_light=Color(46, 48, 54),
        bullet_range_color_dark=Color(112, 116, 124),
        waterfall_total_color=Color(150, 153, 160),
        radialbar_track_color=Color(52, 55, 62),
        radar_fill_alpha=170,
        subtitle_color=Color(158, 162, 172),
        annotation_color=Color(152, 156, 166),
        annotation_area_color=Color(64, 78, 100, 200),
        halo_alpha=170,
    )


def minimal() -> Theme:
    """Return a theme with reduced gridlines, ticks, and margins.

    Returns:
        A `Theme` with the chart furniture reduced, ready to override.
    """
    return Theme(
        axis_color=Color(170, 170, 170),
        text_color=Color(55, 55, 55),
        margin_left=46,
        margin_right=14,
        margin_top=14,
        margin_bottom=42,
        show_gridlines=False,
        minor_tick_length=2,
        subtitle_color=Color(135, 135, 135),
        annotation_color=Color(140, 140, 140),
        tick_length=3,
        label_gap=3,
        margin_buffer=6,
        gridline_style=LineStyle.DOTTED,
        annotation_line_style=LineStyle.DASHED,
    )


def high_contrast() -> Theme:
    """Return a high-contrast theme with larger text and marks.

    Returns:
        A high-contrast `Theme`, ready to override.
    """
    return Theme(
        mark_color=Color(0, 84, 166),
        axis_color=Color(0, 0, 0),
        gridline_color=Color(120, 120, 120),
        text_color=Color(0, 0, 0),
        font_size=14.0,
        point_radius=5.0,
        line_width=3.0,
        margin_left=70,
        margin_right=24,
        margin_top=24,
        margin_bottom=58,
        minor_gridline_color=Color(178, 178, 178),
        color_scale_low=Color(0, 84, 166),
        color_scale_mid=Color(240, 240, 240),
        color_scale_high=Color(166, 42, 0),
        color_ramp=cividis(),
        mark_color_negative=Color(166, 42, 0),
        bullet_range_color_light=Color(238, 238, 238),
        bullet_range_color_dark=Color(72, 72, 72),
        waterfall_total_color=Color(48, 48, 48),
        radialbar_track_color=Color(214, 214, 214),
        shape_by_category=True,
        title_font_size=22.0,
        subtitle_font_size=16.0,
        subtitle_color=Color(58, 58, 58),
        axis_title_font_size=16.0,
        annotation_color=Color(64, 64, 64),
        annotation_area_color=Color(168, 194, 222, 200),
        tick_length=7,
        legend_width=155,
        legend_swatch_size=18,
        margin_buffer=10,
        gridline_style=LineStyle.DOTTED,
        annotation_line_style=LineStyle.DASHED,
    )


def print_safe() -> Theme:
    """Return a grayscale-safe theme using lightness and line patterns.

    Returns:
        A grayscale-safe `Theme`, ready to override.
    """
    return Theme(
        background=WHITE,
        mark_color=Color(25, 25, 25),
        axis_color=Color(60, 60, 60),
        gridline_color=Color(206, 206, 206),
        text_color=Color(20, 20, 20),
        minor_gridline_color=Color(230, 230, 230),
        color_scale_low=Color(30, 30, 30),
        color_scale_mid=Color(128, 128, 128),
        color_scale_high=Color(235, 235, 235),
        color_ramp=viridis(),
        mark_color_negative=Color(170, 170, 170),
        bullet_range_color_light=Color(232, 232, 232),
        bullet_range_color_dark=Color(96, 96, 96),
        waterfall_total_color=Color(100, 100, 100),
        radialbar_track_color=Color(228, 228, 228),
        shape_by_category=True,
        subtitle_color=Color(95, 95, 95),
        annotation_color=Color(120, 120, 120),
        annotation_area_color=Color(210, 210, 210, 200),
        gridline_style=LineStyle.DOTTED,
        annotation_line_style=LineStyle.DASHED,
    )
