#!/usr/bin/env python3
"""Render the BATS/NABE map from the committed 2023 CAFE numerical NetCDF.

The NetCDF is a small curated observational input, not a pre-rendered figure.
Every documentation build creates its own PNG from this file. Source: VIIRS
CAFE, Silsbe et al. (2016), with the Natural Earth >200 m ocean mask applied.
"""

from pathlib import Path
import argparse

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.io import netcdf_file

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/maps/north_atlantic_cafe_npp_2023.nc"
LAND = ROOT / "data/maps/north_atlantic_land.csv"
OUTPUT = ROOT / "data/maps/north_atlantic_cafe_npp_2023.png"
BATS = (-64.17, 31.67)
NABE = (-20.0, 47.0)


def cell_edges(coordinates):
    coords = np.asarray(coordinates, dtype=np.float64)
    if coords.ndim != 1 or coords.size < 2 or not np.all(np.diff(coords) > 0):
        raise ValueError("Expected increasing 1D geographic coordinates")
    midpoints = (coords[1:] + coords[:-1]) / 2
    return np.r_[coords[0] - (midpoints[0] - coords[0]), midpoints,
                 coords[-1] + (coords[-1] - midpoints[-1])]


def read_data(filename):
    with netcdf_file(filename, "r", mmap=False) as nc:
        lat = np.asarray(nc.variables["latitude"][:], dtype=float).copy()
        lon = np.asarray(nc.variables["longitude"][:], dtype=float).copy()
        npp = np.asarray(nc.variables["npp"][:], dtype=float).copy()
    if npp.shape != (len(lat), len(lon)) or not np.isfinite(npp).any():
        raise ValueError("Invalid or empty CAFE numerical field")
    return lat, lon, npp


def plot_map(input_nc=DATA, output=OUTPUT, land=LAND, *, vmax=600):
    latitude, longitude, npp = read_data(input_nc)
    if not np.isfinite(vmax) or vmax <= 0:
        raise ValueError("vmax must be positive and finite")
    figure = plt.figure(figsize=(12.5, 7.5), dpi=140)
    ax = figure.add_axes((0.075, 0.265, 0.890, 0.660))
    cax = figure.add_axes((0.210, 0.129, 0.620, 0.027))
    ax.set_facecolor("#dfe8ee")
    cmap = plt.get_cmap("viridis").copy()
    cmap.set_bad((0, 0, 0, 0))
    mesh = ax.pcolormesh(cell_edges(longitude), cell_edges(latitude),
                         np.ma.masked_invalid(npp), cmap=cmap,
                         shading="flat", rasterized=True, vmin=0, vmax=vmax)

    # The committed Natural Earth polygon CSV supplies a portable land mask.
    polygon = []
    for raw in list(land.read_text().splitlines()) + [""]:
        line = raw.strip()
        if not line:
            if len(polygon) >= 3:
                x, y = zip(*polygon)
                ax.fill(x, y, color="#e7e8de", ec="none", zorder=3)
            polygon = []
        elif not line.startswith("#"):
            polygon.append(tuple(map(float, line.split(","))))

    for name, (lon, lat), colour, offset in (
        ("BATS", BATS, "#174a7e", (9, -20)),
        ("NABE", NABE, "#b14b19", (9, 13)),
    ):
        ax.scatter(lon, lat, s=115, color=colour, edgecolors="white",
                   linewidths=1.8, zorder=5)
        ax.annotate(name, (lon, lat), xytext=offset, textcoords="offset points",
                    fontsize=11, fontweight="bold", color=colour, zorder=6,
                    bbox=dict(facecolor="white", edgecolor="none", alpha=0.85, pad=1.6))

    ax.set(xlim=(-91, 18), ylim=(8, 68), xlabel="Longitude (°)", ylabel="Latitude (°)")
    ax.set_title("North Atlantic open-ocean net primary production · 2023", fontsize=15)
    step = 100 if vmax <= 800 else 200
    bar = figure.colorbar(mesh, cax=cax, orientation="horizontal", extend="max",
                          ticks=np.arange(0, vmax + step / 2, step))
    bar.set_label("NPP (mg C m$^{-2}$ d$^{-1}$)")
    figure.text(0.075, 0.022, "VIIRS CAFE (2023) · Ocean Productivity · water deeper than 200 m · Silsbe et al. (2016)",
                fontsize=9)

    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=140, facecolor="white", bbox_inches="tight", pad_inches=0.07)
    plt.close(figure)
    print(f"Generated {output} from {input_nc}")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DATA)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--vmax", type=float, default=600)
    args = parser.parse_args()
    plot_map(args.input, args.output, vmax=args.vmax)
