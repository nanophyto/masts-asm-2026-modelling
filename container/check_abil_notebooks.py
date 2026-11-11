"""Build-time Abil notebook smoke checks; no ML fitting or downloads."""
from __future__ import annotations

from importlib import import_module
from importlib.metadata import version
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
NOTEBOOKS = ROOT / "workshop" / "02_Abil"


def check_package_metadata() -> None:
    """Keep pip dependency checking, tolerating one verified wheel-tag warning.

    A Conda-installed package can carry a WHEEL tag that pip considers
    unsupported, even if its native extension loads and works on this host.
    The XGBoost CPU fit in check() runs before this exception is considered.
    """
    result = subprocess.run(
        [sys.executable, "-m", "pip", "check"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode == 0:
        return

    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    messages = [line.strip() for line in output.splitlines() if line.strip()]
    known_warning = "xgboost 1.7.6 is not supported on this platform"
    other_messages = [message for message in messages if message != known_warning]
    if not messages or other_messages:
        raise RuntimeError(f"pip dependency validation failed:\n{output}")
    print("pip metadata warning for XGBoost 1.7.6 ignored after successful native CPU fit")


def check_xgboost_native() -> None:
    """Exercise the native C++ library, not just import the Python wrapper."""
    import numpy as np
    from xgboost import XGBRegressor

    data = np.arange(8, dtype=np.float32).reshape(-1, 1)
    target = np.arange(8, dtype=np.float32)
    model = XGBRegressor(
        n_estimators=2, max_depth=1, n_jobs=1,
        objective="reg:squarederror", tree_method="hist",
    )
    model.fit(data, target)
    assert np.isfinite(model.predict(data)).all(), "XGBoost returned nonfinite predictions"


def check() -> None:
    assert sys.version_info[:2] == (3, 11), sys.version
    assert version("abil") == "26.5.4.post2"
    for module in (
        "abil", "cartopy", "matplotlib", "seaborn", "numpy", "pandas",
        "xarray", "netCDF4", "yaml", "sklearn", "xgboost", "joblib",
        "ipykernel", "jupyter_client",
    ):
        import_module(module)
    # Abil 26.5.4.post2 pins XGBoost 1.7.6. Importing it above also
    # checks that its native shared library can load successfully.
    assert version("xgboost") == "1.7.6", version("xgboost")
    check_xgboost_native()
    check_package_metadata()
    from jupyter_client.kernelspec import KernelSpecManager
    kernels = KernelSpecManager().find_kernel_specs()
    assert "abil-tutorial-env" in kernels, kernels
    notebooks = sorted(NOTEBOOKS.rglob("*.ipynb"))
    assert notebooks, "No Abil Jupyter notebooks found"
    for notebook in notebooks:
        data = json.loads(notebook.read_text(encoding="utf-8"))
        assert data.get("nbformat") == 4, notebook
        assert data.get("cells"), notebook
    print(f"Abil environment OK; Jupyter kernel registered; {len(notebooks)} notebooks readable")


if __name__ == "__main__":
    check()
