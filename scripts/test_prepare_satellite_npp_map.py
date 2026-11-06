from pathlib import Path
import gzip
import tempfile

import numpy as np
import rasterio
from rasterio.transform import from_origin

import prepare_satellite_npp_map as npp


def _synthetic_hdf_gz(path, data):
    tif_path = path.with_suffix("")
    transform = from_origin(-91.0, 68.0, 1.0 / 6.0, 1.0 / 6.0)
    with rasterio.open(
        tif_path,
        "w",
        driver="GTiff",
        height=data.shape[0],
        width=data.shape[1],
        count=1,
        dtype="float32",
        transform=transform,
    ) as dst:
        dst.write(np.asarray(data, dtype=np.float32), 1)
    with open(tif_path, "rb") as source, gzip.open(path, "wb") as target:
        target.write(source.read())
    tif_path.unlink()
    return path


def test_monthly_file_uses_cafe_naming():
    assert npp.monthly_file(2023, 1) == "cafe.2023001.hdf.gz"
    assert npp.monthly_file(2024, 2) == "cafe.2024032.hdf.gz"


def test_annual_mean_day_weights():
    fields = [np.full((2, 2), month, dtype=np.float32) for month in range(1, 13)]
    mean = npp.annual_mean(fields, year=2023)
    expected = sum(month * days for month, days in enumerate(
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31], 1
    )) / 365
    assert np.allclose(mean, expected)


def test_read_month_accepts_small_synthetic_raster():
    with tempfile.TemporaryDirectory() as tmp:
        gz_path = Path(tmp) / "cafe.2023001.hdf.gz"
        latitude, longitude = npp.grid()
        data = np.full((len(latitude), len(longitude)), 123.0, dtype=np.float32)
        data[3, 5] = -9999.0
        _synthetic_hdf_gz(gz_path, data)
        lat, lon, values = npp.read_month(gz_path)
    assert lat.shape == latitude.shape
    assert lon.shape == longitude.shape
    assert values.shape == data.shape
    assert np.isclose(values[0, 0], 123.0)
    assert np.isnan(values[3, 5])


def test_crop_global_flips_north_first_rows():
    # 4 x 8 grid: northernmost source row must be mapped to highest latitude.
    source = np.zeros((4, 8), dtype=np.float32)
    source[0, 1] = 123.0  # 67.5 N, 112.5 W
    source[-1, 1] = 456.0  # 67.5 S, 112.5 W
    lat, lon, values = npp.crop_global(source, bounds=(-180, 180, -90, 90))
    assert np.all(np.diff(lat) > 0)
    assert values[-1, 1] == 123.0
    assert values[0, 1] == 456.0
    assert lon[1] == -112.5


def test_bathymetry_url_points_to_source_geojson():
    assert npp.BATHYMETRY_URL.startswith("https://raw.githubusercontent.com/nvkelso/")
    assert npp.BATHYMETRY_URL.endswith("ne_10m_bathymetry_K_200.geojson")
    assert npp.bathymetry_mask_path(Path("cache")).suffix == ".geojson"


def test_200m_bathymetry_mask_uses_geojson_and_south_north_orientation():
    import json

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        geometry = {"type": "Polygon", "coordinates": [[
            [1.0, 0.0], [2.0, 0.0], [2.0, 2.0], [1.0, 2.0], [1.0, 0.0]
        ]]}
        data = {"type": "FeatureCollection", "features": [
            {"type": "Feature", "geometry": geometry, "properties": {"depth": 200}}
        ]}
        bathymetry = root / "ne_10m_bathymetry_K_200.geojson"
        bathymetry.write_text(json.dumps(data))
        mask = npp.load_open_ocean_mask(
            np.array([0.5, 1.5]), np.array([0.5, 1.5]), bathymetry
        )
        assert mask.tolist() == [[False, True], [False, True]]
        annual = np.array([[100.0, 200.0], [300.0, 400.0]])
        masked = npp.apply_open_ocean_mask(annual, mask)
        assert np.isnan(masked[:, 0]).all()
        assert masked[:, 1].tolist() == [200.0, 400.0]


