# Satellite NPP: numerical source for the station map

**Retained scientific input:** `north_atlantic_cafe_npp_2023.nc` (about 1 MB).
This is a numerical 2023 annual-mean VIIRS CAFE net primary production field
in mg C m⁻² d⁻¹, masked to water deeper than 200 m. The upstream product is
from [Ocean Productivity](https://orca.science.oregonstate.edu/1080.by.2160.monthly.hdf.cafe.v.php),
using [CAFE (Silsbe et al., 2016)](https://doi.org/10.1002/2016GB005521).
The 200 m ocean mask is from [Natural Earth bathymetry](https://www.naturalearthdata.com/downloads/10m-physical-vectors/).

**Retained geography:** `north_atlantic_land.csv` is a simplified Natural
Earth coastline polygon file, used to draw the land mask and BATS/NABE markers.

**Regenerated output:** `north_atlantic_cafe_npp_2023.png` is produced from
these numerical/geographic inputs on **every documentation build**, with a
fixed NPP display range of 0–600 mg C m⁻² d⁻¹ and an extended colourbar.
The generated figure, plus `docs/src/assets/station_map.png`, is ignored by Git.

Run the plot manually from the repository root (with numpy, scipy and
matplotlib installed):

```bash
python3 scripts/plot_satellite_npp_map.py
```

This map is observational geographical context, while the workshop's
idealised physical forcing represents a separate seasonally repeated 1990
JRA55/EN4 example. Both BATS and NABE biological experiments are driven by
identical biological parameters under contrasting prescribed environments.
