#!/usr/bin/env python3
"""Make the BATS/NABE map from real satellite-derived NPP values.

Source: Ocean Productivity, VIIRS R2022 CAFE monthly HDF data.
Algorithm: Silsbe et al. (2016), Global Biogeochemical Cycles.
The plotted map is cropped to the North Atlantic and masked to open-ocean
pixels deeper than 200 m using the Natural Earth bathymetry polygon.
"""

import argparse
import calendar
from contextlib import contextmanager
from datetime import date
import gzip
from pathlib import Path
import shutil
import tempfile
from urllib.request import Request, urlopen

import fiona
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import rasterio
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from scipy.io import netcdf_file

ROOT = Path(__file__).resolve().parents[1]
BASE_URL = "https://orca.science.oregonstate.edu/data/1x2/monthly/cafe.viirs.r2022/hdf"
DATA_PAGE = "https://orca.science.oregonstate.edu/1080.by.2160.monthly.hdf.cafe.v.php"
PAPER = "https://doi.org/10.1002/2016GB005521"
# Use the maintained Natural Earth source repository rather than the broken
# legacy download redirect or an unavailable S3 object.
BATHYMETRY_URL = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
                  "master/geojson/ne_10m_bathymetry_K_200.geojson")
BATHYMETRY_PAGE = "https://www.naturalearthdata.com/downloads/10m-physical-vectors/"
BOUNDS = (-91.0, 18.0, 8.0, 68.0)  # longitude / latitude edges, degrees
BATS = (-64.17, 31.67)
NABE = (-20.0, 47.0)
GLOBAL_SHAPE = (1080, 2160)
GLOBAL_RESOLUTION = 1.0 / 6.0


def grid(bounds=BOUNDS, resolution=GLOBAL_RESOLUTION):
    west, east, south, north = bounds
    nlon = round((east - west) / resolution)
    nlat = round((north - south) / resolution)
    longitude = west + (np.arange(nlon) + 0.5) * resolution
    latitude = south + (np.arange(nlat) + 0.5) * resolution
    return latitude.astype(np.float32), longitude.astype(np.float32)


def monthly_file(year, month):
    first_day = date(year, month, 1).timetuple().tm_yday
    return f"cafe.{year}{first_day:03d}.hdf.gz"


