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


## Cycle 1.2: first LOBSTER column

From the repository root, using your tested Julia 1.10 environment:

```bash
julia --project=oceanbiome oceanbiome/exercises/01_grazing.jl
```

For a short end-to-end check of the script and output writing:

```bash
julia --project=oceanbiome oceanbiome/exercises/01_grazing.jl --quick
```

The script constructs the biological model with `PhytoZoo` and `LOBSTER`,
couples it with `NonhydrostaticModel`, initialises the seven tracers and
runs 120 days of control and reduced-grazing simulations (2 days with `--quick`). Both runs use an
identical, idealised BATS-like seasonal cycle for light and vertical mixing.
The physics and initial conditions live in `oceanbiome/src/idealised_physics.jl`.

Oceananigans writes the two sets of tracer profiles to
`outputs/oceanbiome/control.jld2` and
`outputs/oceanbiome/reduced_grazing.jld2`. The script prints the final
surface phytoplankton concentration from each output file. Cycle 1.3 adds sinking carbon-export diagnostics and comparison figures.

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

The same `01_grazing.jl` exercise now uses a **400 m, 80-cell** idealised
column. The 100 m and 300 m export horizons coincide with grid faces. For
both grazing treatments it saves:

- `control.jld2` and `reduced_grazing.jld2`: Oceananigans tracer profiles.
- `control_diagnostics.csv` and `reduced_grazing_diagnostics.csv`: surface
  phytoplankton/nitrate, downward organic-carbon export at 100 and 300 m,
  cumulative export, nitrogen inventory and approximate budget residual.
- `grazing_comparison.png`: a six-panel control-versus-experiment figure.

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

The full 120-day run creates the plot automatically. To test plotting on a
short run (which also loads and compiles CairoMakie), use:

```bash
julia --project=oceanbiome oceanbiome/exercises/01_grazing.jl --quick --plot
```

The ordinary `--quick` smoke test used in CI computes both flux and
budget diagnostics and writes CSV files without loading Makie.
