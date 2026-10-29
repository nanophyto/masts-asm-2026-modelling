# OceanBioME: Julia environment

The Julia environment provides OceanBioME, Oceananigans and CairoMakie for the
mechanistic modelling exercises. Cycle 1.1 establishes and tests these
scientific dependencies. The first LOBSTER column will be implemented in Cycle 1.2.

From the repository root, with Julia 1.13.3 installed and a Python 3.11 conda environment activated:

```bash
./scripts/setup_local.sh
./scripts/test_local.sh
```

`setup_local.sh` generates `oceanbiome/Manifest.toml` using Julia's package
resolver. **Commit the generated manifest after successful local testing** to
make subsequent installations reproducible. The smoke test checks that the
locked packages import at their intended versions.
