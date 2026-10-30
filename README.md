# Getting started with Modelling: A practical workshop for biogeochemists

**MASTS Annual Science Meeting 2026 | 12 November 2026**

Two complementary introductions to modelling in marine biogeochemistry:

- **Data-driven modelling (Abil.py):** prepare environmental observations, train a model, evaluate predictions and interpret variable importance.
- **Mechanistic modelling (OceanBioME.jl):** run a simple LOBSTER water column, change grazing and nutrient uptake, and examine phytoplankton and particulate carbon export.

The exercises are ordinary Python and Julia scripts intended to remain useful after the workshop.

## Set up and test the environment (Cycle 1.1)

Install **Julia 1.10** and create a dedicated **Python 3.11** environment
with Anaconda or Miniconda:

```bash
conda create -n masts-2026 python=3.11 pip
conda activate masts-2026
./scripts/setup_local.sh
./scripts/test_local.sh
```

The scripts use the **active conda environment's Python** and install the
published Abil.py package there. Julia uses the separate `oceanbiome/`
project. Run the commands from the repository root. Keeping Abil outside the
conda `base` environment avoids modifying other projects' dependencies.

Use your existing Julia 1.10 installation; switching Julia versions is not
necessary. Run `julia --version` to confirm which Julia the shell selects.

`setup_local.sh` resolves the exact Julia package versions and generates
`oceanbiome/Manifest.toml` without eagerly precompiling plotting
dependencies. **Commit this manifest after the local tests pass.** CI checks for the committed manifest and runs the same Julia import
and version tests, alongside the Abil Python smoke tests. Until the manifest
is committed, the Julia CI job will fail at that check.

The Python and Julia jobs run on GitHub-hosted runners on pull requests and
pushes to `main`. CI uses Python 3.11 directly rather than installing conda;
both environments install Abil from the same `abil/requirements.txt`.
No workshop cloud resources are started by CI.

If using juliaup, run `juliaup add 1.10` and
`juliaup override set 1.10` from the repository root. Set `JULIA_BIN`
when using a custom Julia executable path.

Outputs from later modelling exercises will be written under `outputs/`
(ignored by Git).

## Development status

**Cycle 1.1:** Dependency specification and setup smoke tests.
**Cycle 1.2:** First idealised LOBSTER column and control/reduced-grazing runs.
**Cycle 1.3:** Carbon-export diagnostics at 100 m and 300 m, nitrogen budgets and figures.
**Cycle 1.3b:** Documenter.jl tutorial with executed reference results and figure validation.
The workshop Docker image and realistic station datasets belong to later cycles. Abil.py is installed and import-tested; its exercises are
prepared separately.

Begin with the reference LOBSTER column and then change grazing:

```bash
julia --threads=1 --project=oceanbiome oceanbiome/exercises/00_reference_column.jl
```

The [Documenter tutorials](docs/src/index.md) walk through the reference
model, the grazing experiment, local installation and physical forcing.

Run the 1D LOBSTER example after setup:

```bash
julia --threads=1 --project=oceanbiome oceanbiome/exercises/01_grazing.jl
```

Use `--quick` after the script name for a two-day end-to-end smoke run.

The example uses the native OceanBioME/Oceananigans model constructors, with
forcing, export diagnostics and optional plotting functions from the local
`MASTSWorkshop` Julia package. Its outputs appear under
`outputs/oceanbiome/` and are excluded from Git. The grazing experiment generates two comparison figures and CSV files
containing carbon export and nitrogen budgets; use `--quick --plot` to test
plotting on the two-day run.

## Workshop documentation

The workshop tutorials are published on GitHub Pages. They introduce the
reference column, the grazing experiment, and the physical forcing, with
figures and example results alongside the code. For independent use after
the workshop, see [Running the examples on your own system](docs/src/running_locally.md).

## Scientific notes

LOBSTER represents phytoplankton, zooplankton, nitrate, ammonium, dissolved organic matter and small/large sinking particulate matter. For teaching we convert the nitrogen-based sinking flux to carbon using C:N = 106:16 and report `g C m^-2` across exact 100 m and 300 m grid faces. Carbon export at a depth is distinct from long-term sequestration. Carbonate chemistry and atmospheric CO2 forcing are not needed for this diagnostic.

**References**

- [OceanBioME LOBSTER column example](https://oceanbiome.github.io/OceanBioME.jl/stable/generated/column/)
- [OceanBioME LOBSTER equations](https://oceanbiome.github.io/OceanBioME.jl/stable/model_components/biogeochemical/LOBSTER/)
- [Abil.py](https://github.com/nanophyto/Abil)

## Next cycle

Cycle 1.4 builds the workshop container and prepares public distribution through GitHub Container Registry.
