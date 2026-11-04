"""Fast checks for the unmodified-science upstream BATS regressor example."""

import ast
import csv
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "workshop/02_Abil"


class BATSReferenceTests(unittest.TestCase):
    def test_script_and_config(self):
        script = (EXAMPLE / "regressor.py").read_text()
        ast.parse(script)
        self.assertIn('os.chdir(os.path.dirname(os.path.abspath(__file__)))', script)
        config = yaml.safe_load((EXAMPLE / "regressor_BATS.yml").read_text())
        self.assertEqual(config["predictors"], ["temperature", "no3", "TA", "DIC", "PAR"])
        self.assertEqual([config["ensemble_config"][key] for key in ("m1", "m2", "m3")],
                         ["rf", "xgb", "knn"])

    def test_pinned_bats_inputs(self):
        from sys import path
        path.insert(0, str(ROOT / "abil"))
        from fetch_bats_data import DATASETS, validate_csv

        data_dir = EXAMPLE / "data"
        if not all((data_dir / name).is_file() for name in DATASETS):
            self.skipTest("Datasets are installed during the Docker build (or by abil/fetch_bats_data.py)")
        for name, (minimum_rows, columns) in DATASETS.items():
            contents = (data_dir / name).read_bytes()
            validate_csv(contents, minimum_rows, columns)
        with (data_dir / "bats_training.csv").open(newline="") as f:
            rows = list(csv.DictReader(f))
        self.assertTrue(all(float(row["Gephyrocapsa huxleyi"]) >= 0 for row in rows))


if __name__ == "__main__":
    unittest.main()
