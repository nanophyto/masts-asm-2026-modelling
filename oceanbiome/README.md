# OceanBioME: Julia environment

The Julia environment provides OceanBioME, Oceananigans and CairoMakie for the
mechanistic modelling exercises. Cycle 1.1 establishes and tests these
scientific dependencies. The first LOBSTER column will be implemented in Cycle 1.2.

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
