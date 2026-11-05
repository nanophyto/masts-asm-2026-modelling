# NumericalEarth CATKE → offline OceanBioME (1D)

A 1200 m **physical 1D column** generates face-located tracer diffusivity with
NumericalEarth.jl's established CATKE turbulence closure. A separate
Oceananigans/OceanBioME **biological 1D column** then uses that diffusivity with
vertically implicit tracer transport. Both BATS and NABE use the same 60-cell
stretched physical grid and the workshop's existing 300 m / 1200 m biological grids.

## 1. Install the physical environment

From the repository root (Julia 1.10):

```bash
julia --threads=1 --project=physics -e 'using Pkg; Pkg.instantiate()'
```

The separate physics project pins NumericalEarth **0.8.2** and Oceananigans
**0.113.6**; the OceanBioME project retains Oceananigans **0.114.1**. Once the
setup is confirmed, commit `physics/Manifest.toml` to reproduce the dependency
resolution. Neither physics package is added to the participant environment.

## 2. Short smoke tests

The existing two-day commands remain valid and begin saving immediately:

```bash
julia --threads=1 --project=physics physics/generate_column.jl BATS 2
julia --threads=1 --project=physics physics/generate_column.jl NABE 2
julia --threads=1 --project=oceanbiome physics/test_offline_biology.jl BATS outputs/physics/bats_catke_2d.jld2
```

The generator uses EN4's January 1990 hydrography and **the entire 1990
RepeatYearJRA55 cycle** even for short tests. JRA55's 3-hourly record spans
January 1 to December 31; `Cyclical(365days)` supplies the explicit full-year
period for both instantaneous atmospheric fields and window-mean fluxes. The
window-mean series may still issue a generic 1.5-hour interpolation-edge
warning, but it now wraps the full annual record rather than a short fragment.

## 3. Annual physics with spin-up

The CLI accepts `STATION [output_days=2] [spinup_days=0] [output_hours=3]`.
For **one year of spin-up and one saved year**, run:

```bash
julia --threads=1 --project=physics physics/generate_column.jl BATS 365 365
julia --threads=1 --project=physics physics/generate_column.jl NABE 365 365
```

Equivalently, in Julia:

```julia
include("physics/generate_column.jl")
generate(:BATS; spinup_days = 365, output_days = 365, output_hours = 3)
```

These continuous 730-day integrations output:

```text
outputs/physics/
  bats_catke_spin365d_365d.jld2
  bats_catke_spin365d_365d_spinup_daily.jld2
  bats_catke_spin365d_365d.provenance.txt
  nabe_catke_spin365d_365d.jld2
  nabe_catke_spin365d_365d_spinup_daily.jld2
  nabe_catke_spin365d_365d.provenance.txt
```

The primary file contains **only the second year** (days 365–730), including
both endpoints at 3-hour intervals. The small companion file saves daily
snapshots from the last spin-up year (days 0–365), enabling a same-season
comparison. Both contain `κc` at faces and temperature/salinity at centres;
no velocities are written.

The native JLD2 timestamps retain the continuous physical clock.
`MASTSWorkshop.load_offline_physics` subtracts the **first saved time**, so
an OceanBioME column starts at time zero with the start of the saved year.
The reader interpolates between saved snapshots without repeating the year.

A longer spin-up is selected by changing the second number (e.g. `365 730`
for two spin-up years). The diagnostic file still contains only the **last**
365 days of that spin-up period.

## 4. Validate the physical seasonal cycle

After the BATS and NABE annual integrations:

```bash
julia --threads=1 --project=oceanbiome physics/validate_seasonal_physics.jl BATS outputs/physics/bats_catke_spin365d_365d.jld2
julia --threads=1 --project=oceanbiome physics/validate_seasonal_physics.jl NABE outputs/physics/nabe_catke_spin365d_365d.jld2
```

The validation writes a PNG and Markdown summary beside each forcing file.
It compares the last spin-up year to the output year for temperature-derived
mixed-layer depth, temperature and salinity at 10 m and 100 m. With the
prepared `data/observations/gosml_mld_bats_nabe.csv`, it also plots NOAA GOSML
monthly means and reports the model MLD RMSE/bias. If that file is missing,
prepare it in the established isolated environment:

```bash
conda run -n masts-gosml python scripts/prepare_mld_climatology.py
```

The MLD definition follows de Boyer Montégut et al. (2004): the first depth
where the magnitude of the temperature difference from 10 m exceeds 0.2 °C.
The diagnostic returns the deepest cell centre when no crossing occurs, so
bottom-limited mixed layers should be inspected. These diagnostics assess
adjustment and hydrographic drift; observations determine whether the seasonal
cycle is representative. EN4 supplies the initial T/S, while GOSML provides an
independent seasonal MLD comparison.

The existing two-day mixing comparison is also available for the annual files:

```bash
julia --threads=1 --project=oceanbiome physics/plot_diffusivity.jl BATS outputs/physics/bats_catke_spin365d_365d.jld2
```

## 5. Run offline biology

```bash
julia --threads=1 --project=oceanbiome physics/test_offline_biology.jl BATS outputs/physics/bats_catke_spin365d_365d.jld2
julia --threads=1 --project=oceanbiome oceanbiome/test/runtests.jl
```

```julia
using MASTSWorkshop
config = column(:BATS; deep = true,
                offline_physics = "outputs/physics/bats_catke_spin365d_365d.jld2")
```

The biological runs retain the workshop's NASA POWER-derived PAR. The offline
transport reads CATKE's face diffusivity and evolves only the biological
tracers. T/S and MLD are physical diagnostics; the current LOBSTER model does
not yet use temperature-dependent biological rates.

**References**: [NumericalEarth single-column example](https://numericalearth.github.io/NumericalEarthDocumentation/stable/literated/single_column_os_papa_simulation/);
[de Boyer Montégut et al. (2004), JGR](https://doi.org/10.1029/2004JC002378).
