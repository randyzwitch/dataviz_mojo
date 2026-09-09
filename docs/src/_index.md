---
title: dataviz_mojo
type: hextra-home
layout: hextra-home
---

<div class="hx:mt-6 hx:mb-6">
{{< hextra/hero-headline >}}
  Grammar-of-graphics charts,&nbsp;<br class="hx:sm:block hx:hidden" />native to Mojo
{{< /hextra/hero-headline >}}
</div>

<div class="hx:mb-12">
{{< hextra/hero-subtitle >}}
  One fluent `Plot` builder -- mark, encode, theme -- covers 40+ chart types,<br class="hx:sm:block hx:hidden" />
  rendered to SVG or raster.
{{< /hextra/hero-subtitle >}}
</div>

<div class="hx:mb-12 hx:flex hx:flex-wrap hx:gap-4">
{{< hextra/hero-button text="Quickstart" link="quickstart/" >}}
{{< hextra/hero-button text="Choose a chart" link="chart-selection/" style="background-color: transparent; color: inherit; border: 1px solid currentColor;" >}}
{{< hextra/hero-button text="Browse examples" link="examples/" style="background-color: transparent; color: inherit; border: 1px solid currentColor;" >}}
</div>

## See it before you build it

Every chart below comes straight from the example gallery.

<style>

h2 {
  margin-top: 2.5rem;
  margin-bottom: 1rem;
  padding-bottom: 0.25rem;
  border-bottom: 1px solid color-mix(in srgb, currentColor 12%, transparent);
  font-size: 1.875rem;
  line-height: 2.25rem;
  font-weight: 600;
  letter-spacing: -0.025em;
}
p:not([class]) {
  margin-top: 1rem;
  line-height: 1.75rem;
}

#content a:not(.not-prose) {
  color: var(--hx-color-primary-600);
  text-decoration: underline;
  text-decoration-color: color-mix(in srgb, var(--hx-color-primary-600) 40%, transparent);
  text-underline-offset: 2px;
}
#content a:not(.not-prose):hover {
  text-decoration-color: var(--hx-color-primary-600);
}
.dvm-gallery {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1rem;
  width: 100%;
  margin: 1.5rem 0 3rem;
}
@media (max-width: 640px) {
  .dvm-gallery {
    grid-template-columns: repeat(2, 1fr);
  }
}
.dvm-gallery a {
  display: block;
  border-radius: 1rem;
  border: 1px solid color-mix(in srgb, currentColor 15%, transparent);
  overflow: hidden;
  text-decoration: none;
  color: inherit;
  transition: border-color 0.2s ease;
}
.dvm-gallery a:hover {
  border-color: color-mix(in srgb, currentColor 45%, transparent);
}
.dvm-gallery .dvm-thumb {
  background: #fff;
  height: 8rem;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0.5rem;
}
.dvm-gallery .dvm-thumb img {
  max-width: 100%;
  max-height: 100%;
}
.dvm-gallery .dvm-caption {
  padding: 0.5rem 0.75rem;
  font-size: 0.875rem;
  opacity: 0.7;
}

:root.light .dvm-gallery a {
  border-color: #b8dcec;
}
:root.light .dvm-gallery a:hover {
  border-color: #6fa8c9;
}
:root.light .dvm-gallery .dvm-thumb {
  background: #eaf5fa;
}
:root.light .dvm-chart-preview {
  background: #eaf5fa;
  border-color: #b8dcec;
}
:root.light h2 {
  border-bottom-color: #b8dcec;
}


.dvm-next {
  width: 100%;
  text-align: right;
  margin-top: 1.5rem;
}
.dvm-next a {
  font-size: 1.125rem;
  font-weight: 600;
  color: var(--hx-color-primary-600);
}
.dvm-next a:hover {
  text-decoration: underline;
}
</style>

<div class="dvm-gallery not-prose">
  <a href="examples/streamgraph/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_streamgraph.svg" alt="Streamgraph" /></div><div class="dvm-caption">Streamgraph</div></a>
  <a href="examples/chord/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_chord.svg" alt="Chord diagram" /></div><div class="dvm-caption">Chord</div></a>
  <a href="examples/sunburst/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_sunburst.svg" alt="Sunburst" /></div><div class="dvm-caption">Sunburst</div></a>
  <a href="examples/candlestick/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_candlestick.svg" alt="Candlestick" /></div><div class="dvm-caption">Candlestick</div></a>
  <a href="examples/radar/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_radar.svg" alt="Radar" /></div><div class="dvm-caption">Radar</div></a>
  <a href="examples/sankey/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_sankey.svg" alt="Sankey" /></div><div class="dvm-caption">Sankey</div></a>
  <a href="examples/calendar_heatmap/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_calendar_heatmap.svg" alt="Calendar heatmap" /></div><div class="dvm-caption">Calendar heatmap</div></a>
  <a href="examples/treemap/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_treemap.svg" alt="Treemap" /></div><div class="dvm-caption">Treemap</div></a>
  <a href="examples/population_pyramid/" class="not-prose"><div class="dvm-thumb"><img src="examples/out_population_pyramid.svg" alt="Population pyramid" /></div><div class="dvm-caption">Population pyramid</div></a>
</div>

<p class="hx:text-sm hx:text-gray-500 hx:dark:text-gray-400 hx:mb-12">
  Nine of the 40+ chart types this package builds -- see the rest, source next to rendered output, in
  <a href="examples/">the examples gallery</a>.
</p>

## Why dataviz_mojo?

{{< hextra/feature-grid cols="3" >}}
  {{< hextra/feature-card
    icon="template"
    title="Grammar of graphics when you want it"
    subtitle="One fluent `Plot` builder -- `mark_point()`/`mark_bar()`/... + `encode()` + `.theme()` is enough to build any chart."
  >}}
  {{< hextra/feature-card
    icon="chart-square-bar"
    title="40+ convenience chart functions"
    subtitle="Scatter and bar through sankey, treemap, radar, and candlestick -- statistical, financial, hierarchical, radial, and network charts all share the same API."
  >}}
  {{< hextra/feature-card
    icon="lightning-bolt"
    title="Native Mojo, no bindings"
    subtitle="Pure Mojo top to bottom, built on `canvas_mojo`!"
  >}}
  {{< hextra/feature-card
    icon="photograph"
    title="SVG or raster"
    subtitle="Every `Plot` renders to crisp SVG or a PNG/BMP raster canvas -- `save()` picks the backend from the file extension."
  >}}
  {{< hextra/feature-card
    icon="puzzle"
    title="One pixi install away"
    subtitle="A git-source pixi dependency -- `pixi install` builds `dataviz_mojo` and `canvas_mojo` for you"
  >}}
  {{< hextra/feature-card
    icon="code"
    title="Open Source"
    subtitle="MIT licensed on GitHub -- read the source, file an issue, or send a PR."
  >}}
{{< /hextra/feature-grid >}}

## A first chart

<div class="dvm-chart-row">

<div class="dvm-chart-code">

```mojo
from dataviz import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

    var plot = (
                Plot()
                .mark_point()
                .encode(x=x, y=y)
               )

    save(plot, "chart.svg")
```

</div>

<div class="dvm-chart-preview"><img src="examples/out_scatter.svg" alt="The scatter plot that code produces" /></div>

</div>

That's the same pattern behind every mark type this package supports, plus color/size encoding, facets, multi-series layering, and the raster backend.

Use the [conceptual guides](guides/) when you need to coordinate scales,
themes, encodings, composition, accessibility, or output across chart types.

<p class="dvm-next"><a href="quickstart/" class="not-prose">Quickstart &rarr;</a></p>
