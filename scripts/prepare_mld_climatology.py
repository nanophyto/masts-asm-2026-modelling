#!/usr/bin/env python3
"""Extract two 12-month GOSML mixed-layer climatologies into an offline CSV.

From the repository root, create the isolated environment once:
    conda env create -f scripts/gosml-environment.yml
Then run:
    conda run -n masts-gosml python scripts/prepare_mld_climatology.py
The five NOAA downloads are cached locally and excluded from Git.
"""

import argparse
from contextlib import ExitStack
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import numpy as np
import xarray as xr

BASE_URL = "https://www.pmel.noaa.gov/gosml/data_files/"
SOURCES = {
    "mean": ("mixed_layer_properties_mean.nc", "depth_mean"),
    "p05": ("mixed_layer_properties_5.nc", "depth_5"),
    "p50": ("mixed_layer_properties_50.nc", "depth_50"),
    "p95": ("mixed_layer_properties_95.nc", "depth_95"),
    "mapping": ("mixed_layer_mapping_stats.nc", None),
}
STATIONS = {"BATS": (31.7, -64.2), "NABE": (47.0, -20.0)}
COLUMNS = (
    "station", "lat_requested", "lon_requested", "lat_selected", "lon_selected",
    "distance_km", "month", "mld_mean_m", "mld_p05_m", "mld_p50_m",
    "mld_p95_m", "n_profiles", "sum_mapping_weights",
)
REPO = Path(__file__).resolve().parents[1]


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download_source(url, destination, retries=3, timeout=90):
    """Download atomically so interrupted fetches never look like cached files."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and destination.stat().st_size > 0:
        return destination
    temporary = destination.with_suffix(destination.suffix + ".part")
    for attempt in range(1, retries + 1):
        try:
            request = Request(url, headers={"User-Agent": "MASTSWorkshop-GOSML/1.0"})
            with urlopen(request, timeout=timeout) as source, temporary.open("wb") as out:
                while chunk := source.read(1024 * 1024):
                    out.write(chunk)
            if not temporary.stat().st_size:
                raise ValueError("empty NetCDF download")
            temporary.replace(destination)
            return destination
        except (OSError, HTTPError, URLError, ValueError) as exc:
            temporary.unlink(missing_ok=True)
            if attempt == retries:
                raise RuntimeError(
                    f"Could not download {url} after {retries} attempts: {exc}. "
                    "Download the five files from https://www.pmel.noaa.gov/gosml/ "
                    "manually and pass --source-dir /path/to/files."
                ) from exc
            time.sleep(min(2 ** (attempt - 1), 4))


def normalized_lon(lon):
    """Normalize longitudes to [-180, 180), preserving scalar or array shape."""
    return (np.asarray(lon) + 180) % 360 - 180


def haversine_km(lat, lon, requested_lat, requested_lon):
    lat = np.deg2rad(np.asarray(lat))
    delta_lat = lat - np.deg2rad(requested_lat)
    delta_lon = np.deg2rad(normalized_lon(np.asarray(lon) - requested_lon))
    a = np.sin(delta_lat / 2) ** 2 + np.cos(lat) * np.cos(np.deg2rad(requested_lat)) * np.sin(delta_lon / 2) ** 2
    return 6371.0 * 2 * np.arcsin(np.sqrt(np.clip(a, 0, 1)))


def month_indices(month_values):
    """Return positions for Jan..Dec from CF month or decimal-month coordinates."""
    values = np.asarray(month_values)
    if np.issubdtype(values.dtype, np.datetime64):
        months = np.asarray([int(str(v)[5:7]) for v in values], dtype=int)
    else:
        numbers = np.asarray(values, dtype=float)
        if numbers.shape != (12,) or not np.all(np.isfinite(numbers)):
            raise ValueError(f"Expected 12 finite climatological months; got {numbers}")
        if np.allclose(np.sort(numbers), np.arange(12) + 0.5, atol=0.05):
            months = np.floor(numbers).astype(int) + 1
        elif np.allclose(np.sort(numbers), np.arange(1, 13), atol=0.05):
            months = np.rint(numbers).astype(int)
        elif np.allclose(np.sort(numbers), np.arange(12), atol=0.05):
            months = np.rint(numbers).astype(int) + 1
        elif np.allclose(np.sort(numbers), (np.arange(12) + 0.5) / 12, atol=0.005):
            months = np.rint(12 * numbers + 0.5).astype(int)
        else:
            raise ValueError(f"Unrecognised GOSML month coordinates: {numbers}")
    if sorted(months.tolist()) != list(range(1, 13)):
        raise ValueError(f"Climatology must contain each month exactly once; got {months}")
    return np.argsort(months)


def canonical_dataset(dataset):
    """Accept common coordinate labels and either longitude convention."""
    aliases = {
        "latitude": ("latitude", "lat", "Latitude", "LATITUDE"),
        "longitude": ("longitude", "lon", "Longitude", "LONGITUDE"),
        "month": ("month", "time", "Month", "MONTH", "TIME"),
    }
    available = set(dataset.variables) | set(dataset.dims)
    rename = {}
    for destination, names in aliases.items():
        name = next((name for name in names if name in available), None)
        if name is None:
            raise ValueError(f"NetCDF lacks a {destination} coordinate")
        if name != destination:
            rename[name] = destination
    dataset = dataset.rename(rename)
    for name in ("latitude", "longitude", "month"):
        if name not in dataset.coords:
            dataset = dataset.set_coords(name)
        if dataset[name].ndim != 1:
            raise ValueError(f"Expected one-dimensional {name} coordinate")
    month_indices(dataset.month.values)
    return dataset


def location_indices(dataset, lat, lon):
    lat_vals = np.asarray(dataset.latitude.values, dtype=float)
    lon_vals = np.asarray(dataset.longitude.values, dtype=float)
    li = int(np.argmin(np.abs(lat_vals - lat)))
    ji = int(np.argmin(np.abs(normalized_lon(lon_vals - lon))))
    if abs(lat_vals[li] - lat) > 0.1 or abs(float(normalized_lon(lon_vals[ji] - lon))) > 0.1:
        raise ValueError(f"Inconsistent GOSML grid at ({lat}, {lon})")
    return li, ji


def read_months(dataset, variable, lat, lon):
    if variable not in dataset:
        raise ValueError(f"Missing expected NetCDF variable {variable}")
    indices = location_indices(dataset, lat, lon)
    field = dataset[variable]
    if set(field.dims) != {"month", "latitude", "longitude"}:
        raise ValueError(f"Unexpected dimensions for {variable}: {field.dims}")
    values = np.asarray(field.isel(latitude=indices[0], longitude=indices[1]).values, dtype=float)
    return values[month_indices(dataset.month.values)]


def check_depth_units(sources):
    units = {}
    for key, (_, variable) in SOURCES.items():
        if variable is None:
            continue
        raw = str(sources[key][variable].attrs.get("units", "")).strip()
        if raw and raw.lower() not in {"m", "meter", "meters", "metre", "metres"}:
            raise ValueError(f"Expected GOSML mixed-layer depth in metres; {variable} uses {raw!r}")
        units[variable] = raw or "metres (as documented by NOAA; absent from file attributes)"
    return units


def station_rows(sources, station, requested_lat, requested_lon, max_distance_km=350):
    """Choose nearest location with a complete, internally consistent 12-month series."""
    reference = sources["mean"]
    lats, lons = np.meshgrid(reference.latitude.values, reference.longitude.values, indexing="ij")
    distances = haversine_km(lats, lons, requested_lat, requested_lon)
    for flat_index in np.argsort(distances, axis=None):
        distance = float(distances.flat[flat_index])
        if distance > max_distance_km:
            break
        i, j = np.unravel_index(flat_index, distances.shape)
        lat, lon = float(lats[i, j]), float(normalized_lon(lons[i, j]))
        try:
            depth = {key: read_months(sources[key], name, lat, lon)
                     for key, (_, name) in SOURCES.items() if name}
            count = read_months(sources["mapping"], "number_observations", lat, lon)
            weight = read_months(sources["mapping"], "sum_mapping_weights", lat, lon)
        except (ValueError, KeyError, IndexError):
            continue
        if not all(np.isfinite(values).all() for values in (*depth.values(), count, weight)):
            continue
        if not (all((values > 0).all() for values in depth.values())
                and (depth["p05"] <= depth["p50"]).all()
                and (depth["p50"] <= depth["p95"]).all()
                and (count > 0).all() and (weight > 0).all()):
            continue
        rows = []
        for m in range(12):
            rows.append(dict(zip(COLUMNS, (
                station, requested_lat, requested_lon, lat, lon, round(distance, 3), m + 1,
                float(depth["mean"][m]), float(depth["p05"][m]),
                float(depth["p50"][m]), float(depth["p95"][m]),
                int(round(count[m])), float(weight[m]),
            ))))
        return rows
    raise ValueError(f"No complete 12-month GOSML ocean cell for {station} "
                     f"within {max_distance_km} km of ({requested_lat}, {requested_lon})")


def extract(source_dir, output_csv, metadata_path, *, maximum_distance_km=350):
    """Read provided NetCDF files, select stations, and write CSV + provenance JSON."""
    paths = {key: Path(source_dir) / filename for key, (filename, _) in SOURCES.items()}
    absent = [str(path) for path in paths.values() if not path.is_file()]
    if absent:
        raise FileNotFoundError("Missing GOSML NetCDF files: " + ", ".join(absent))
    with ExitStack() as stack:
        sources = {key: canonical_dataset(stack.enter_context(xr.open_dataset(path, decode_times=False)))
                   for key, path in paths.items()}
        units = check_depth_units(sources)
        rows = []
        selections = {}
        for station, (lat, lon) in STATIONS.items():
            selected = station_rows(sources, station, lat, lon, maximum_distance_km)
            rows.extend(selected)
            selections[station] = {k: selected[0][k] for k in
                                   ("lat_requested", "lon_requested", "lat_selected", "lon_selected", "distance_km")}
    if len(rows) != 24:
        raise ValueError(f"Expected 24 rows, got {len(rows)}")
    output_csv = Path(output_csv)
    metadata_path = Path(metadata_path)
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    # Create metadata before publishing the CSV, so a failed extraction leaves neither.
    metadata = {
        "dataset": "NOAA PMEL Global Ocean Surface Mixed Layer Statistical Monthly Climatology (GOSML)",
        "citation": "Johnson and Lyman (2022), Journal of Geophysical Research: Oceans, doi:10.1029/2021JC018219",
        "access_date_utc": datetime.now(timezone.utc).date().isoformat(),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "method": "Nearest ocean grid cell with 12 positive, finite, percentile-consistent MLD values and positive mapping support; no spatial interpolation",
        "month_encoding": "January=1 through December=12; sorted from NOAA monthly or decimal-month coordinate",
        "mld_definition": "Holte and Talley (2009) density algorithm on Argo profiles; statistics are spatially/time/bathymetrically weighted (Johnson and Lyman, 2022)",
        "percentiles": "5th, 50th, 95th describe observed MLD distribution, not uncertainty on the climatological mean",
        "depth_units": units,
        "selected_grid_cells": selections,
        "source_files": {
            key: {
                "filename": path.name,
                "url": BASE_URL + path.name,
                "sha256": sha256_file(path),
                "size_bytes": path.stat().st_size,
            }
            for key, path in paths.items()
        },
    }
    temp_csv = output_csv.with_suffix(".csv.tmp")
    temp_metadata = metadata_path.with_suffix(".json.tmp")
    try:
        with temp_csv.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=COLUMNS)
            writer.writeheader()
            writer.writerows(rows)
        temp_metadata.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        temp_csv.replace(output_csv)
        temp_metadata.replace(metadata_path)
    finally:
        temp_csv.unlink(missing_ok=True)
        temp_metadata.unlink(missing_ok=True)
    return rows, metadata


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=None,
                        help="Directory containing five pre-downloaded GOSML NetCDF files; uses no network")
    parser.add_argument("--cache-dir", type=Path, default=REPO / "data/observations/raw",
                        help="Cache directory for original NOAA files (gitignored)")
    parser.add_argument("--output-csv", type=Path,
                        default=REPO / "data/observations/gosml_mld_bats_nabe.csv")
    parser.add_argument("--metadata", type=Path,
                        default=REPO / "data/observations/gosml_mld_bats_nabe.metadata.json")
    parser.add_argument("--max-distance-km", type=float, default=350)
    args = parser.parse_args(argv)
    source_dir = args.source_dir or args.cache_dir
    if args.source_dir is None:
        for filename, _ in SOURCES.values():
            path = source_dir / filename
            print(f"GOSML source: {filename} ({'cached' if path.exists() else 'downloading'})", flush=True)
            download_source(BASE_URL + filename, path)
    try:
        rows, metadata = extract(source_dir, args.output_csv, args.metadata,
                                 maximum_distance_km=args.max_distance_km)
    except ValueError as exc:
        parser.error(str(exc))
    for station in STATIONS:
        selection = metadata["selected_grid_cells"][station]
        depths = [row["mld_mean_m"] for row in rows if row["station"] == station]
        print(f"{station}: cell ({selection['lat_selected']:.2f}, {selection['lon_selected']:.2f}), "
              f"distance {selection['distance_km']:.1f} km, monthly mean MLD {min(depths):.1f}–{max(depths):.1f} m")
    print(f"Wrote {len(rows)} observations to {args.output_csv}")
    print(f"Wrote SHA-256 provenance to {args.metadata}")


if __name__ == "__main__":
    main()
