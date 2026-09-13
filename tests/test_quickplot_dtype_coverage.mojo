"""Every exported quickplot accepts `List[Int]` as well as `List[Float64]`
for its numeric columns (#224).

#559 collapsed 51 concrete-plus-generic overload pairs into one generic
function each, and the seven that kept multiple overloads did so
deliberately, so that arguments can take different element types
independently (`radar(max_values: List[Float64], series: List[List[Int]])`).

Nothing enforced either property. Dropping an overload, or narrowing a
parameter back to `List[Float64]`, would compile and pass the whole suite;
the only thing that would notice is a caller who is not in this repository.

These are compile-time assertions wearing a test's clothes. **If the file
builds, the overload set is intact**, and that is the whole assertion.

Each call is wrapped in `try`/`except` because the fixtures below are
generic, not valid input for 45 different charts: a pie wants positive
values, a Gantt wants matching row counts, and so on. Those runtime
complaints are not what is being tested and every other test in the suite
covers the drawing. A call that resolved to the wrong overload, or to none,
would fail the build rather than raise.
"""

from std.testing import TestSuite, assert_true

from dataviz import (
    bullet,
    hist2d,
    histogram,
    radar,
    area,
    bar,
    barbs,
    beeswarm,
    box,
    boxenplot,
    bump,
    calendar_heatmap,
    candlestick,
    chord,
    corrplot,
    effect_scatter,
    funnel,
    gantt,
    graph,
    grouped_bar,
    heatmap,
    hexbin,
    line,
    lineplot,
    lollipop,
    marimekko,
    nightingale,
    parallel,
    pie,
    pointplot,
    polar,
    polarbar,
    population_pyramid,
    punchcard,
    quiver,
    radialbar,
    residplot,
    ridgeline,
    sankey,
    scatter,
    single_axis,
    span_chart,
    stacked_bar,
    streamplot,
    sunburst,
    tree,
    treemap,
    violin,
    waterfall,
)


def _f() -> List[Float64]:
    var v = List[Float64]()
    for i in range(6):
        v.append(Float64(i) + 1.0)
    return v^


def _i() -> List[Int]:
    var v = List[Int]()
    for i in range(6):
        v.append(i + 1)
    return v^


def _s() -> List[String]:
    var v = List[String]()
    for i in range(6):
        v.append("c" + String(i))
    return v^


def _nf() -> List[List[Float64]]:
    var v = List[List[Float64]]()
    for i in range(3):
        var row = List[Float64]()
        for j in range(6):
            row.append(Float64(i + j) + 1.0)
        v.append(row^)
    return v^


def _ni() -> List[List[Int]]:
    var v = List[List[Int]]()
    for i in range(3):
        var row = List[Int]()
        for j in range(6):
            row.append(i + j + 1)
        v.append(row^)
    return v^


