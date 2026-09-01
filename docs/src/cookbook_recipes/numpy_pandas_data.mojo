"""Plot a numpy array or a pandas Series directly -- `Plot.encode()`/
`encode_categorical()` accept either with no manual conversion, even a
raw `Series` with no `.to_numpy()` step first.
"""
from dataviz_mojo.plot import Plot, save
from std.python import Python

def main() raises:
    var np = Python.import_module("numpy")
    var pd = Python.import_module("pandas")

    var x = np.linspace(0.0, 10.0, 20)
    var y = np.sin(x)

    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
    var revenue = pd.Series(Python.evaluate("[42, 48, 45, 61]"))

    var scatter_plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .labels(title="A NumPy Array, Plotted Directly", x_title="x", y_title="sin(x)")
    )
    save(scatter_plot, "docs/src/examples/out_numpy_pandas_data_scatter.svg")

    var bar_plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=quarters, y=revenue)
        .labels(title="A pandas Series, Plotted Directly", y_title="Revenue ($M)")
    )
    save(bar_plot, "docs/src/examples/out_numpy_pandas_data_bar.svg")
