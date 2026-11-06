#!/usr/bin/env python3
"""Prepare NASA POWER 2001-2020 surface-PAR climatologies and Julia forcing.

From the repo root:
    conda run -n masts-gosml python scripts/prepare_par_climatology.py

This writes a provenance-backed, 24-row observational CSV and *generates*
Oceananigans-compatible smooth PAR coefficients from the NASA measurements.
Cached raw NASA JSON is stored under data/observations/raw (gitignored).
"""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
API = "https://power.larc.nasa.gov/api/temporal/climatology/point"
PARAMETER = "ALLSKY_SFC_PAR_TOT"
COMMUNITY = "SB"  # Sustainable Buildings: radiation reported as mean W/m^2.
START, END = 2001, 2020
STATIONS = {"BATS": (31.67, -64.17), "NABE": (47.0, -20.0)}
MONTHS = ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")
MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
CSV_COLUMNS = ("station", "month", "latitude", "longitude", "par_w_m2")


def api_url(latitude, longitude):
    return API + "?" + urlencode({
        "parameters": PARAMETER, "community": COMMUNITY, "longitude": longitude,
        "latitude": latitude, "format": "JSON", "start": START, "end": END,
    })


def watts_per_m2_factor(raw):
    """Convert POWER's declared radiant energy/flux units to 24-hour mean W/m^2."""
    unit = str(raw).lower().strip().replace("²", "^2").replace("−", "-")
    unit = "".join(unit.split()).replace("**", "^")
    if unit in {"w/m^2", "w/m2", "wm-2", "wm^-2"}:
        return 1.0
    if unit in {"mj/m^2/day", "mj/m2/day", "mjm-2day-1"}:
        return 1e6 / 86400
    if unit in {"kw-hr/m^2/day", "kwh/m^2/day", "kw-hr/m2/day", "kwh/m2/day"}:
        return 3.6e6 / 86400
    raise ValueError(f"Unrecognised NASA POWER PAR unit {raw!r}; refusing to infer conversion")


def parse_power_json(content):
    """Validate exactly 12 months of PAR and convert the reported units."""
    payload = json.loads(content)
    # POWER uses "messages" for informational notes, including notices about
    # custom climatology periods. Actual API failures are reported separately.
    for field in ("errors", "error"):
        if payload.get(field):
            raise ValueError(f"NASA POWER API reported {field}: {payload[field]}")
    values = payload["properties"]["parameter"][PARAMETER]
    candidates = (payload.get("parameters", {}),
                  payload.get("header", {}).get("parameters", {}),
                  payload.get("header", {}).get("parameter_information", {}))
    raw_unit = next((entry[PARAMETER]["units"] for entry in candidates
                     if isinstance(entry, dict) and PARAMETER in entry
                     and isinstance(entry[PARAMETER], dict) and "units" in entry[PARAMETER]), None)
    if raw_unit is None:
        raise ValueError("NASA POWER response lacks units for ALLSKY_SFC_PAR_TOT")
    factor = watts_per_m2_factor(raw_unit)
    if any(m not in values for m in MONTHS):
        raise ValueError("NASA POWER PAR climatology must contain JAN through DEC")
    result = np.array([float(values[m]) * factor for m in MONTHS])
    if not np.all(np.isfinite(result)) or not np.all((result > 0) & (result < 400)):
        raise ValueError("NASA POWER returned missing or implausible monthly mean PAR")
    return result, raw_unit


def month_midpoint_days():
    starts = np.cumsum([0, *MONTH_DAYS[:-1]])
    return starts + np.array(MONTH_DAYS) / 2


def design_matrix(days):
    phase = 2 * np.pi * np.asarray(days) / 365
    return np.column_stack((np.ones_like(phase), np.cos(phase), np.sin(phase),
                            np.cos(2 * phase), np.sin(2 * phase)))


def evaluate_fit(coefficients, days):
    return np.exp(design_matrix(days) @ coefficients)


def fit_par(values):
    """Periodic two-harmonic fit in log(PAR), positive at all times."""
    values = np.asarray(values, dtype=float)
    if values.shape != (12,) or not np.all(np.isfinite(values)) or np.any(values <= 0):
        raise ValueError("Expected twelve positive, finite monthly PAR values")
    coefficients = np.linalg.lstsq(design_matrix(month_midpoint_days()),
                                  np.log(values), rcond=None)[0]
    daily = evaluate_fit(coefficients, np.arange(366))
    if not np.all((daily > 0) & (daily < 400)):
        raise ValueError("PAR fit yielded physically implausible daily irradiance")
    rmse = float(np.sqrt(np.mean((evaluate_fit(coefficients, month_midpoint_days()) - values) ** 2)))
    return coefficients, rmse


