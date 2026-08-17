Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/theme.mojo)

# `Theme`

```mojo
@memory_only
struct Theme
```

## Fields

- **background** (`Color`)
- **mark_color** (`Color`)
- **axis_color** (`Color`)
- **gridline_color** (`Color`)
- **text_color** (`Color`)
- **font_size** (`Float64`)
- **point_radius** (`Float64`)
- **line_width** (`Float64`)
- **margin_left** (`Int`)
- **margin_right** (`Int`)
- **margin_top** (`Int`)
- **margin_bottom** (`Int`)
- **show_gridlines** (`Bool`)
- **color_scale_low** (`Color`)
- **color_scale_high** (`Color`)
- **size_range_min** (`Float64`)
- **size_range_max** (`Float64`)
- **show_legend** (`Bool`)
- **scale** (`Float64`)
- **donut_inner_radius_fraction** (`Float64`)
- **color_by_sign** (`Bool`)
- **mark_color_negative** (`Color`)
- **bullet_range_color_light** (`Color`)
- **bullet_range_color_dark** (`Color`)
- **line_smoothing** (`Float64`)
- **title_font_size** (`Float64`)
- **axis_title_font_size** (`Float64`)
- **waterfall_total_color** (`Color`)

## Implemented traits

`AnyType`, `Copyable`, `Deinitable`, `ImplicitlyCopyable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self, background: Color = Color(UInt8(255), UInt8(255), UInt8(255), UInt8(255)), mark_color: Color = Color(UInt8(30), UInt8(100), UInt8(180), UInt8(255)), axis_color: Color = Color(UInt8(80), UInt8(80), UInt8(80), UInt8(255)), gridline_color: Color = Color(UInt8(225), UInt8(225), UInt8(225), UInt8(255)), text_color: Color = Color(UInt8(40), UInt8(40), UInt8(40), UInt8(255)), font_size: Float64 = 12, point_radius: Float64 = 3.5, line_width: Float64 = 2, margin_left: Int = Int(60), margin_right: Int = Int(20), margin_top: Int = Int(20), margin_bottom: Int = Int(50), show_gridlines: Bool = True, color_scale_low: Color = Color(UInt8(60), UInt8(110), UInt8(200), UInt8(255)), color_scale_high: Color = Color(UInt8(220), UInt8(90), UInt8(40), UInt8(255)), size_range_min: Float64 = 3, size_range_max: Float64 = 15, show_legend: Bool = True, scale: Float64 = 1, donut_inner_radius_fraction: Float64 = 0, color_by_sign: Bool = False, mark_color_negative: Color = Color(UInt8(200), UInt8(60), UInt8(60), UInt8(255)), bullet_range_color_light: Color = Color(UInt8(224), UInt8(224), UInt8(224), UInt8(255)), bullet_range_color_dark: Color = Color(UInt8(120), UInt8(120), UInt8(120), UInt8(255)), line_smoothing: Float64 = 0, title_font_size: Float64 = 18, axis_title_font_size: Float64 = 14, waterfall_total_color: Color = Color(UInt8(100), UInt8(100), UInt8(100), UInt8(255)))
```

**Args:**

- **background** (`Color`)
- **mark_color** (`Color`)
- **axis_color** (`Color`)
- **gridline_color** (`Color`)
- **text_color** (`Color`)
- **font_size** (`Float64`)
- **point_radius** (`Float64`)
- **line_width** (`Float64`)
- **margin_left** (`Int`)
- **margin_right** (`Int`)
- **margin_top** (`Int`)
- **margin_bottom** (`Int`)
- **show_gridlines** (`Bool`)
- **color_scale_low** (`Color`)
- **color_scale_high** (`Color`)
- **size_range_min** (`Float64`)
- **size_range_max** (`Float64`)
- **show_legend** (`Bool`)
- **scale** (`Float64`)
- **donut_inner_radius_fraction** (`Float64`)
- **color_by_sign** (`Bool`)
- **mark_color_negative** (`Color`)
- **bullet_range_color_light** (`Color`)
- **bullet_range_color_dark** (`Color`)
- **line_smoothing** (`Float64`)
- **title_font_size** (`Float64`)
- **axis_title_font_size** (`Float64`)
- **waterfall_total_color** (`Color`)
- **self** (`Self`)

**Returns:**

`Self`

### `default`

```mojo
@staticmethod
fn def default() -> Self
```

Named the same way `FontSlant.NORMAL`-style call sites in this workspace read -- `Theme.default()` rather than relying on every caller remembering that `Theme()` alone already means the same thing (it does; this is purely for readability at call sites like `.theme(Theme.default())`).

**Returns:**

`Self`


