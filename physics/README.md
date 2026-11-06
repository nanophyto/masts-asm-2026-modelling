# Instructor physics: NumericalEarth CATKE columns

This optional research workflow generates **1,200 m**, **60-cell stretched**
physical BATS/NABE columns with NumericalEarth CATKE, then derives an idealised
seasonal diffusivity for the workshop ecosystem models. The physical and
biological Julia environments are intentionally separate.

The physical generator uses the **1990 JRA55 cycle** and **EN4 initial
T/S**, with a 365-day spin-up followed by a saved 365-day annual cycle.

## Generate annual physics

```bash
julia --threads=1 --project=physics -e 'using Pkg; Pkg.instantiate()'
julia --threads=1 --project=physics physics/generate_column.jl BATS 365 365
julia --threads=1 --project=physics physics/generate_column.jl NABE 365 365
```

The output JLD2 files are written below `outputs/physics/` and ignored by
Git. The physics environment pins NumericalEarth 0.8.2 and Oceananigans
0.113.6; the biology environment pins Oceananigans 0.114.1.

## Fit a smooth seasonal mixing parameterisation

```bash
julia --threads=1 --project=oceanbiome physics/fit_smooth_diffusivity.jl BATS \
  outputs/physics/bats_catke_spin365d_365d.jld2
julia --threads=1 --project=oceanbiome physics/fit_smooth_diffusivity.jl NABE \
  outputs/physics/nabe_catke_spin365d_365d.jld2
```

The fit uses the shared `physics/smooth_diffusivity_fit.jl` implementation
with vertical-temperature diagnostics from `physics/mld_temperature_diagnostic.jl`.
Use the fitted TOML via `MASTSWorkshop.column(:BATS; smooth_physics="...")`
or with `:NABE`, including `deep=true` for a 1,200 m biology column.

## Optional physical figures

`physics/plot_appendix_physics.jl` can render CATKE temperature, salinity,
horizontal wind response and diffusivity using the two saved annual JLD2 files.
These input JLD2 files are large and not committed. The public documentation
uses the analytically specified classroom forcing instead, regenerating all
its figures on CI from version-controlled code and small numerical inputs.

The 1D model can have wind-driven horizontal `u`/`v` even though vertical
fluid velocity is zero. Suspended particles still have separate gravitational
sinking velocities.
