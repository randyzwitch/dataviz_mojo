"""Every mark renders the same through `Chart[M]` as through `Plot`
(#828). For each `Mark`, the registry's representative `Plot` has its
columns copied into a typed chart of that mark, and the two SVGs must
be identical. This is the digest for the typed path while `Plot` is
still the source of truth."""

from std.testing import TestSuite, assert_equal, assert_true

from dataviz.core.mark import Mark
from dataviz.plot import Plot
from dataviz.rendering import render_svg as render_svg_plot
from dataviz.chart import Chart, Plot2, render_svg
from dataviz.marks import (
    Point,
    Line,
    Bar,
    Area,
    Arc,
    Lollipop,
    Waterfall,
    Box,
    Candlestick,
    Bullet,
    Gantt,
    GroupedBar,
    StackedBar,
    PopulationPyramid,
    Heatmap,
    Chord,
    SingleAxis,
    EffectScatter,
    Funnel,
    Bump,
    Streamgraph,
    Beeswarm,
    Violin,
    Ridgeline,
    Nightingale,
    PolarBar,
    Polar,
    Radar,
    Gauge,
    Parallel,
    SpanChart,
    CalendarHeatmap,
    Corrplot,
    Punchcard,
    Marimekko,
    Sunburst,
    Tree,
    Treemap,
    ArcDiagram,
    Graph,
    Sankey,
    Radialbar,
    Barbs,
    Contour,
    Contourf,
    Tricontour,
    Tricontourf,
    Kde,
    Rug,
    Triplot,
    Tripcolor,
    Ecdf,
    Imshow,
    Pcolormesh,
    Eventplot,
    Pointplot,
    Boxenplot,
    Hist2d,
    Hexbin,
    Quiver,
    Histogram,
    Streamplot,
    DendrogramMark,
    Scatter3d,
    Plot3d,
    Surface3d,
    Wire3d,
    Trisurf3d,
    Bar3d,
    Voxels,
    Stem3d,
    Quiver3d,
    FillBetween3d,
)
from _mark_registry import _representative_plot


