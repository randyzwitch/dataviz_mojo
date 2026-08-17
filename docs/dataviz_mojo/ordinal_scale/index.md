Mojo module [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/ordinal_scale.mojo)

# `ordinal_scale`

OrdinalScale -- maps a fixed-order list of discrete categories onto evenly spaced pixel bands, the standard "band scale" every bar-chart- style categorical axis needs (matches d3's `scaleBand` in spirit: one `padding` fraction, applied as an equal gap on both sides of every band, not separate inner/outer padding knobs -- this package's own "minimal, not a port of everything a mature library offers" approach, same reasoning `LinearGradient` gives for supporting only "pad" extend and not repeat/reflect).

Purely index-based (`band_start(i)`/`center(i)`, not `band_start
(category_string)`) -- a bar chart's data already gives each row's
category and its position in that same row, so there's never a need
to search the domain by string equality to answer "where does this
category go." `Plot`'s own `x_categories` list *is* this scale's
domain, index for index; a caller wanting repeated categories
(grouped/stacked bars) needs a different, not-yet-built encoding --
see the wiki.

## Structs

- [`OrdinalScale`](OrdinalScale.md)