def read_station(station, cache_dir, offline=False, refresh=False):
    lat, lon = STATIONS[station]
    cache = cache_dir / f"nasa_power_par_{station.lower()}.json"
    url = api_url(lat, lon)
    if cache.is_file() and not refresh:
        raw = cache.read_bytes()
    elif offline:
        raise FileNotFoundError(f"Missing cached NASA POWER file: {cache}")
    else:
        request = Request(url, headers={"User-Agent": "MASTS-ASM-2026-PAR-climatology/1.0"})
        with urlopen(request, timeout=50) as response:
            raw = response.read()
    values, units = parse_power_json(raw)
    cache.parent.mkdir(parents=True, exist_ok=True)
    if not cache.is_file() or refresh:
        cache.write_bytes(raw)
    return values, {"url": url, "units_as_reported": units,
                    "sha256": hashlib.sha256(raw).hexdigest(),
                    "cached_file": str(cache.relative_to(ROOT)) if cache.is_relative_to(ROOT) else str(cache)}


def create_products(observations):
    """Generate a small CSV, provenance JSON data and a Julia coefficient file."""
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=CSV_COLUMNS, lineterminator="\n")
    writer.writeheader()
    coefficients = {}
    metrics = {}
    for station, (values, _) in observations.items():
        for month, value in enumerate(values, 1):
            writer.writerow(dict(zip(CSV_COLUMNS, (station, month, *STATIONS[station], f"{value:.8f}"))))
        coefficients[station], rmse = fit_par(values)
        metrics[station] = {
            "monthly_fit_rmse_w_m2": round(rmse, 4),
            "observed_min_w_m2": round(float(np.min(values)), 4),
            "observed_max_w_m2": round(float(np.max(values)), 4),
            "fitted_min_w_m2": round(float(np.min(evaluate_fit(coefficients[station], np.arange(365)))), 4),
            "fitted_max_w_m2": round(float(np.max(evaluate_fit(coefficients[station], np.arange(365)))), 4),
        }
    csv_bytes = output.getvalue().encode("utf-8")
    csv_sha = hashlib.sha256(csv_bytes).hexdigest()
    fmt = lambda x: format(float(x), ".15g")
    constants = (
        "# Generated by scripts/prepare_par_climatology.py from NASA POWER station observations.\n"
        "# 2001-2020, ALLSKY_SFC_PAR_TOT (24-hour mean W/m^2). Do not edit manually.\n"
        f'const PAR_COEFFICIENT_ORIGIN = "NASA POWER 2001-2020"\n'
        f'const PAR_CSV_SHA256 = "{csv_sha}"\n'
        f'const BATS_PAR_LOG_COEFFICIENTS = ({", ".join(map(fmt, coefficients["BATS"]))})\n'
        f'const NABE_PAR_LOG_COEFFICIENTS = ({", ".join(map(fmt, coefficients["NABE"]))})\n'
    )
    metadata = {
        "dataset": "NASA POWER ALLSKY_SFC_PAR_TOT (CERES all-sky surface PAR)",
        "community": COMMUNITY, "start_year": START, "end_year": END,
        "units": "W m-2 (24-hour mean irradiance)",
        "monthly_values": "monthly climatological averages, not noon irradiance",
        "calibration": "Least-squares two-harmonic log(PAR) fit at calendar-month midpoints; periodic and positive",
        "csv_sha256": csv_sha, "fit_metrics": metrics,
        "source_files": {station: props for station, (_, props) in observations.items()},
        "retrieved_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    return csv_bytes, constants.encode("utf-8"), metadata


def prepare(*, output_dir=None, coefficients_path=None, cache_dir=None, offline=False, refresh=False):
    output_dir = Path(output_dir or ROOT / "data/observations")
    coefficients_path = Path(coefficients_path or ROOT / "oceanbiome/src/par_forcing_coefficients.jl")
    cache_dir = Path(cache_dir or output_dir / "raw")
    observations = {station: read_station(station, cache_dir, offline=offline, refresh=refresh)
                    for station in STATIONS}
    csv_bytes, constants, metadata = create_products(observations)
    output_dir.mkdir(parents=True, exist_ok=True)
    coefficients_path.parent.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "nasa_power_par_bats_nabe.csv"
    metadata_path = output_dir / "nasa_power_par_bats_nabe.metadata.json"
    # Publish only after both station records and both fits validate successfully.
    csv_path.write_bytes(csv_bytes)
    coefficients_path.write_bytes(constants)
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for station, stats in metadata["fit_metrics"].items():
        print(f"{station}: observed {stats['observed_min_w_m2']}-{stats['observed_max_w_m2']} W/m2; "
              f"fit RMSE {stats['monthly_fit_rmse_w_m2']} W/m2")
    print(f"Wrote {csv_path}\nWrote {metadata_path}\nWrote {coefficients_path}")
    return csv_path, metadata_path, coefficients_path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="Use existing cached NASA JSON files")
    parser.add_argument("--refresh", action="store_true", help="Refetch NASA climatologies")
    args = parser.parse_args(argv)
    if args.offline and args.refresh:
        parser.error("--offline and --refresh are mutually exclusive")
    prepare(offline=args.offline, refresh=args.refresh)


if __name__ == "__main__":
    main()
