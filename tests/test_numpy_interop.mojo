"""Tests for `_materialize_python_floats` (numpy_interop.mojo) and
`Plot.encode()`/`encode_categorical()`'s `PythonObject` overloads: a
numpy `ndarray`, a pandas `Series`, or a plain Python list of numbers,
converted through numpy's own array-like protocol. Real numpy/pandas
calls throughout (dev/test-only dependencies; see pixi.toml).
"""

from std.testing import assert_equal, assert_raises, TestSuite
from std.python import Python, PythonObject

from dataviz.numpy_interop import _materialize_python_floats
from dataviz.plot import Plot, render_svg


def test_materialize_python_floats_matches_hand_derived_values() raises:
    var np = Python.import_module("numpy")
    var arr = np.array(Python.evaluate("[1.5, 2.5, 3.5]"), dtype="float64")
    var out = _materialize_python_floats(arr)
    assert_equal(len(out), 3)
    assert_equal(out[0], 1.5)
    assert_equal(out[1], 2.5)
    assert_equal(out[2], 3.5)


def test_materialize_python_floats_converts_an_int64_numpy_array() raises:
    var np = Python.import_module("numpy")
    var arr = np.array(Python.evaluate("[1, 2, 3]"), dtype="int64")
    var out = _materialize_python_floats(arr)
    assert_equal(len(out), 3)
    assert_equal(out[0], 1.0)
    assert_equal(out[1], 2.0)
    assert_equal(out[2], 3.0)


def test_materialize_python_floats_accepts_a_plain_python_list() raises:
    # numpy's ascontiguousarray accepts a plain Python list directly.
    var plain_list = Python.evaluate("[4.0, 5.0, 6.0]")
    var out = _materialize_python_floats(plain_list)
    assert_equal(len(out), 3)
    assert_equal(out[0], 4.0)
    assert_equal(out[1], 5.0)
    assert_equal(out[2], 6.0)


def test_materialize_python_floats_accepts_a_pandas_series() raises:
    # A raw pandas Series, not `.to_numpy()`'d first; numpy's array-like
    # protocol handles it.
    var pd = Python.import_module("pandas")
    var series = pd.Series(Python.evaluate("[10, 20, 30]"))
    var out = _materialize_python_floats(series)
    assert_equal(len(out), 3)
    assert_equal(out[0], 10.0)
    assert_equal(out[1], 20.0)
    assert_equal(out[2], 30.0)


def test_materialize_python_floats_raises_on_a_2d_array() raises:
    var np = Python.import_module("numpy")
    var arr2d = np.array(
        Python.evaluate("[[1.0, 2.0], [3.0, 4.0]]"), dtype="float64"
    )
    with assert_raises():
        _ = _materialize_python_floats(arr2d)


def test_materialize_python_floats_raises_on_non_numeric_data() raises:
    var np = Python.import_module("numpy")
    var arr = np.array(Python.evaluate("['a', 'b', 'c']"))
    with assert_raises():
        _ = _materialize_python_floats(arr)


def test_encode_accepts_a_numpy_array_matching_the_list_float64_path() raises:
    var np = Python.import_module("numpy")
    var x = np.array(Python.evaluate("[1.0, 2.0, 3.0]"), dtype="float64")
    var y = np.array(Python.evaluate("[10.0, 20.0, 30.0]"), dtype="float64")
    var plot_from_numpy = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var svg_from_numpy = render_svg(plot_from_numpy).to_string()

    var xf: List[Float64] = [1.0, 2.0, 3.0]
    var yf: List[Float64] = [10.0, 20.0, 30.0]
    var plot_from_list = Plot().mark_point().encode(x=xf, y=yf).size(400, 300)
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_numpy, svg_from_list)


def test_encode_categorical_accepts_a_pandas_series_y_matching_the_list_float64_path() raises:
    var pd = Python.import_module("pandas")
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
