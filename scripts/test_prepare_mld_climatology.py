"""Offline tests for GOSML extraction; NetCDF fixtures require only xarray + scipy."""

import csv
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

import numpy as np
import xarray as xr

from prepare_mld_climatology import SOURCES, extract, month_indices, normalized_lon


class GOSMLExtractionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.raw = self.directory / "sources"
        self.raw.mkdir()
        self.csv = self.directory / "observations.csv"
        self.metadata = self.directory / "metadata.json"

    def make_sources(self, *, descending=False, alternate_longitudes=False,
                     invalid_nearest=False, bad_percentiles=False, bad_units=False,
                     incomplete_months=False):
        latitudes = np.array([31.5, 32.5, 47.5, 48.5], dtype=float)
        longitudes = np.array([-64.5, -63.5, -20.5, -19.5], dtype=float)
        for key, (filename, variable) in SOURCES.items():
            lat = latitudes[::-1] if descending else latitudes
            lon = longitudes.copy()
            if alternate_longitudes and key in {"p05", "p95", "mapping"}:
                lon = np.mod(lon, 360)
            if descending:
                lon = lon[::-1]
            months = np.arange(12, dtype=float) + 0.5
            if incomplete_months:
                months[-1] = months[-2]
            if descending:
                months = months[::-1]
            data = np.zeros((len(months), len(lat), len(lon)))
            for m, month in enumerate(months):
                for i, latitude in enumerate(lat):
                    for j, longitude in enumerate(lon):
                        data[m, i, j] = (float(np.floor(month)) + 1) + (5 if latitude > 40 else 0)
            if key == "mean":
                data = 20 + data
            elif key == "p05":
                data = 5 + data
            elif key == "p50":
                data = 15 + data
            elif key == "p95":
                data = 50 + data
            elif key == "mapping":
                data = 100 + data
            if invalid_nearest and key == "mean":
                near_lat = int(np.where(lat == 31.5)[0][0])
                near_lon = int(np.where(np.isclose(normalized_lon(lon), -64.5))[0][0])
                data[4, near_lat, near_lon] = np.nan
            if bad_percentiles and key == "p50":
                data += 100
            if key == "mapping":
                dataset = xr.Dataset({
                    "number_observations": (("time", "lat", "lon"), data),
                    "sum_mapping_weights": (("time", "lat", "lon"), data / 2),
                }, coords={"time": months, "lat": lat, "lon": lon})
            else:
                dataset = xr.Dataset({
                    variable: (("time", "lat", "lon"), data,
                               {"units": "cm" if bad_units else "m"}),
                }, coords={"time": months, "lat": lat, "lon": lon})
            dataset.to_netcdf(self.raw / filename, engine="scipy")

    def test_extract_24_rows_and_traceable_sources(self):
        self.make_sources(descending=True, alternate_longitudes=True)
        rows, metadata = extract(self.raw, self.csv, self.metadata)
        self.assertEqual(len(rows), 24)
        for station in ("BATS", "NABE"):
            monthly = [row for row in rows if row["station"] == station]
            self.assertEqual([row["month"] for row in monthly], list(range(1, 13)))
            self.assertTrue(all(row["mld_p05_m"] <= row["mld_p50_m"] <= row["mld_p95_m"]
                                for row in monthly))
            self.assertTrue(all(row["n_profiles"] > 0 for row in monthly))
        self.assertEqual(rows[0]["mld_mean_m"], 21.0)
        self.assertEqual(rows[12]["mld_mean_m"], 26.0)
        self.assertEqual(rows[0]["lon_selected"], -64.5)
        self.assertEqual(rows[12]["lon_selected"], -20.5)
        with self.csv.open(newline="") as file:
            self.assertEqual(len(list(csv.DictReader(file))), 24)
        self.assertEqual(metadata["selected_grid_cells"]["BATS"]["lat_selected"], 31.5)
        from_disk = json.loads(self.metadata.read_text())
        mean_path = self.raw / SOURCES["mean"][0]
        self.assertEqual(from_disk["source_files"]["mean"]["sha256"],
                         hashlib.sha256(mean_path.read_bytes()).hexdigest())

    def test_offline_command_line_extract(self):
        self.make_sources()
        result = subprocess.run([
            sys.executable, str(Path(__file__).with_name("prepare_mld_climatology.py")),
            "--source-dir", str(self.raw), "--output-csv", str(self.csv),
            "--metadata", str(self.metadata),
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Wrote 24 observations", result.stdout)
        self.assertTrue(self.csv.is_file() and self.metadata.is_file())

    def test_nearest_invalid_ocean_cell_uses_valid_neighbor(self):
        self.make_sources(invalid_nearest=True)
        rows, _ = extract(self.raw, self.csv, self.metadata)
        self.assertNotEqual((rows[0]["lat_selected"], rows[0]["lon_selected"]),
                            (31.5, -64.5))
        self.assertEqual(rows[0]["station"], "BATS")

    def test_reject_inconsistent_percentiles(self):
        self.make_sources(bad_percentiles=True)
        with self.assertRaisesRegex(ValueError, "No complete 12-month"):
            extract(self.raw, self.csv, self.metadata)
        self.assertFalse(self.csv.exists())

    def test_reject_unrecognised_depth_units(self):
        self.make_sources(bad_units=True)
        with self.assertRaisesRegex(ValueError, "metres"):
            extract(self.raw, self.csv, self.metadata)

    def test_reject_missing_month(self):
        self.make_sources(incomplete_months=True)
        with self.assertRaisesRegex(ValueError, "month"):
            extract(self.raw, self.csv, self.metadata)

    def test_reject_missing_sources(self):
        with self.assertRaisesRegex(FileNotFoundError, "Missing GOSML"):
            extract(self.raw, self.csv, self.metadata)

    def test_month_coordinates_can_be_zero_based_or_decimal_year(self):
        for values in (np.arange(12), np.arange(1, 13),
                       (np.arange(12) + 0.5) / 12, np.arange(12) + 0.5):
            self.assertEqual(month_indices(values[::-1]).tolist(), list(range(11, -1, -1)))

    def test_max_selection_distance(self):
        self.make_sources()
        with self.assertRaisesRegex(ValueError, "within 1 km"):
            extract(self.raw, self.csv, self.metadata, maximum_distance_km=1)


if __name__ == "__main__":
    unittest.main()
