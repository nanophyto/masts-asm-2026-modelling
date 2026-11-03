# Getting started with Modelling: A practical workshop for biogeochemists

**MASTS Annual Science Meeting 2026 | 12 November 2026**

Two complementary introductions to modelling in marine biogeochemistry:

- **Data-driven modelling (Abil.py):** prepare environmental observations, train a model, evaluate predictions and interpret variable importance.
- **Mechanistic modelling (OceanBioME.jl):** run a simple LOBSTER water column, change grazing and nutrient uptake, and examine phytoplankton and particulate carbon export.

The exercises are ordinary Python and Julia scripts intended to remain useful after the workshop.

### Workstation first-run preparation

The combined Docker image can pre-warm the Julia editor environments and run
the 365-day reference column once per participant's persistent workstation
home. Enable `MASTS_WARMUP_ON_START=1` in the Cloud Workstations container
configuration and start the instances before the session. Check readiness with
`python /opt/workshop/warmup_workstation.py status` inside a workstation.
An optional PackageCompiler sysimage build and a cold-run comparison are
available in [container/README.md](container/README.md); these keep the
Julia 1.10 scientific environment and Julia 1.11 editor runtime separate.

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

Participant results are written under `workshop/results/` (ignored by Git).

## Development status

**Cycle 1.1:** Dependency specification and setup smoke tests.
**Cycle 1.2:** First idealised LOBSTER column and control/reduced-grazing runs.
**Cycle 1.3:** Carbon-export diagnostics at 100 m and 300 m, nitrogen budgets and figures.
**Cycle 1.3b:** Documenter.jl tutorial with executed reference results and figure validation.
Cycle 1.4 includes the combined Code OSS workshop image and an opt-in GHCR publication workflow. Abil.py is installed and import-tested; its exercises are prepared separately.

The participant-facing folder is [`workshop/`](workshop/). Begin with the reference
LOBSTER column and then change grazing:

```bash
julia --threads=1 --project=oceanbiome workshop/01_OceanBioME/00_reference_column.jl
```

The [Documenter tutorials](docs/src/index.md) walk through the reference
model, the grazing experiment, local installation and physical forcing.

Run the 1D LOBSTER example after setup:

```bash
julia --threads=1 --project=oceanbiome workshop/01_OceanBioME/01_grazing.jl
```


### Column configuration

Both teaching exercises run a 500 m water column with **50 vertical cells**
(10 m spacing), a **30-minute time step**, and vertically implicit diffusion.
The particle-sinking Courant number is checked in the Julia test suite for the
reference and reduced-grazing parameter sets. In the 365-day comparison with
the original column, this configuration ran about six times faster, with
cumulative export differences of 4.0% at 100 m and 4.4% at 300 m.

`MASTSWorkshop.column(:BATS)` prepares the idealised BATS-like physics and
numerical settings. The exercises use native OceanBioME/Oceananigans
constructors and write their figures and diagnostics to
`workshop/results/oceanbiome/`.

## Workshop documentation

The workshop tutorials are published on GitHub Pages. They introduce the
reference column, the grazing experiment, and the physical forcing, with
figures and example results alongside the code. For independent use after
the workshop, see [Running the examples on your own system](docs/src/running_locally.md).

## Scientific notes

LOBSTER represents phytoplankton, zooplankton, nitrate, ammonium, dissolved organic matter and small/large sinking particulate matter. For teaching we convert the nitrogen-based sinking flux to carbon using C:N = 106:16 and diagnose export at 50 m intervals to 500 m, including the 100 m and 300 m reference horizons. The tutorial compares the simulated export profile with a Martin power law. Carbon export at a depth is distinct from long-term sequestration. Carbonate chemistry and atmospheric CO2 forcing are not needed for this diagnostic.

**References**

- [OceanBioME LOBSTER column example](https://oceanbiome.github.io/OceanBioME.jl/stable/generated/column/)
- [OceanBioME LOBSTER equations](https://oceanbiome.github.io/OceanBioME.jl/stable/model_components/biogeochemical/LOBSTER/)
- [Abil.py](https://github.com/nanophyto/Abil)

## Combined workshop container

The [workshop container](container/README.md) includes the browser-based
Code OSS editor, Julia 1.10, OceanBioME, CairoMakie and Python 3.11 with
Abil.py. It uses one Julia thread per column and ships with preinstalled,
precompiled dependencies.

Build and smoke-test it from the repository root:

```bash
docker build --platform linux/amd64 -f container/Dockerfile -t masts-asm-2026-modelling:local .
./scripts/test_container.sh masts-asm-2026-modelling:local
```

The public GitHub Container Registry image can be published manually after
running the image's tests. The [container instructions](container/README.md)
cover the local browser editor and public image access.

## Next cycle

PR 2 establishes the Google Cloud Workstations cluster, participant access,
and the tested image deployment.

### Julia editor compatibility

The workshop uses Julia 1.10.12 for simulations and Julia 1.11.9
for Code OSS language-server indexing. Both runtimes are installed by the
container; the Julia REPL and terminal continue to use Julia 1.10.12.