def test_annual_cache_skips_monthly_reprocessing_after_failure(monkeypatch):
    import sys
    import json

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        cache = root / "cache"
        cache.mkdir()
        # Use the script's full-size grid so the plotting and NetCDF paths
        # exercise the same code as a real annual mean.
        latitude, longitude = npp.grid()
        array = np.full((len(latitude), len(longitude)), 300.0, dtype=np.float32)
        np.savez_compressed(cache / "north_atlantic_cafe_2023_annual_unmasked.npz",
                            latitude=latitude, longitude=longitude, npp=array)
        shape = {"type": "Polygon", "coordinates": [[
            [-80.0, 15.0], [0.0, 15.0], [0.0, 60.0], [-80.0, 60.0], [-80.0, 15.0]
        ]]}
        bathymetry = cache / "ne_10m_bathymetry_K_200.geojson"
        bathymetry.write_text(json.dumps({"type": "FeatureCollection", "features": [
            {"type": "Feature", "geometry": shape, "properties": {"depth": 200}}
        ]}))
        figure = root / "map.png"
        netcdf = root / "map.nc"
        # The GeoJSON is already cached. Any unexpected monthly download fails.
        def cached_only(url, destination):
            if not destination.is_file():
                raise AssertionError(f"Unexpected download: {url}")
            return destination
        monkeypatch.setattr(npp, "fetch", cached_only)
        original_root = npp.ROOT
        try:
            npp.ROOT = root
            (root / "data" / "maps").mkdir(parents=True)
            # A blank coastline file is enough to exercise the map writer.
            (root / "data" / "maps" / "north_atlantic_land.csv").write_text("")
            monkeypatch.setattr(sys, "argv", ["prepare_satellite_npp_map.py", "--year", "2023",
                                           "--cache", str(cache), "--netcdf", str(netcdf),
                                           "--figure", str(figure)])
            npp.main()
        finally:
            npp.ROOT = original_root
        assert figure.is_file() and figure.stat().st_size > 10000
        assert netcdf.is_file()
        _, _, npp_values = npp.read_netcdf(netcdf)
        assert np.isnan(npp_values[0, 0])
        assert np.isfinite(npp_values[100, 100])


def test_station_map_uses_full_width_and_1200_colourbar(tmp_path, monkeypatch):
    from matplotlib.figure import Figure

    latitude, longitude = npp.grid()
    # Deterministic synthetic NPP values to test layout without downloading data.
    y = np.linspace(0.0, 1.0, len(latitude), dtype=np.float32)[:, None]
    x = np.linspace(0.0, 1.0, len(longitude), dtype=np.float32)[None, :]
    values = (150.0 + 900.0 * y * (0.5 + 0.5 * x)).astype(np.float32)
    values[:12, :12] = np.nan
    path = tmp_path / "station_map.nc"
    npp.write_netcdf(path, latitude, longitude, values, 2023)
    figure_path = tmp_path / "station_map.png"
    land_csv = tmp_path / "land.csv"
    land_csv.write_text("")

    original = Figure.savefig
    saved = []

    def capture(fig, *args, **kwargs):
        saved.append(fig)
        return original(fig, *args, **kwargs)

    monkeypatch.setattr(Figure, "savefig", capture)
    npp.plot_map(path, figure_path, land_csv, 2023)

    assert figure_path.stat().st_size > 20_000
    (fig,) = saved
    map_ax, colourbar_ax = fig.axes
    assert map_ax.get_position().x1 > 0.85
    assert colourbar_ax.get_position().x0 > map_ax.get_position().x1
    assert colourbar_ax.get_position().x1 >= 0.9
    assert np.isclose(map_ax.collections[0].norm.vmax, 1200)
    np.testing.assert_allclose(colourbar_ax.get_yticks(), np.arange(0, 1201, 200))
    assert map_ax.collections[0].get_coordinates().shape == (
        len(latitude) + 1, len(longitude) + 1, 2
    )