def _typed_point(p: Plot) raises -> String:
    var c = Chart[Point](Point(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.channels = p._channels.copy()
    c.mark.y_err = p._y_err.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_line(p: Plot) raises -> String:
    var c = Chart[Line](Line(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.channels = p._channels.copy()
    c.mark.y_err = p._y_err.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_bar(p: Plot) raises -> String:
    var c = Chart[Bar](Bar(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_area(p: Plot) raises -> String:
    var c = Chart[Area](Area(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.channels = p._channels.copy()
    c.mark.y_err = p._y_err.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_arc(p: Plot) raises -> String:
    var c = Chart[Arc](Arc(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_lollipop(p: Plot) raises -> String:
    var c = Chart[Lollipop](
        Lollipop(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_waterfall(p: Plot) raises -> String:
    var c = Chart[Waterfall](
        Waterfall(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.waterfall = p._waterfall.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_box(p: Plot) raises -> String:
    var c = Chart[Box](Box(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.box = p._box.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_candlestick(p: Plot) raises -> String:
    var c = Chart[Candlestick](
        Candlestick(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.candle = p._candle.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_bullet(p: Plot) raises -> String:
    var c = Chart[Bullet](Bullet(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.bullet = p._bullet.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_gantt(p: Plot) raises -> String:
    var c = Chart[Gantt](Gantt(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.gantt = p._gantt.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_grouped_bar(p: Plot) raises -> String:
    var c = Chart[GroupedBar](
        GroupedBar(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.grouped_bar = p._grouped_bar.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_stacked_bar(p: Plot) raises -> String:
    var c = Chart[StackedBar](
        StackedBar(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.grouped_bar = p._grouped_bar.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_population_pyramid(p: Plot) raises -> String:
    var c = Chart[PopulationPyramid](
        PopulationPyramid(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.pyramid = p._pyramid.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_heatmap(p: Plot) raises -> String:
    var c = Chart[Heatmap](Heatmap(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.heatmap = p._heatmap.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_chord(p: Plot) raises -> String:
    var c = Chart[Chord](Chord(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.edge_data = p._edges.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_single_axis(p: Plot) raises -> String:
    var c = Chart[SingleAxis](
        SingleAxis(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.channels = p._channels.copy()
    c.mark.y_err = p._y_err.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_effect_scatter(p: Plot) raises -> String:
    var c = Chart[EffectScatter](
        EffectScatter(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.channels = p._channels.copy()
    c.mark.y_err = p._y_err.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_funnel(p: Plot) raises -> String:
    var c = Chart[Funnel](Funnel(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_bump(p: Plot) raises -> String:
    var c = Chart[Bump](Bump(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.grouped_bar = p._grouped_bar.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_streamgraph(p: Plot) raises -> String:
    var c = Chart[Streamgraph](
        Streamgraph(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.grouped_bar = p._grouped_bar.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_beeswarm(p: Plot) raises -> String:
    var c = Chart[Beeswarm](
        Beeswarm(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.categorical = p._categorical.copy()
    c.mark.distribution = p._distribution.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_violin(p: Plot) raises -> String:
    var c = Chart[Violin](Violin(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.categorical = p._categorical.copy()
    c.mark.distribution = p._distribution.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_ridgeline(p: Plot) raises -> String:
    var c = Chart[Ridgeline](
        Ridgeline(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.categorical = p._categorical.copy()
    c.mark.distribution = p._distribution.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_nightingale(p: Plot) raises -> String:
    var c = Chart[Nightingale](
        Nightingale(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.nightingale = p._nightingale.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_polar_bar(p: Plot) raises -> String:
    var c = Chart[PolarBar](
        PolarBar(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_polar(p: Plot) raises -> String:
    var c = Chart[Polar](Polar(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.polar = p._polar.copy()
    return render_svg(c).to_string()


def _typed_radar(p: Plot) raises -> String:
    var c = Chart[Radar](Radar(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.radar = p._radar.copy()
    return render_svg(c).to_string()


def _typed_gauge(p: Plot) raises -> String:
    var c = Chart[Gauge](Gauge(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.gauge = p._gauge.copy()
    return render_svg(c).to_string()


def _typed_parallel(p: Plot) raises -> String:
    var c = Chart[Parallel](
        Parallel(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.parallel = p._parallel.copy()
    return render_svg(c).to_string()


def _typed_span_chart(p: Plot) raises -> String:
    var c = Chart[SpanChart](
        SpanChart(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.gantt = p._gantt.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_calendar_heatmap(p: Plot) raises -> String:
    var c = Chart[CalendarHeatmap](
        CalendarHeatmap(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.calendar = p._calendar.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_corrplot(p: Plot) raises -> String:
    var c = Chart[Corrplot](
        Corrplot(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.corrplot = p._corrplot.copy()
    return render_svg(c).to_string()


def _typed_punchcard(p: Plot) raises -> String:
    var c = Chart[Punchcard](
        Punchcard(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.punchcard = p._punchcard.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_marimekko(p: Plot) raises -> String:
    var c = Chart[Marimekko](
        Marimekko(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.marimekko = p._marimekko.copy()
    return render_svg(c).to_string()


def _typed_sunburst(p: Plot) raises -> String:
    var c = Chart[Sunburst](
        Sunburst(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.hierarchy = p._hierarchy.copy()
    return render_svg(c).to_string()


def _typed_tree(p: Plot) raises -> String:
    var c = Chart[Tree](Tree(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.hierarchy = p._hierarchy.copy()
    return render_svg(c).to_string()


def _typed_treemap(p: Plot) raises -> String:
    var c = Chart[Treemap](Treemap(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.hierarchy = p._hierarchy.copy()
    return render_svg(c).to_string()


def _typed_arc_diagram(p: Plot) raises -> String:
    var c = Chart[ArcDiagram](
        ArcDiagram(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.edge_data = p._edges.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_graph(p: Plot) raises -> String:
    var c = Chart[Graph](Graph(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.edge_data = p._edges.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_sankey(p: Plot) raises -> String:
    var c = Chart[Sankey](Sankey(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.edge_data = p._edges.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_radialbar(p: Plot) raises -> String:
    var c = Chart[Radialbar](
        Radialbar(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_barbs(p: Plot) raises -> String:
    var c = Chart[Barbs](Barbs(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.barbs = p._barbs.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_contour(p: Plot) raises -> String:
    var c = Chart[Contour](Contour(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.contour = p._contour.copy()
    return render_svg(c).to_string()


def _typed_contourf(p: Plot) raises -> String:
    var c = Chart[Contourf](
        Contourf(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.contour = p._contour.copy()
    return render_svg(c).to_string()


def _typed_tricontour(p: Plot) raises -> String:
    var c = Chart[Tricontour](
        Tricontour(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.tricontour = p._tricontour.copy()
    return render_svg(c).to_string()


def _typed_tricontourf(p: Plot) raises -> String:
    var c = Chart[Tricontourf](
        Tricontourf(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.tricontour = p._tricontour.copy()
    return render_svg(c).to_string()


def _typed_kde(p: Plot) raises -> String:
    var c = Chart[Kde](Kde(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.distribution = p._distribution.copy()
    return render_svg(c).to_string()


def _typed_rug(p: Plot) raises -> String:
    var c = Chart[Rug](Rug(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.distribution = p._distribution.copy()
    return render_svg(c).to_string()


def _typed_triplot(p: Plot) raises -> String:
    var c = Chart[Triplot](Triplot(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.triplot = p._triplot.copy()
    return render_svg(c).to_string()


def _typed_tripcolor(p: Plot) raises -> String:
    var c = Chart[Tripcolor](
        Tripcolor(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.triplot = p._triplot.copy()
    return render_svg(c).to_string()


def _typed_ecdf(p: Plot) raises -> String:
    var c = Chart[Ecdf](Ecdf(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.distribution = p._distribution.copy()
    return render_svg(c).to_string()


def _typed_imshow(p: Plot) raises -> String:
    var c = Chart[Imshow](Imshow(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.image = p._image.copy()
    return render_svg(c).to_string()


def _typed_pcolormesh(p: Plot) raises -> String:
    var c = Chart[Pcolormesh](
        Pcolormesh(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.image = p._image.copy()
    return render_svg(c).to_string()


def _typed_eventplot(p: Plot) raises -> String:
    var c = Chart[Eventplot](
        Eventplot(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.categorical = p._categorical.copy()
    c.mark.distribution = p._distribution.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_pointplot(p: Plot) raises -> String:
    var c = Chart[Pointplot](
        Pointplot(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.y_err = p._y_err.copy()
    return render_svg(c).to_string()


def _typed_boxenplot(p: Plot) raises -> String:
    var c = Chart[Boxenplot](
        Boxenplot(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.boxen = p._boxen.copy()
    c.mark.categorical = p._categorical.copy()
    c.mark.continuous = p._continuous.copy()
    return render_svg(c).to_string()


def _typed_hist2d(p: Plot) raises -> String:
    var c = Chart[Hist2d](Hist2d(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.image = p._image.copy()
    return render_svg(c).to_string()


def _typed_hexbin(p: Plot) raises -> String:
    var c = Chart[Hexbin](Hexbin(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.hexbin = p._hexbin.copy()
    return render_svg(c).to_string()


def _typed_quiver(p: Plot) raises -> String:
    var c = Chart[Quiver](Quiver(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.barbs = p._barbs.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_histogram(p: Plot) raises -> String:
    var c = Chart[Histogram](
        Histogram(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.continuous = p._continuous.copy()
    c.mark.channels = p._channels.copy()
    c.mark.y_err = p._y_err.copy()
    c.mark.histogram = p._histogram.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_streamplot(p: Plot) raises -> String:
    var c = Chart[Streamplot](
        Streamplot(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.stream = p._stream.copy()
    c.mark.continuous = p._continuous.copy()
    c.mark.categorical = p._categorical.copy()
    return render_svg(c).to_string()


def _typed_dendrogram(p: Plot) raises -> String:
    var c = Chart[DendrogramMark](
        DendrogramMark(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.dendrogram = p._dendrogram.copy()
    return render_svg(c).to_string()


def _typed_scatter3d(p: Plot) raises -> String:
    var c = Chart[Scatter3d](
        Scatter3d(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.xyz = p._xyz.copy()
    return render_svg(c).to_string()


def _typed_plot3d(p: Plot) raises -> String:
    var c = Chart[Plot3d](Plot3d(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.xyz = p._xyz.copy()
    return render_svg(c).to_string()


def _typed_surface3d(p: Plot) raises -> String:
    var c = Chart[Surface3d](
        Surface3d(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.surface = p._surface.copy()
    return render_svg(c).to_string()


def _typed_wire3d(p: Plot) raises -> String:
    var c = Chart[Wire3d](Wire3d(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.surface = p._surface.copy()
    return render_svg(c).to_string()


def _typed_trisurf3d(p: Plot) raises -> String:
    var c = Chart[Trisurf3d](
        Trisurf3d(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.xyz = p._xyz.copy()
    return render_svg(c).to_string()


def _typed_bar3d(p: Plot) raises -> String:
    var c = Chart[Bar3d](Bar3d(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.bars3d = p._bars3d.copy()
    return render_svg(c).to_string()


def _typed_voxels(p: Plot) raises -> String:
    var c = Chart[Voxels](Voxels(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.voxels = p._voxels.copy()
    return render_svg(c).to_string()


def _typed_stem3d(p: Plot) raises -> String:
    var c = Chart[Stem3d](Stem3d(), p._settings.copy(), p._mark_style.copy())
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.xyz = p._xyz.copy()
    return render_svg(c).to_string()


def _typed_quiver3d(p: Plot) raises -> String:
    var c = Chart[Quiver3d](
        Quiver3d(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.vectors3d = p._vectors3d.copy()
    return render_svg(c).to_string()


def _typed_fill_between3d(p: Plot) raises -> String:
    var c = Chart[FillBetween3d](
        FillBetween3d(), p._settings.copy(), p._mark_style.copy()
    )
    c.annotations = p._annotations.copy()
    c.width = p.width
    c.height = p.height
    c.mark.ribbon3d = p._ribbon3d.copy()
    return render_svg(c).to_string()


def _typed_svg(mark: Mark, p: Plot) raises -> String:
    if mark == Mark.POINT:
        return _typed_point(p)
    if mark == Mark.LINE:
        return _typed_line(p)
    if mark == Mark.BAR:
        return _typed_bar(p)
    if mark == Mark.AREA:
        return _typed_area(p)
    if mark == Mark.ARC:
        return _typed_arc(p)
    if mark == Mark.LOLLIPOP:
        return _typed_lollipop(p)
    if mark == Mark.WATERFALL:
        return _typed_waterfall(p)
    if mark == Mark.BOX:
        return _typed_box(p)
    if mark == Mark.CANDLESTICK:
        return _typed_candlestick(p)
    if mark == Mark.BULLET:
        return _typed_bullet(p)
    if mark == Mark.GANTT:
        return _typed_gantt(p)
    if mark == Mark.GROUPED_BAR:
        return _typed_grouped_bar(p)
    if mark == Mark.STACKED_BAR:
        return _typed_stacked_bar(p)
    if mark == Mark.POPULATION_PYRAMID:
        return _typed_population_pyramid(p)
    if mark == Mark.HEATMAP:
        return _typed_heatmap(p)
    if mark == Mark.CHORD:
        return _typed_chord(p)
    if mark == Mark.SINGLE_AXIS:
        return _typed_single_axis(p)
    if mark == Mark.EFFECT_SCATTER:
        return _typed_effect_scatter(p)
    if mark == Mark.FUNNEL:
        return _typed_funnel(p)
    if mark == Mark.BUMP:
        return _typed_bump(p)
    if mark == Mark.STREAMGRAPH:
        return _typed_streamgraph(p)
    if mark == Mark.BEESWARM:
        return _typed_beeswarm(p)
    if mark == Mark.VIOLIN:
        return _typed_violin(p)
    if mark == Mark.RIDGELINE:
        return _typed_ridgeline(p)
    if mark == Mark.NIGHTINGALE:
        return _typed_nightingale(p)
    if mark == Mark.POLAR_BAR:
        return _typed_polar_bar(p)
    if mark == Mark.POLAR:
        return _typed_polar(p)
    if mark == Mark.RADAR:
        return _typed_radar(p)
    if mark == Mark.GAUGE:
        return _typed_gauge(p)
    if mark == Mark.PARALLEL:
        return _typed_parallel(p)
    if mark == Mark.SPAN_CHART:
        return _typed_span_chart(p)
    if mark == Mark.CALENDAR_HEATMAP:
        return _typed_calendar_heatmap(p)
    if mark == Mark.CORRPLOT:
        return _typed_corrplot(p)
    if mark == Mark.PUNCHCARD:
        return _typed_punchcard(p)
    if mark == Mark.MARIMEKKO:
        return _typed_marimekko(p)
    if mark == Mark.SUNBURST:
        return _typed_sunburst(p)
    if mark == Mark.TREE:
        return _typed_tree(p)
    if mark == Mark.TREEMAP:
        return _typed_treemap(p)
    if mark == Mark.ARC_DIAGRAM:
        return _typed_arc_diagram(p)
    if mark == Mark.GRAPH:
        return _typed_graph(p)
    if mark == Mark.SANKEY:
        return _typed_sankey(p)
    if mark == Mark.RADIALBAR:
        return _typed_radialbar(p)
    if mark == Mark.BARBS:
        return _typed_barbs(p)
    if mark == Mark.CONTOUR:
        return _typed_contour(p)
    if mark == Mark.CONTOURF:
        return _typed_contourf(p)
    if mark == Mark.TRICONTOUR:
        return _typed_tricontour(p)
    if mark == Mark.TRICONTOURF:
        return _typed_tricontourf(p)
    if mark == Mark.KDE:
        return _typed_kde(p)
    if mark == Mark.RUG:
        return _typed_rug(p)
    if mark == Mark.TRIPLOT:
        return _typed_triplot(p)
    if mark == Mark.TRIPCOLOR:
        return _typed_tripcolor(p)
    if mark == Mark.ECDF:
        return _typed_ecdf(p)
    if mark == Mark.IMSHOW:
        return _typed_imshow(p)
    if mark == Mark.PCOLORMESH:
        return _typed_pcolormesh(p)
    if mark == Mark.EVENTPLOT:
        return _typed_eventplot(p)
    if mark == Mark.POINTPLOT:
        return _typed_pointplot(p)
    if mark == Mark.BOXENPLOT:
        return _typed_boxenplot(p)
    if mark == Mark.HIST2D:
        return _typed_hist2d(p)
    if mark == Mark.HEXBIN:
        return _typed_hexbin(p)
    if mark == Mark.QUIVER:
        return _typed_quiver(p)
    if mark == Mark.HISTOGRAM:
        return _typed_histogram(p)
    if mark == Mark.STREAMPLOT:
        return _typed_streamplot(p)
    if mark == Mark.DENDROGRAM:
        return _typed_dendrogram(p)
    if mark == Mark.SCATTER3D:
        return _typed_scatter3d(p)
    if mark == Mark.PLOT3D:
        return _typed_plot3d(p)
    if mark == Mark.SURFACE3D:
        return _typed_surface3d(p)
    if mark == Mark.WIRE3D:
        return _typed_wire3d(p)
    if mark == Mark.TRISURF3D:
        return _typed_trisurf3d(p)
    if mark == Mark.BAR3D:
        return _typed_bar3d(p)
    if mark == Mark.VOXELS:
        return _typed_voxels(p)
    if mark == Mark.STEM3D:
        return _typed_stem3d(p)
    if mark == Mark.QUIVER3D:
        return _typed_quiver3d(p)
    if mark == Mark.FILL_BETWEEN3D:
        return _typed_fill_between3d(p)
    raise Error("no typed twin for " + mark.name())


def test_every_mark_renders_the_same_svg_typed() raises:
    var checked = 0
    for i in range(Mark.COUNT):
        var mark = Mark(i)
        var p = _representative_plot(mark)
        var expected = render_svg_plot(p).to_string()
        var got = _typed_svg(mark, p)
        assert_true(
            expected == got, "typed " + mark.name() + " renders differently"
        )
        checked += 1
    assert_equal(checked, Mark.COUNT)


def test_the_typed_builder_matches_the_one_call_bar() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var typed = (
        Plot2().mark_bar().encode_categorical(cats, vals).labels(title="Bars")
    )
    var p = (
        Plot().mark_bar().encode_categorical(cats, vals).labels(title="Bars")
    )
    assert_true(render_svg(typed).to_string() == render_svg_plot(p).to_string())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
