"""Offline NASA POWER parser, units and smooth seasonal-fitting regression tests."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from prepare_par_climatology import (MONTHS, STATIONS, create_products, evaluate_fit,
                                     fit_par, month_midpoint_days, parse_power_json,
                                     prepare, watts_per_m2_factor)


def response(values, unit="W/m^2"):
    return json.dumps({
        "properties": {"parameter": {"ALLSKY_SFC_PAR_TOT": dict(zip(MONTHS, values))}},
        "parameters": {"ALLSKY_SFC_PAR_TOT": {"units": unit}},
    }).encode()


class PARPreparationTests(unittest.TestCase):
    def setUp(self):
        self.months = [18 + 40 * (1 - np.cos(2 * np.pi * (m - 1) / 12)) for m in range(1, 13)]

    def test_declared_power_units(self):
        for units, factor in (("W/m^2", 1), ("W m-2", 1),
                              ("MJ/m^2/day", 1e6 / 86400),
                              ("kW-hr/m^2/day", 3.6e6 / 86400)):
            self.assertAlmostEqual(watts_per_m2_factor(units), factor)
        with self.assertRaises(ValueError):
            watts_per_m2_factor("unknown")

    def test_read_monthly_means_and_units(self):
        data, units = parse_power_json(response(self.months))
        self.assertEqual(units, "W/m^2")
        np.testing.assert_allclose(data, self.months)
        mj_per_day = np.array(self.months) * 86400 / 1e6
        data, _ = parse_power_json(response(mj_per_day.tolist(), "MJ/m^2/day"))
        np.testing.assert_allclose(data, self.months)

    def test_reject_missing_units_months_or_data(self):
        invalid = [json.loads(response(self.months)) for _ in range(4)]
        del invalid[0]["parameters"]
        del invalid[1]["properties"]["parameter"]["ALLSKY_SFC_PAR_TOT"]["JUN"]
        invalid[2]["properties"]["parameter"]["ALLSKY_SFC_PAR_TOT"]["APR"] = -999
        invalid[3]["errors"] = ["POWER failed"]
        for payload in invalid:
            with self.assertRaises((ValueError, KeyError)):
                parse_power_json(json.dumps(payload).encode())

    def test_custom_climatology_notice_is_informational(self):
        payload = json.loads(response(self.months))
        payload["messages"] = [
            "The requested parameters are computed for a custom climatological "
            "period (January 2001 - December 2020)"
        ]
        data, units = parse_power_json(json.dumps(payload).encode())
        self.assertEqual(units, "W/m^2")
        np.testing.assert_allclose(data, self.months)

    def test_fit_is_positive_and_periodic(self):
        coefficients, rmse = fit_par(self.months)
        samples = evaluate_fit(coefficients, np.arange(366))
        self.assertTrue(np.all(samples > 0))
        self.assertAlmostEqual(samples[0], samples[-1], places=10)
        self.assertLess(rmse, 2)
        with self.assertRaises(ValueError):
            fit_par([0] * 12)

    def test_offline_products_have_24_rows_and_matching_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "raw"
            cache.mkdir()
            for station in STATIONS:
                monthly_values = (self.months if station == "BATS" else
                                  [value + 5 for value in self.months])
                payload = json.loads(response(monthly_values))
                payload["messages"] = ["Custom climatological period (January 2001 - December 2020)"]
                (cache / f"nasa_power_par_{station.lower()}.json").write_text(json.dumps(payload))
            csv_file, metadata_file, coefficients_file = prepare(
                output_dir=root / "obs", coefficients_path=root / "coefficients.jl",
                cache_dir=cache, offline=True)
            data = csv_file.read_bytes()
            self.assertEqual(len(data.decode().splitlines()), 25)
            self.assertNotEqual(data.decode().splitlines()[1].split(",")[-1],
                                data.decode().splitlines()[13].split(",")[-1])
            metadata = json.loads(metadata_file.read_text())
            self.assertEqual(metadata["csv_sha256"], hashlib.sha256(data).hexdigest())
            self.assertIn('PAR_COEFFICIENT_ORIGIN = "NASA POWER', coefficients_file.read_text())
            self.assertIn(metadata["csv_sha256"], coefficients_file.read_text())
            self.assertEqual(len(metadata["fit_metrics"]), 2)

    def test_empty_cache_fails_before_writing_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(FileNotFoundError):
                prepare(output_dir=root, coefficients_path=root / "coefficients.jl", offline=True)
            self.assertFalse((root / "nasa_power_par_bats_nabe.csv").exists())


if __name__ == "__main__":
    unittest.main()
