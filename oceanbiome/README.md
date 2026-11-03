# OceanBioME: Julia environment

The Julia environment provides OceanBioME, Oceananigans and CairoMakie for the
mechanistic modelling exercises. Cycle 1.1 establishes and tests these
scientific dependencies. Cycle 1.2 adds a first idealised LOBSTER water column and a grazing experiment.

From the repository root, with Julia 1.10 installed and a Python 3.11 conda environment activated:

```bash
./scripts/setup_local.sh
./scripts/test_local.sh
```

`setup_local.sh` generates `oceanbiome/Manifest.toml` using Julia's package
resolver. **Commit the generated manifest after successful local testing** to
make subsequent installations reproducible. The smoke test imports
OceanBioME and Oceananigans and verifies their locked versions. It checks
CairoMakie's installed version without loading Makie. Plotting precompilation is deferred to the later workshop image build.


## Instructor reference column

Run `julia --threads=1 --project=oceanbiome workshop/01_OceanBioME/00_reference_column.jl`
for the single-column walkthrough. The follow-up `01_grazing.jl` changes
one parameter and compares two runs. Documenter provides separate pages
for these exercises, local setup and physical forcing.

## Cycle 1.2: first LOBSTER column

From the repository root, using your tested Julia 1.10 environment:

```bash
julia --threads=1 --project=oceanbiome workshop/01_OceanBioME/01_grazing.jl
```

The script constructs the biological model with `PhytoZoo` and `LOBSTER`,
couples it with `NonhydrostaticModel`, initialises all seven tracers and runs
365 days of control and reduced-grazing simulations. Both use the same
idealised BATS-like light and mixing, prepared by `MASTSWorkshop.column(:BATS)`.

Oceananigans writes the two tracer-profile files to
`workshop/results/oceanbiome/grazing/`. The script prints the final surface
phytoplankton concentrations and saves export, budget and figure diagnostics.

Run the existing tests again with:

```bash
./scripts/test_local.sh
```

The tests exercise native OceanBioME model construction, identical initial
conditions, parameter propagation, a short control-versus-perturbation run,
finite concentrations and a biological response. They use a shorter
simulation than the participant example to keep CI efficient.

See the [official OceanBioME column example](https://oceanbiome.github.io/OceanBioME.jl/stable/generated/column/)
for the same core constructors and output-writing conventions.

## Cycle 1.3: sinking organic-carbon export and budgets

The same `01_grazing.jl` exercise now uses a **500 m, 50-cell** idealised
column. Export is diagnosed every 50 m from 50 to 500 m; the 100 m
and 300 m horizons coincide with grid faces. For both grazing treatments it saves:

- `control.jld2` and `reduced_grazing.jld2`: Oceananigans tracer profiles.
- `control_export_profile.csv` and `reduced_grazing_export_profile.csv`:
  depth-resolved sinking flux, late-period mean flux and integrated export.
- `control_diagnostics.csv` and `reduced_grazing_diagnostics.csv`: surface
  phytoplankton/nitrate, downward organic-carbon export at 100 and 300 m,
  cumulative export, nitrogen inventory and approximate budget residual.
- `grazing_response.png`: control, reduced grazing and their differences.
- `carbon_export.png`: daily and cumulative export at both horizons, including differences.

The CSV has time in days, instantaneous flux in `mg C m^-2 day^-1` and
cumulative export in `g C m^-2`. LOBSTER's particulate tracers are in
`mmol N m^-3`; the fixed conversion is **106 mol C : 16 mol N** and
**12.011 mg C/mmol C**. Downward-positive export is computed from the
OceanBioME sinking velocity at each face and the tracer concentration in
the cell immediately above it (a simple upwind diagnostic).

The budget compares changes in the **total nitrogen inventory across all
seven LOBSTER pools** with cumulative sinking loss at the bottom of the
open column. No external nitrogen source or deep restoring is imposed at
this stage. Since the reported flux uses profile snapshots and a simple
upwind face estimate, the residual is a numerical/sampling diagnostic.
It can be reduced by saving profiles more frequently.

The full 365-day grazing run creates both comparison figures. The reference
column produces `reference_vertical_evolution.png`,
`reference_carbon_export.png`, `reference_martin_curve.png`, and
`reference_physics.png`. The export-profile figure compares final 90-day
mean model fluxes to the Martin et al. (1987) power-law reference anchored
at 100 m, and shows cumulative export over the full simulated year.
The annual grazing script produces the comparison figures. The test suite
uses short two-day model runs to validate scientific and numerical behaviour.

## Column resolution and time step

The two teaching exercises use **50 cells over 500 m** (10 m spacing),
a **30-minute time step**, and vertically implicit diffusion.
Particle sinking remains explicit; the Julia test suite checks its Courant
number for both grazing configurations. The chosen configuration was validated over a full
365-day seasonal cycle, including carbon export and nitrogen conservation.

## Workshop tutorials

The GitHub Pages tutorial introduces the reference column, the grazing
experiment and the physical forcing, with simulation results and figures.
Participants can follow the published walkthrough and run the examples
directly using the commands above.

## Reusable workshop package

The `oceanbiome/` Julia project also contains a local package named
`MASTSWorkshop`. Exercises import its physical forcing and diagnostics with
`using MASTSWorkshop`. Loading `CairoMakie` enables its plotting methods via a
Julia package extension; numerical tests load the lightweight functions.

After changing the project definition, refresh and commit your local manifest:

```bash
julia --threads=1 --project=oceanbiome -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
```

Use `julia --threads=1` when running the single-column examples.

After updating the column configuration, regenerate the reference figures with
`julia --project=docs docs/make.jl`. For subsequent documentation-only
corrections, reuse those generated results:

```bash
DOCS_REUSE_RESULTS=true julia --project=docs docs/make.jl
```

This uses the figures and diagnostics under `outputs/oceanbiome/reference_docs/`.
