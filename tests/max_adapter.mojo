"""MAX Python Tensor and Buffer inputs, run in pixi's max-adapter env."""

from std.python import Python
from std.testing import TestSuite, assert_equal, assert_raises

from dataviz.core.numpy_interop import _materialize_python_floats
from dataviz.plot import Plot, render_svg


def test_max_tensor_and_buffer_match_list_plot() raises:
    var np = Python.import_module("numpy")
    var tensor_module = Python.import_module("max.experimental.tensor")
    var driver = Python.import_module("max.driver")
    var x = tensor_module.Tensor.from_dlpack(
        np.array(Python.evaluate("[1.0, 2.0, 3.0]"), dtype="float32")
    )
    var y = driver.Buffer.from_numpy(
        np.array(Python.evaluate("[10, 20, 30]"), dtype="int64")
    )
    var from_max = render_svg(
        Plot().mark_point().encode(x=x, y=y).size(400, 300)
    ).to_string()
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [10.0, 20.0, 30.0]
    var from_list = render_svg(
        Plot().mark_point().encode(x=xs, y=ys).size(400, 300)
    ).to_string()
    assert_equal(from_max, from_list)


def test_max_buffer_reaches_categorical_values() raises:
    var np = Python.import_module("numpy")
    var driver = Python.import_module("max.driver")
    var values = driver.Buffer.from_numpy(
        np.array(Python.evaluate("[3.0, 5.0]"), dtype="float64")
    )
    var cats: List[String] = ["A", "B"]
    var from_max = render_svg(
        Plot().mark_bar().encode_categorical(x=cats, y=values).size(400, 300)
    ).to_string()
    var ys: List[Float64] = [3.0, 5.0]
    var from_list = render_svg(
        Plot().mark_bar().encode_categorical(x=cats, y=ys).size(400, 300)
    ).to_string()
    assert_equal(from_max, from_list)


def test_max_tensor_matrix_is_rejected() raises:
    var np = Python.import_module("numpy")
    var tensor_module = Python.import_module("max.experimental.tensor")
    var matrix = tensor_module.Tensor.from_dlpack(
        np.array(Python.evaluate("[[1.0, 2.0], [3.0, 4.0]]"))
    )
    with assert_raises():
        _ = _materialize_python_floats(matrix)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
