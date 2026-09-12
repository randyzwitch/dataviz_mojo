"""Convert numpy, pandas, and Python numeric arrays to Mojo floats.

Array-like detection and numeric conversion are delegated to numpy:
`np.ascontiguousarray(array, dtype="float64")` accepts an `ndarray` of
any numeric dtype, a plain Python list, and a pandas `Series` directly.
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
    """Copy a numpy `ndarray`/pandas `Series`/plain Python number list into a
    `List[Float64]`. Raises with numpy's/`from_numpy_array`'s own message
    on anything that can't become a 1-D numeric array.
    """
    var np = Python.import_module("numpy")
    var contig = np.ascontiguousarray(array, dtype="float64")
    var span = from_numpy_array[DType.float64](contig)
    var out = List[Float64](capacity=len(span))
    for v in span:
        out.append(v)
    return out^
