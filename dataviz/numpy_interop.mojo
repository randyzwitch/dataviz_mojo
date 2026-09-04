"""`_materialize_python_floats`: the numpy/pandas adapter, a third input
axis alongside array_like.mojo's `Float64Sequence`/`StringSequence`
(container type) and `DType` genericity (element type). `PythonObject`
can't conform to a Mojo trait, so it gets its own adapter.

Array-like detection and numeric conversion are delegated to numpy:
`np.ascontiguousarray(array, dtype="float64")` accepts an `ndarray` of
any numeric dtype, a plain Python list, and a pandas `Series` directly.
`std.python.numpy.from_numpy_array` then borrows the result as a `Span`
without copying; the one copy is from that `Span` into the
`List[Float64]` the rest of the package expects.

Requires numpy in the caller's environment; `Python.import_module(
"numpy")` raises if it is missing. dataviz itself never depends on
numpy (pixi.toml lists it as a dev/test-only dependency).

Numeric `x`/`y` only. A `PythonObject` string column for
`Plot.encode_categorical()` is a separate follow-up (#158).

plot.mojo imports `PythonObject` (from `std.python`) and this module's
`_materialize_python_floats` unconditionally, for the two `PythonObject`
overloads of `Plot.encode()`/`encode_categorical()` (#225 checked
whether that costs a consumer who never calls either overload
anything):

- **Runtime linkage**: none. A consumer binary built with `mojo build`
  against this package and never calling into a `PythonObject` path
  has no `libpython`/CPython entry in its dynamic section at all
  (`ldd` on the binary lists only `libc`/`libm`/`libstdc++`/the Mojo
  runtime shared libs); Mojo's Python interop resolves and loads
  CPython lazily (effectively `dlopen`) only when a `Python.*` call
  actually executes. Such a binary starts and runs identically on a
  machine with no Python installed at all.
- **Compile time**: no measurable difference. Building the same
  one-file consumer against this package as published versus against
  a copy with both `PythonObject` overloads (and their two imports)
  removed took the same ~23 CPU-s cold / ~4.5s warm either way, in
  repeated `mojo build` timings -- the package's real compile-time
  cost is the `_render_generic` dispatch tree's own monomorphization
  (see pixi.toml's `[tasks]` comment), not this import.

Both answers came back "no impact," so the two `PythonObject`
overloads stay on `Plot` itself rather than moving behind a separate
import path.
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
