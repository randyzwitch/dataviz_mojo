"""Tests for NumPy, pandas, and Python-list numeric inputs.

These are the only tests that reach outside the Mojo toolchain, so they
are the only ones a broken Python environment can fail. When that
happens the failure reads as a code defect, which sends you looking at
the conversion first and costs an hour (#536).

`_import_or_explain` is why it no longer does. It does not skip -- a
skip would hide a real breakage, which is the objection that left #536
unresolved -- it fails exactly as before and says what to check. The
diagnosis changes from slow to instant; nothing is tolerated that was
not tolerated before.
"""

from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.python import Python, PythonObject

from dataviz.core.numpy_interop import _materialize_python_floats
from dataviz.plot import Plot
from dataviz import render_svg


def _import_or_explain(module: String) raises -> PythonObject:
    """Import `module`, or fail saying the environment is the suspect.

    The failure that prompted this looked like:

        Unable to import required dependencies:
          pytz: No module named 'pytz'
          dateutil: No module named 'dateutil'

    pandas was installed and its own dependencies were not importable,
    because the environment had two Python trees with the packages split
    across them and `bin/python` resolved to the one missing half. It
    reproduced every run, so it did not look like a flake, and nothing
    in the message pointed at the environment.

    Args:
        module: What to import.

    Returns:
        The module.

    Raises:
        Error: The import failed, with what to check appended.
    """
    try:
        return Python.import_module(module)
    except e:
        raise Error(
            "could not import "
            + module
            + " -- this is almost always a stale pixi environment rather"
            + " than a defect in this library (dataviz_mojo#536). Try"
            + " `rm -rf .pixi && pixi install` and run again; if it still"
            + " fails, the environment has two Python trees with the"
            + " packages split across them. Original error: "
            + String(e)
        )


def test_materialize_python_floats_matches_hand_derived_values() raises:
    var np = _import_or_explain("numpy")
    var arr = np.array(Python.evaluate("[1.5, 2.5, 3.5]"), dtype="float64")
    var out = _materialize_python_floats(arr)
    assert_equal(len(out), 3)
    assert_equal(out[0], 1.5)
    assert_equal(out[1], 2.5)
    assert_equal(out[2], 3.5)


def test_materialize_python_floats_converts_an_int64_numpy_array() raises:
    var np = _import_or_explain("numpy")
    var arr = np.array(Python.evaluate("[1, 2, 3]"), dtype="int64")
    var out = _materialize_python_floats(arr)
    assert_equal(len(out), 3)
    assert_equal(out[0], 1.0)
    assert_equal(out[1], 2.0)
    assert_equal(out[2], 3.0)


def test_materialize_python_floats_accepts_a_plain_python_list() raises:
    # `ascontiguousarray` accepts a plain Python list.
    var plain_list = Python.evaluate("[4.0, 5.0, 6.0]")
    var out = _materialize_python_floats(plain_list)
    assert_equal(len(out), 3)
    assert_equal(out[0], 4.0)
    assert_equal(out[1], 5.0)
    assert_equal(out[2], 6.0)


def test_materialize_python_floats_accepts_a_pandas_series() raises:
    # NumPy's array protocol handles a pandas Series directly.
    var pd = _import_or_explain("pandas")
    var series = pd.Series(Python.evaluate("[10, 20, 30]"))
    var out = _materialize_python_floats(series)
    assert_equal(len(out), 3)
    assert_equal(out[0], 10.0)
    assert_equal(out[1], 20.0)
    assert_equal(out[2], 30.0)


def test_materialize_python_floats_raises_on_a_2d_array() raises:
    var np = _import_or_explain("numpy")
    var arr2d = np.array(
        Python.evaluate("[[1.0, 2.0], [3.0, 4.0]]"), dtype="float64"
    )
    with assert_raises():
        _ = _materialize_python_floats(arr2d)


def test_materialize_python_floats_raises_on_non_numeric_data() raises:
    var np = _import_or_explain("numpy")
    var arr = np.array(Python.evaluate("['a', 'b', 'c']"))
    with assert_raises():
        _ = _materialize_python_floats(arr)


def test_encode_accepts_a_numpy_array_matching_the_list_float64_path() raises:
    var np = _import_or_explain("numpy")
    var x = np.array(Python.evaluate("[1.0, 2.0, 3.0]"), dtype="float64")
    var y = np.array(Python.evaluate("[10.0, 20.0, 30.0]"), dtype="float64")
    var plot_from_numpy = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var svg_from_numpy = render_svg(plot_from_numpy).to_string()

    var xf: List[Float64] = [1.0, 2.0, 3.0]
    var yf: List[Float64] = [10.0, 20.0, 30.0]
    var plot_from_list = Plot().mark_point().encode(x=xf, y=yf).size(400, 300)
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_numpy, svg_from_list)


def test_encode_labels_work_for_numpy_input_of_mixed_dtypes() raises:
    # #699: the PythonObject overload had no labels= at all. An int64 x
    # against a float32 y (exact values) with labels renders the same
    # bytes as the List[Float64] call with the same labels.
    var np = _import_or_explain("numpy")
    var x = np.array(Python.evaluate("[1, 2, 3]"), dtype="int64")
    var y = np.array(Python.evaluate("[0.5, 2.25, 4.0]"), dtype="float32")
    var labels: List[String] = ["one", "two", "three"]
    var from_numpy = render_svg(
        Plot().mark_point().encode(x=x, y=y, labels=labels).size(400, 300)
    ).to_string()
    var xf: List[Float64] = [1.0, 2.0, 3.0]
    var yf: List[Float64] = [0.5, 2.25, 4.0]
    var from_list = render_svg(
        Plot().mark_point().encode(x=xf, y=yf, labels=labels).size(400, 300)
    ).to_string()
    assert_equal(from_numpy, from_list)
    assert_true(">two</text>" in from_numpy, "the labels are drawn")


def test_encode_categorical_accepts_a_pandas_series_y_matching_the_list_float64_path() raises:
    var pd = _import_or_explain("pandas")
    var cats: List[String] = ["A", "B", "C"]
    var series = pd.Series(Python.evaluate("[10, 20, -5]"))
    var plot_from_pandas = (
        Plot().mark_bar().encode_categorical(x=cats, y=series).size(400, 300)
    )
    var svg_from_pandas = render_svg(plot_from_pandas).to_string()

    var yf: List[Float64] = [10.0, 20.0, -5.0]
    var plot_from_list = (
        Plot().mark_bar().encode_categorical(x=cats, y=yf).size(400, 300)
    )
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_pandas, svg_from_list)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
