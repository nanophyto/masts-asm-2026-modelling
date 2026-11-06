# Station map source data

`north_atlantic_land.csv` contains simplified Natural Earth coastline polygons for
plotting the BATS/NABE locator map without a GIS dependency in the Julia docs.

`prepare_satellite_npp_map.py` now builds the background field from the
**Ocean Productivity VIIRS R2022 CAFE product** and then masks the plot to
**open-ocean pixels deeper than 200 m** using the public-domain Natural Earth
10m bathymetry polygon. The polygon is downloaded as GeoJSON directly from
[Natural Earth's source repository](https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_10m_bathymetry_K_200.geojson).

Generated outputs:

- `north_atlantic_cafe_npp_2023.nc` - numerical annual-mean NPP field for the
  cropped North Atlantic domain.
- `north_atlantic_cafe_npp_2023.png` - plotted station map used in the docs.

To regenerate:

```bash
conda env create -f scripts/npp-map-environment.yml
conda activate masts-npp-map
python scripts/prepare_satellite_npp_map.py --year 2023
```

If internet access is unavailable when the script runs, it will not be able to
fetch the monthly Ocean Productivity HDF files or the Natural Earth bathymetry
GeoJSON. Monthly downloads and the unmasked annual numerical mean are cached
under `outputs/maps/cafe_monthly/`, so rerunning after a transient download
failure does not require rereading twelve monthly HDF4 files.