def test_every_quickplot_accepts_list_float64() raises:
    # The baseline. If this stops compiling the package is broken for
    # everyone, so it is the less interesting half.
    try:
        _ = area(_f(), _f())
    except:
        pass
    try:
        _ = bar(_s(), _f())
    except:
        pass
    try:
        _ = barbs(_f(), _f(), _f(), _f())
    except:
        pass
    try:
        _ = beeswarm(_s(), _nf())
    except:
        pass
    try:
        _ = box(_s(), _nf())
    except:
        pass
    try:
        _ = boxenplot(_s(), _nf())
    except:
        pass
    try:
        _ = bump(_s(), _s(), _nf())
    except:
        pass
    try:
        _ = calendar_heatmap(_s(), _f())
    except:
        pass
    try:
        _ = candlestick(_s(), _f(), _f(), _f(), _f())
    except:
        pass
    try:
        _ = chord(_s(), _s(), _f())
    except:
        pass
    try:
        _ = corrplot(_s(), _nf())
    except:
        pass
    try:
        _ = effect_scatter(_f(), _f())
    except:
        pass
    try:
        _ = funnel(_s(), _f())
    except:
        pass
    try:
        _ = gantt(_s(), _f(), _f())
    except:
        pass
    try:
        _ = graph(_s(), _s(), _f())
    except:
        pass
    try:
        _ = grouped_bar(_s(), _s(), _nf())
    except:
        pass
    try:
        _ = heatmap(_s(), _s(), _f())
    except:
        pass
    try:
        _ = hexbin(_f(), _f())
    except:
        pass
    try:
        _ = line(_f(), _f())
    except:
        pass
    try:
        _ = lineplot(_f(), _f())
    except:
        pass
    try:
        _ = lollipop(_s(), _f())
    except:
        pass
    try:
        _ = marimekko(_s(), _s(), _nf())
    except:
        pass
    try:
        _ = nightingale(_s(), _f())
    except:
        pass
    try:
        _ = parallel(_nf(), _s(), _s())
    except:
        pass
    try:
        _ = pie(_s(), _f())
    except:
        pass
    try:
        _ = pointplot(_s(), _f())
    except:
        pass
    try:
        _ = polar(_f(), _f())
    except:
        pass
    try:
        _ = polarbar(_s(), _f())
    except:
        pass
    try:
        _ = population_pyramid(_s(), _f(), _f())
    except:
        pass
    try:
        _ = punchcard(_s(), _s(), _f())
    except:
        pass
    try:
        _ = quiver(_f(), _f(), _f(), _f())
    except:
        pass
    try:
        _ = radialbar(_s(), _f())
    except:
        pass
    try:
        _ = residplot(_f(), _f())
    except:
        pass
    try:
        _ = ridgeline(_s(), _nf())
    except:
        pass
    try:
        _ = sankey(_s(), _s(), _f())
    except:
        pass
    try:
        _ = scatter(_f(), _f())
    except:
        pass
    try:
        _ = single_axis(_f())
    except:
        pass
    try:
        _ = span_chart(_s(), _f(), _f())
    except:
        pass
    try:
        _ = stacked_bar(_s(), _s(), _nf())
    except:
        pass
    try:
        _ = streamplot(_f(), _f(), _nf(), _nf())
    except:
        pass
    try:
        _ = sunburst(_s(), _s(), _f())
    except:
        pass
    try:
        _ = tree(_s(), _s(), _f())
    except:
        pass
    try:
        _ = treemap(_s(), _s(), _f())
    except:
        pass
    try:
        _ = violin(_s(), _nf())
    except:
        pass
    try:
        _ = waterfall(_s(), _f())
    except:
        pass
    assert_true(True, "all float64 calls resolved")


