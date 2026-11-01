"""Check that both short workshop exercises generated their required outputs."""

from pathlib import Path
import sys


EXPECTED = {
    "reference": (
        "reference_vertical_evolution.png", "reference_nitrogen_partition.png",
        "reference_living_fraction.png", "reference_carbon_export.png",
        "reference_martin_curve.png", "reference_physics.png",
        "reference_diagnostics.csv",
    ),
    "grazing": (
        "grazing_response.png", "grazing_plankton_balance.png",
        "carbon_export.png", "control_diagnostics.csv",
        "reduced_grazing_diagnostics.csv",
    ),
}


def main(root):
    for folder, names in EXPECTED.items():
        for name in names:
            file = root / folder / name
            if not file.is_file() or file.stat().st_size <= 8:
                raise RuntimeError(f"Missing or empty workshop output: {file}")
            if file.suffix == ".png" and file.open("rb").read(8) != bytes((137, 80, 78, 71, 13, 10, 26, 10)):
                raise RuntimeError(f"Invalid PNG header: {file}")
    print("Both scientific exercises generated the expected diagnostics and figures")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
