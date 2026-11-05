# Offline one-dimensional physical forcing for OceanBioME

This directory runs a **physical 1D column** with the established
[NumericalEarth single-column configuration](https://numericalearth.github.io/NumericalEarthDocumentation/stable/literated/single_column_os_papa_simulation/).
The physical simulation uses Oceananigans' published **CATKE** vertical turbulence
closure. The resulting time-dependent, face-located tracer diffusivity is
loaded by a separate **1D OceanBioME column**, which retains Oceananigans'
vertically implicit tracer diffusion.

The physics generator and the biological workshop have **separate Julia
projects**. NumericalEarth is not a dependency of the participant environment.

## 1. Install the offline physics environment

From the repository root (Julia 1.10):

```bash
julia --threads=1 --project=physics -e 'using Pkg; Pkg.instantiate()'
```

On first successful installation, commit `physics/Manifest.toml` to pin the
validated physical model and its dependencies. The provided `Project.toml`
selects **NumericalEarth v0.8.2** and **Oceananigans v0.113.6**, a
compatible pair. NumericalEarth v0.8.2 accepts Oceananigans v0.111–v0.113;
the physics generator therefore pins the final v0.113 release. The separate
OceanBioME environment continues to use Oceananigans v0.114.1. The native
JLD2 hand-off is checked by the offline coupling tests after installation.

## 2. Generate physical columns

Start with two days to verify external EN4 and JRA55 data access:

```bash
julia --threads=1 --project=physics physics/generate_column.jl BATS 2
julia --threads=1 --project=physics physics/generate_column.jl NABE 2
```

Once the two-day simulations have been checked, generate one year:

```bash
julia --threads=1 --project=physics physics/generate_column.jl BATS 365
julia --threads=1 --project=physics physics/generate_column.jl NABE 365
```

The output files live under `outputs/physics/` by default. The generator follows
the published NumericalEarth ingredients:

- BATS (`31.67 N, 64.17 W`) and NABE (`47 N, 20 W`) point columns.
- 1200 m depth, 60 stretched vertical cells, sharing faces with the deep
  biological teaching columns.
- EN4 January 1990 temperature and salinity profiles, and repeat-year JRA55
  atmospheric and radiative forcing beginning on 1 January 1990.
- CATKE vertical turbulent diffusivity and a TEOS-10 equation of state,
  simulated with 10-minute steps; 3-hourly output by default.

The source data are downloaded by NumericalEarth on first use. Oceananigans
writes only `κc` (m² s⁻¹, vertical faces), `T` (°C, cell centres), and `S`
(g/kg, cell centres) to the offline files. Salinity is retained for subsequent
stratification/MLD assessment. No horizontal or vertical water velocity is
required by the biological column.

## 3. Test the offline biological coupling

```bash
julia --threads=1 --project=oceanbiome oceanbiome/test/runtests.jl
julia --threads=1 --project=oceanbiome physics/test_offline_biology.jl BATS outputs/physics/bats_catke_2d.jld2
julia --threads=1 --project=oceanbiome physics/test_offline_biology.jl NABE outputs/physics/nabe_catke_2d.jld2
```

Plot each CATKE result against the existing idealised mixing field:

```bash
julia --threads=1 --project=oceanbiome physics/plot_diffusivity.jl BATS outputs/physics/bats_catke_2d.jld2
julia --threads=1 --project=oceanbiome physics/plot_diffusivity.jl NABE outputs/physics/nabe_catke_2d.jld2
```

Then use the offline mixing from an annual physical run in a regular
OceanBioME column:

```julia
using MASTSWorkshop
config = column(:BATS; deep=true,
                offline_physics="outputs/physics/bats_catke_365d.jld2")
# config.grid, config.closure, config.initial, config.surface_PAR work with
# the existing LOBSTER + NonhydrostaticModel construction.
```

The reader loads `κc` at its native face levels and linearly interpolates
in depth and time, without changing the CATKE coefficients. It preserves
both 300 m teaching and 1200 m deep columns; `offline_physics=nothing`
retains the existing idealised forcing.

The model time must be covered by the physical output file. The first output
snapshot is held over the initial interval if writing starts after time zero;
subsequent times are interpolated without repeating the physical year.

## 4. Physical assessment before choosing the reference

Compare the generated mixing fields and the T/S-derived mixed-layer depth
against the existing idealised profiles and GOSML. Because this column evolves
without lateral exchange, inspect any hydrographic drift before using its
annual results as the standard teaching reference. The published NASA POWER PAR
fits remain the input to the biology; the NumericalEarth radiation is used for
the physical heat budget.

The physics files are model outputs rather than observation products. We will
adopt annual physical forcing after the two-day integration and its seasonal
MLD are validated on the workstation.