def test_every_quickplot_accepts_list_int() raises:
    # The half that silently rots. A `List[Int]` caller depends on the
    # DType overload existing; nothing else in the suite passes one.
    try:
        _ = area(_i(), _i())
    except:
        pass
    try:
        _ = bar(_s(), _i())
    except:
        pass
    try:
        _ = barbs(_i(), _i(), _i(), _i())
    except:
        pass
    try:
        _ = beeswarm(_s(), _ni())
    except:
        pass
    try:
        _ = box(_s(), _ni())
    except:
        pass
    try:
        _ = boxenplot(_s(), _ni())
    except:
        pass
    try:
        _ = bump(_s(), _s(), _ni())
    except:
        pass
    try:
        _ = calendar_heatmap(_s(), _i())
    except:
        pass
    try:
        _ = candlestick(_s(), _i(), _i(), _i(), _i())
    except:
        pass
    try:
        _ = chord(_s(), _s(), _i())
    except:
        pass
    try:
        _ = corrplot(_s(), _ni())
    except:
        pass
    try:
        _ = effect_scatter(_i(), _i())
    except:
        pass
    try:
        _ = funnel(_s(), _i())
    except:
        pass
    try:
        _ = gantt(_s(), _i(), _i())
    except:
        pass
    try:
        _ = graph(_s(), _s(), _i())
    except:
        pass
    try:
        _ = grouped_bar(_s(), _s(), _ni())
    except:
        pass
    try:
        _ = heatmap(_s(), _s(), _i())
    except:
        pass
    try:
        _ = hexbin(_i(), _i())
    except:
        pass
    try:
        _ = line(_i(), _i())
    except:
        pass
    try:
        _ = lineplot(_i(), _i())
    except:
        pass
    try:
        _ = lollipop(_s(), _i())
    except:
        pass
    try:
        _ = marimekko(_s(), _s(), _ni())
    except:
        pass
    try:
        _ = nightingale(_s(), _i())
    except:
        pass
    try:
        _ = parallel(_ni(), _s(), _s())
    except:
        pass
    try:
        _ = pie(_s(), _i())
    except:
        pass
    try:
        _ = pointplot(_s(), _i())
    except:
        pass
    try:
        _ = polar(_i(), _i())
    except:
        pass
    try:
        _ = polarbar(_s(), _i())
    except:
        pass
    try:
        _ = population_pyramid(_s(), _i(), _i())
    except:
        pass
    try:
        _ = punchcard(_s(), _s(), _i())
    except:
        pass
    try:
        _ = quiver(_i(), _i(), _i(), _i())
    except:
        pass
    try:
        _ = radialbar(_s(), _i())
    except:
        pass
    try:
        _ = residplot(_i(), _i())
    except:
        pass
    try:
        _ = ridgeline(_s(), _ni())
    except:
        pass
    try:
        _ = sankey(_s(), _s(), _i())
    except:
        pass
    try:
        _ = scatter(_i(), _i())
    except:
        pass
    try:
        _ = single_axis(_i())
    except:
        pass
    try:
        _ = span_chart(_s(), _i(), _i())
    except:
        pass
    try:
        _ = stacked_bar(_s(), _s(), _ni())
    except:
        pass
    try:
        _ = streamplot(_i(), _i(), _ni(), _ni())
    except:
        pass
    try:
        _ = sunburst(_s(), _s(), _i())
    except:
        pass
    try:
        _ = tree(_s(), _s(), _i())
    except:
        pass
    try:
        _ = treemap(_s(), _s(), _i())
    except:
        pass
    try:
        _ = violin(_s(), _ni())
    except:
        pass
    try:
        _ = waterfall(_s(), _i())
    except:
        pass
    assert_true(True, "all int calls resolved")


def test_the_functions_with_extra_required_arguments() raises:
    # Four quickplots take a required non-list argument, so the generated
    # calls above skip them. Written out rather than left uncovered: three
    # of the four are in the set that kept multiple overloads on purpose.
    try:
        _ = histogram(_f(), 5)
    except:
        pass
    try:
        _ = histogram(_i(), 5)
    except:
        pass
    try:
        _ = hist2d(_f(), _f(), 4)
    except:
        pass
    try:
        _ = hist2d(_i(), _i(), 4)
    except:
        pass
    assert_true(True, "bins-taking quickplots resolved for both types")


def test_the_multi_overload_functions_take_mixed_element_types() raises:
    """The property #224 decided to keep rather than refactor away.

    `radar` and `bullet` each pair a fixed `List[Float64]` argument with a
    generic one, so a caller can pass float maxima and integer series in
    the same call. Collapsing those overload sets into a single shared
    `dtype` would take that away, compile cleanly, and break nobody in this
    repository -- which is why it is pinned here.
    """
    try:
        _ = radar(_s(), _f(), _s(), _ni())
    except:
        pass
    try:
        _ = radar(_s(), _f(), _s(), _nf())
    except:
        pass
    try:
        _ = bullet(_s(), _i(), _i(), _nf())
    except:
        pass
    try:
        _ = bullet(_s(), _f(), _f(), _nf())
    except:
        pass
    assert_true(True, "mixed element types across arguments still resolve")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
