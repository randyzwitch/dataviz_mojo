Mojo module [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/scale.mojo)

# `scale`

LinearScale -- maps a continuous data domain onto a pixel range, and picks "nice" tick positions within that domain for axis labeling. This is the piece canvas_mojo.geometry.Transform2D's own docstring already named as deferred here: `scale()`/`translate()` below compute exactly the slope/intercept Transform2D's affine map takes, so Plot builds one Transform2D from an x-scale and a y-scale (with the y-scale's range reversed -- pixel y increases downward, data y conventionally increases upward, the same "negative scale_y" trick Transform2D's own docstring documents) rather than reimplementing the linear map here.

`ticks()` is the one genuinely new algorithm in this package: Paul
Heckbert's "nice numbers for graph labels" (Graphics Gems, 1990), the
same approach d3/matplotlib/most charting libraries use in spirit --
round the ideal step size for a target tick count up to the nearest
"nice" multiple (1, 2, 5, or 10 times a power of ten) so labels read
as 0.2/0.4/0.6, not 0.1934/0.3868/0.5802. Every example in this
module's own docstring below was independently computed by hand
before trusting the Mojo implementation.

## Structs

- [`MinMax`](MinMax.md): A column's [min, max] -- a small named struct rather than a positional tuple (see scale.mojo's sibling `Ticks`/`_NiceStep` for the same reasoning), and the shared starting point for every kind of domain this package computes: `Plot._data_extent` pads it for spatial (x/y) axes, `ColorScale`/size encoding use it exactly as- is (no padding -- a color/size legend's extremes should mean exactly the data's own extremes, not a padded approximation of them).
- [`Ticks`](Ticks.md): LinearScale.ticks()'s result: the tick positions themselves plus how many decimal places they need for display -- both returned together since the decimal count falls straight out of the same step computation _nice_step already did, not a separate thing to re-derive from a tick value afterward.
- [`LinearScale`](LinearScale.md): A linear map from [domain_min, domain_max] to [range_min, range_max] -- `range_min`/`range_max` are the pixel positions `domain_min`/`domain_max` land on, not necessarily numerically increasing (a y-axis scale passes range_min=plot_bottom_pixel, range_max=plot_top_pixel, a *smaller* pixel value, since pixel y increases downward -- the map comes out with a negative slope automatically, no separate "flip" flag needed).