def fetch(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and destination.stat().st_size > 0:
        return destination
    request = Request(url, headers={"User-Agent": "MASTSWorkshop-NPP-map/1.1"})
    partial = destination.with_suffix(destination.suffix + ".part")
    try:
        with urlopen(request, timeout=120) as response, open(partial, "wb") as output:
            while data := response.read(1024 * 1024):
                output.write(data)
        partial.replace(destination)
    finally:
        partial.unlink(missing_ok=True)
    return destination


@contextmanager
def gunzipped_copy(path):
    """Yield a temporary uncompressed copy of a .gz file."""
    suffix = ''.join(path.with_suffix('').suffixes) or path.stem
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / Path(path).with_suffix("").name
        with gzip.open(path, "rb") as source, open(target, "wb") as destination:
            shutil.copyfileobj(source, destination)
        yield target


def global_latlon(height, width):
    """Cell centres for global 180x360 rasters."""
    dlon = 360.0 / width
    dlat = 180.0 / height
    lon = -180.0 + (np.arange(width) + 0.5) * dlon
    lat = -90.0 + (np.arange(height) + 0.5) * dlat
    return lat.astype(np.float32), lon.astype(np.float32)


def _candidate_subdatasets(dataset):
    names = list(dataset.subdatasets)
    preferred = []
    other = []
    for name in names:
        label = name.lower()
        if any(token in label for token in ("npp", "cafe", "productivity", "pp")):
            preferred.append(name)
        else:
            other.append(name)
    return preferred + other


def _read_raster(path):
    # HDF4 starts with this four-byte signature. Check the driver only for
    # actual HDF4 files; this also permits lightweight GeoTIFF-based tests.
    with open(path, "rb") as header:
        is_hdf4 = header.read(4) == b"\x0e\x03\x13\x01"
    if is_hdf4:
        with rasterio.Env() as env:
            if not any("HDF4" in driver.upper() for driver in env.drivers()):
                raise RuntimeError(
                    "GDAL HDF4 support is missing. Run "
                    "`conda env update -f scripts/npp-map-environment.yml --prune` "
                    "to install libgdal-hdf4."
                )
    with rasterio.open(path) as container:
        targets = _candidate_subdatasets(container) or [None]
        for target in targets:
            with rasterio.open(target) if target is not None else rasterio.open(path) as src:
                data = src.read(1, masked=True).astype(np.float32)
                if np.ma.is_masked(data):
                    data = data.filled(np.nan)
                else:
                    data = np.asarray(data, dtype=np.float32)
                nodata = src.nodata
                if nodata is not None:
                    data[data == nodata] = np.nan
                data[~np.isfinite(data)] = np.nan
                if np.isfinite(data).any():
                    return data
    raise ValueError(f"Could not find a readable NPP raster in {path}")


def crop_global(values, *, bounds=BOUNDS):
    lat_global, lon_global = global_latlon(*values.shape)
    west, east, south, north = bounds
    j = np.where((lon_global >= west) & (lon_global < east))[0]
    i = np.where((lat_global >= south) & (lat_global < north))[0]
    if len(i) == 0 or len(j) == 0:
        raise ValueError("Crop bounds do not intersect the source grid")
    # Ocean Productivity HDF grids are north-to-south (row 0 at +90 N).
    # Our latitude coordinate is increasing, so flip the raster rows first.
    cropped = values[::-1, :][np.ix_(i, j)].astype(np.float32)
    cropped[(cropped < 0) | (cropped > 100000)] = np.nan
    return lat_global[i], lon_global[j], cropped


def read_month(path, *, bounds=BOUNDS):
    """Read a compressed monthly HDF file and crop to the North Atlantic."""
    with gunzipped_copy(path) as extracted:
        values = _read_raster(extracted)
    if values.shape == GLOBAL_SHAPE:
        return crop_global(values, bounds=bounds)
    # Synthetic tests can use smaller rasters with the target cropped shape already.
    latitude, longitude = grid(bounds=bounds)
    if values.shape != (len(latitude), len(longitude)):
        raise ValueError(
            f"Unexpected raster shape {values.shape}; expected {GLOBAL_SHAPE} or {(len(latitude), len(longitude))}"
        )
    values[(values < 0) | (values > 100000)] = np.nan
    return latitude, longitude, values.astype(np.float32)


def annual_mean(monthly_values, *, year):
    """Mean daily NPP over a calendar year, weighted by days per month."""
    if len(monthly_values) != 12:
        raise ValueError("Exactly 12 monthly NPP grids are required")
    shape = monthly_values[0].shape
    weighted_total = np.zeros(shape, dtype=np.float64)
    valid_days = np.zeros(shape, dtype=np.float64)
    for month, values in enumerate(monthly_values, 1):
        if values.shape != shape:
            raise ValueError("Inconsistent NPP grid shape")
        n_days = calendar.monthrange(year, month)[1]
        valid = np.isfinite(values) & (values >= 0)
        weighted_total[valid] += n_days * values[valid]
        valid_days[valid] += n_days
    mean = np.full(shape, np.nan, dtype=np.float32)
    np.divide(weighted_total, valid_days, out=mean, where=valid_days > 0)
    return mean


def bathymetry_mask_path(cache):
    return cache / "ne_10m_bathymetry_K_200.geojson"


def load_open_ocean_mask(latitude, longitude, bathymetry_geojson):
    """Rasterize Natural Earth's ocean-deeper-than-200-m polygons onto the NPP grid.

    Fiona reads the official GeoJSON directly, with no intermediate extraction.
    Latitude in the output array increases south-to-north; rasterio rasterizes
    north-to-south, so the final mask is flipped vertically.
    """
    dx = float(np.median(np.diff(longitude)))
    dy = float(np.median(np.diff(latitude)))
    west = float(longitude[0] - dx / 2)
    east = float(longitude[-1] + dx / 2)
    south = float(latitude[0] - dy / 2)
    north = float(latitude[-1] + dy / 2)
    transform = from_bounds(west, south, east, north, len(longitude), len(latitude))

    with fiona.open(bathymetry_geojson) as source:
        shapes = [feature["geometry"] for feature in source if feature.get("geometry")]
    if not shapes:
        raise ValueError(f"No 200 m bathymetry geometries in {bathymetry_geojson}")

    mask_north_up = rasterize(
        ((geometry, 1) for geometry in shapes),
        out_shape=(len(latitude), len(longitude)),
        fill=0,
        transform=transform,
        dtype=np.uint8,
        all_touched=False,
    )
    return np.flipud(mask_north_up).astype(bool)


def apply_open_ocean_mask(values, mask):
    masked = values.astype(np.float32, copy=True)
    masked[~mask] = np.nan
    return masked


def write_netcdf(path, latitude, longitude, npp, year):
    """Save the geographically referenced NPP values, not a colour raster."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with netcdf_file(path, "w") as nc:
        nc.createDimension("latitude", len(latitude))
        nc.createDimension("longitude", len(longitude))
        lat = nc.createVariable("latitude", "f4", ("latitude",))
        lon = nc.createVariable("longitude", "f4", ("longitude",))
        field = nc.createVariable("npp", "f4", ("latitude", "longitude"))
        lat[:] = latitude
        lon[:] = longitude
        field[:] = npp
        lat.units = "degrees_north"
        lon.units = "degrees_east"
        field.units = "mg C m-2 d-1"
        field.long_name = "Annual mean open-ocean net primary production, CAFE"
        nc.title = f"North Atlantic open-ocean VIIRS CAFE NPP, {year}"
        nc.source = DATA_PAGE
        nc.algorithm_reference = PAPER
        nc.bathymetry_mask = f"Natural Earth 10m bathymetry 200 m polygon ({BATHYMETRY_PAGE})"
        nc.averaging = "Day-weighted average of 12 monthly daily NPP estimates"


def read_netcdf(path):
    with netcdf_file(path, "r", mmap=False) as nc:
        return (
            np.array(nc.variables["latitude"][:]),
            np.array(nc.variables["longitude"][:]),
            np.array(nc.variables["npp"][:]),
        )


def _cell_edges(values):
    values = np.asarray(values, dtype=np.float64)
    if values.ndim != 1 or values.size < 2:
        raise ValueError("Expected a one-dimensional coordinate array with at least two values")
    midpoints = 0.5 * (values[:-1] + values[1:])
    first = values[0] - 0.5 * (values[1] - values[0])
    last = values[-1] + 0.5 * (values[-1] - values[-2])
    return np.concatenate(([first], midpoints, [last]))


def plot_map(path, destination, land_csv, year):
    latitude, longitude, npp = read_netcdf(path)
    # Explicit panel positions use the full figure width. The earlier
    # subplots_adjust(right=0.84) left a large unused strip right of the
    # colourbar, even after changing the colour scale.
    fig = plt.figure(figsize=(12.0, 7.0), dpi=140)
    ax = fig.add_axes((0.078, 0.145, 0.780, 0.775))
    colorbar_ax = fig.add_axes((0.875, 0.168, 0.025, 0.730))
    ax.set_facecolor("#dfe8ee")
    cmap = plt.get_cmap("viridis").copy()
    cmap.set_bad((0.0, 0.0, 0.0, 0.0))
    mesh = ax.pcolormesh(
        _cell_edges(longitude),
        _cell_edges(latitude),
        np.ma.masked_invalid(npp),
        cmap=cmap,
        vmin=0,
        vmax=600,
        shading="flat",
        rasterized=True,
    )

    # Public-domain Natural Earth coastline polygons committed with the repo.
    polygon = []
    for line in land_csv.read_text().splitlines() + [""]:
        line = line.strip()
        if not line:
            if len(polygon) >= 3:
                x, y = zip(*polygon)
                ax.fill(x, y, color="#e7e8de", ec="#777e77", lw=0.55, zorder=3)
            polygon = []
        elif not line.startswith("#"):
            polygon.append(tuple(float(v) for v in line.split(",")))

    for name, (lon, lat), colour, offset in (
        ("BATS", BATS, "#174a7e", (9, -20)),
        ("NABE", NABE, "#b14b19", (9, 13)),
    ):
        ax.scatter(lon, lat, s=115, color=colour, edgecolors="white", linewidths=1.8, zorder=5)
        ax.annotate(
            name,
            (lon, lat),
            xytext=offset,
            textcoords="offset points",
            fontsize=11,
            fontweight="bold",
            color=colour,
            zorder=6,
            bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.85, "pad": 1.6},
        )

    ax.set(
        xlim=(BOUNDS[0], BOUNDS[1]),
        ylim=(BOUNDS[2], BOUNDS[3]),
        xlabel="Longitude (°)",
        ylabel="Latitude (°)",
    )
    ax.set_title(f"North Atlantic open-ocean net primary production · {year}", fontsize=15)
    cb = fig.colorbar(mesh, cax=colorbar_ax, extend="max", ticks=np.arange(0, 1201, 200))
    cb.set_label("NPP (mg C m$^{-2}$ d$^{-1}$)")
    fig.text(
        0.08,
        0.035,
        "VIIRS CAFE (2023) · Ocean Productivity · open ocean (>200 m) · Silsbe et al. (2016)",
        fontsize=9,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(destination, dpi=140, facecolor="white", bbox_inches="tight", pad_inches=0.12)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, default=2023)
    parser.add_argument("--cache", type=Path, default=ROOT / "outputs" / "maps" / "cafe_monthly")
    parser.add_argument("--netcdf", type=Path, default=None)
    parser.add_argument("--figure", type=Path, default=None)
    parser.add_argument("--skip-bathymetry-mask", action="store_true",
                        help="Plot the regional CAFE field without the >200 m open-ocean mask")
    args = parser.parse_args()
    netcdf = args.netcdf or ROOT / "data" / "maps" / f"north_atlantic_cafe_npp_{args.year}.nc"
    if not netcdf.is_file():
        # Cache the numerical annual mean separately: a failed bathymetry
        # download must never require re-reading 12 HDF4 monthly rasters.
        annual_cache = args.cache / f"north_atlantic_cafe_{args.year}_annual_unmasked.npz"
        if annual_cache.is_file():
            print(f"Reusing annual CAFE mean: {annual_cache}", flush=True)
            with np.load(annual_cache, allow_pickle=False) as cached:
                latitudes, longitudes, annual = (cached[key].copy() for key in
                                                  ("latitude", "longitude", "npp"))
        else:
            latitudes = longitudes = None
            fields = []
            for month in range(1, 13):
                name = monthly_file(args.year, month)
                gz_path = fetch(f"{BASE_URL}/{name}", args.cache / name)
                print(f"Reading {gz_path.name}", flush=True)
                latitude, longitude, field = read_month(gz_path)
                if latitudes is None:
                    latitudes, longitudes = latitude, longitude
                fields.append(field)
            annual = annual_mean(fields, year=args.year)
            annual_cache.parent.mkdir(parents=True, exist_ok=True)
            np.savez_compressed(annual_cache, latitude=latitudes,
                                longitude=longitudes, npp=annual)
            print(f"Saved reusable annual CAFE mean: {annual_cache}", flush=True)
        if not args.skip_bathymetry_mask:
            bathymetry = fetch(BATHYMETRY_URL, bathymetry_mask_path(args.cache))
            mask = load_open_ocean_mask(latitudes, longitudes, bathymetry)
            annual = apply_open_ocean_mask(annual, mask)
        write_netcdf(netcdf, latitudes, longitudes, annual, args.year)
    figure = args.figure or ROOT / "data" / "maps" / f"north_atlantic_cafe_npp_{args.year}.png"
    plot_map(netcdf, figure, ROOT / "data" / "maps" / "north_atlantic_land.csv", args.year)
    docs_figure = ROOT / "docs" / "src" / "assets" / "station_map.png"
    docs_figure.parent.mkdir(parents=True, exist_ok=True)
    if figure.resolve() != docs_figure.resolve():
        shutil.copyfile(figure, docs_figure)
    print(f"Saved numerical NPP data: {netcdf}")
    print(f"Saved plotted map: {figure}")
    print(f"Updated documentation asset: {docs_figure}")


if __name__ == "__main__":
    main()
