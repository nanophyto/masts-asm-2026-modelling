# MASTSWorkshop.jl - workshop biology environment

This local Julia package combines Oceananigans 0.114.1, OceanBioME 0.20.1 and
CairoMakie 0.15.16 (all pinned in `oceanbiome/Manifest.toml`) for the
MASTS ASM 2026 hands-on modelling exercises.

## Install and test

From the repository root, use Julia 1.10:

```bash
julia --threads=1 --project=oceanbiome -e 'using Pkg; Pkg.instantiate()'
julia --threads=1 --project=oceanbiome oceanbiome/test/runtests.jl
```

The scientific tests exercise column construction, conservation diagnostics,
particle sinking, BATS/NABE forcing and the optional offline/smooth physics
interfaces. The CI documentation job runs each **full 365-day experiment**
and checks that its figures and diagnostic CSVs are valid.

## Workshop examples

```bash
julia --threads=1 --project=oceanbiome workshop/01_OceanBioME/00_reference_column.jl
julia --threads=1 --project=oceanbiome workshop/01_OceanBioME/01_grazing.jl
julia --threads=1 --project=oceanbiome workshop/01_OceanBioME/07_bats_nabe.jl
```

Additional examples cover particle sinking, remineralisation, light affinity,
nutrient affinity and phytoplankton mortality. They use **30 uniform 10 m
cells over 300 m** by default; `MASTSWorkshop.column(:BATS; deep=true)` and
`:NABE` produce a stretched 60-cell 1,200 m grid. Export horizons include
100/300 m, and 1,000 m for deep runs. Each annual exercise writes its own
JLD2, PNG and CSV results beneath `workshop/results/` (ignored by Git).

## Rebuild the complete documentation

```bash
python -m pip install numpy scipy matplotlib
julia --threads=1 --project=docs docs/make.jl
python scripts/check_documentation_images.py docs/build
```

The documentation rebuilds plots and content in fresh output directories.
Its CAFE NPP background is generated from the small numerical NetCDF input
in `data/maps/` and does not need network access or HDF4 support.

For the optional NumericalEarth CATKE research workflow, see
[`physics/README.md`](../physics/README.md).
