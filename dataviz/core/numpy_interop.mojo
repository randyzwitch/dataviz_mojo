"""Convert numpy, pandas, MAX, and Python numeric arrays to Mojo floats.

Array-like detection and numeric conversion are delegated to numpy:
`np.ascontiguousarray(array, dtype="float64")` accepts an `ndarray` of
any numeric dtype, a plain Python list, and a pandas `Series` directly.
Objects with `to_numpy()` (including MAX Tensor and Buffer) first copy
their data to a host NumPy array.
`std.python.numpy.from_numpy_array` borrows the contiguous result, which is
then copied into `List[Float64]`.

Requires numpy in the caller's environment; `Python.import_module(
"numpy")` raises if it is missing. dataviz itself never depends on
numpy (pixi.toml lists it as a dev/test-only dependency).

Only one-dimensional numeric input is supported. Numpy must be installed in
the caller's environment.
"""

from std.python import Python, PythonObject
from std.python.numpy import from_numpy_array


def _materialize_python_floats(array: PythonObject) raises -> List[Float64]:
    """Copy a numeric Python array, including MAX Tensor or Buffer, into a
    `List[Float64]`. Calls `to_numpy()` when available before converting
    to contiguous float64 storage. Raises with NumPy's own message when
    the value cannot become a one-dimensional numeric array.
    """
    var np = Python.import_module("numpy")
    var source = array
    if Bool(Python.import_module("builtins").hasattr(array, "to_numpy")):
        source = array.to_numpy()
    var contig = np.ascontiguousarray(source, dtype="float64")
    var span = from_numpy_array[DType.float64](contig)
    var out = List[Float64](capacity=len(span))
    for v in span:
        out.append(v)
    return out^
