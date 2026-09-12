"""An encoder rejects a mark it does not write data for (#538).

`Plot` carries every mark's data on one struct with the mark as a
runtime field, so `Plot().mark_line().encode_boxenplot(...)` compiles.
It used to fail later, in the render or as a chart that drew nothing,
with an error naming neither the mark nor the encoder. Mojo 1.0 cannot
make it a type error: a trait cannot be a collection's element type and
`render_layers()` takes `List[Plot]` (#522).

The check lives in the encoder rather than in `render()`. That costs
the calling order -- `mark_*()` must come before `encode_*()` -- and
buys an error at the call that is actually wrong.

These tests cover the three shapes the accepted sets come in, because
they are not one encoder to one mark:

- one encoder, one mark, the common case
- one encoder, several marks that share a payload and differ only in
  what they draw
- an encoder that delegates to another, where the inner one has to
  accept every mark its callers accept
"""

from std.testing import TestSuite, assert_raises, assert_true

from dataviz import Theme
from dataviz.mark import Mark
from dataviz.plot import Plot, render


def _xs() -> List[Float64]:
    var x = List[Float64]()
    for i in range(6):
        x.append(Float64(i))
    return x^


def _ys() -> List[Float64]:
    var y = List[Float64]()
    for i in range(6):
        y.append(Float64(i) * 1.5 + 1.0)
    return y^


def _cats() -> List[String]:
    var c = List[String]()
    for i in range(3):
        c.append("c" + String(i))
    return c^


def _groups() -> List[List[Float64]]:
    var g = List[List[Float64]]()
    for i in range(3):
        var row = List[Float64]()
        for j in range(5):
            row.append(Float64((i + 1) * (j + 1)))
        g.append(row^)
    return g^


def test_a_mismatched_encoder_names_both_the_mark_and_itself() raises:
    # The whole point: the message says what was called, what it needed,
    # and what the plot actually is. Asserting on all three, because an
    # error that says only "invalid mark" would pass a weaker test.
    with assert_raises(contains="encode_boxenplot"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())
    with assert_raises(contains="Mark.BOXENPLOT"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())
    with assert_raises(contains="Mark.LINE"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())


def test_the_message_says_which_builder_would_fix_it() raises:
    with assert_raises(contains="mark_boxenplot()"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())


def test_the_matching_mark_is_accepted_and_renders() raises:
    # The other half of the claim: the check rejects the wrong pairing
    # without breaking the right one.
    var p = Plot().mark_boxenplot().encode_boxenplot(_cats(), _groups())
    var c = render(p^.size(320, 240))
    assert_true(c.width == 320, "the correct pairing still renders")


def test_the_default_mark_needs_no_builder_call() raises:
    # `Plot()` starts at Mark.POINT and `encode()` accepts it, so a
    # plot that never calls a `mark_*()` still encodes. Several tests
    # rely on this to reach render-time validation errors.
    var p = Plot().encode(x=_xs(), y=_ys())
    var c = render(p^.size(200, 150))
    assert_true(c.width == 200, "the default mark encodes")


def test_an_encoder_shared_by_two_marks_accepts_both() raises:
    # BARBS and QUIVER read the same `_barbs` payload and differ only in
    # the glyph. A set, not a single mark.
    var u = List[Float64]()
    var v = List[Float64]()
    for i in range(6):
        u.append(1.0)
        v.append(Float64(i) * 0.5)
    _ = Plot().mark_barbs().encode_barbs(_xs(), _ys(), u, v)
    _ = Plot().mark_quiver().encode_barbs(_xs(), _ys(), u, v)

    # ... and still rejects one that reads a different payload.
    with assert_raises(contains="encode_barbs"):
        _ = Plot().mark_bar().encode_barbs(_xs(), _ys(), u, v)


def test_a_delegating_encoder_does_not_trip_the_inner_check() raises:
    # `encode_ecdf()` delegates to `encode_kde()`, so the inner encoder
    # has to accept Mark.ECDF even though its own name does not suggest
    # it. This is the case the first version of the table got wrong.
    var vals = _ys()
    _ = Plot().mark_ecdf().encode_ecdf(vals)
    _ = Plot().mark_ecdf().encode_kde(vals)
    _ = Plot().mark_kde().encode_kde(vals)


def test_the_reverse_order_now_raises() raises:
    # The cost of checking in the encoder rather than at render time.
    # `encode_*()` before `mark_*()` used to work and no longer does,
    # deliberately: the plot is still Mark.POINT when the encoder runs.
    with assert_raises(contains="encode_boxplot"):
        _ = Plot().encode_boxplot(_cats(), _groups()).mark_box()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
