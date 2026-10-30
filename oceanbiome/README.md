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
surface phytoplankton concentration from each output file. Carbon export
and its associated figures are the focus of Cycle 1.3.

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
