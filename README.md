# MASTS ASM 2026 — Modelling for biogeochemists

A practical OceanBioME/Julia workshop with the BATS and NABE column comparison,
biological parameter experiments, and a separate Abil.py exercise.

- [Participant starting instructions](workshop/START_HERE.md)
- [Julia environment and scientific tests](oceanbiome/README.md)
- [Optional NumericalEarth physics](physics/README.md)
- [Running on your own system](docs/src/running_locally.md)

## Rebuild the documentation

Documentation figures, 365-day model output, console summaries and the Pages
site are **generated anew by GitHub Actions** on every PR and on `main`.
Their source files and the small curated observations are committed; generated
PNGs, CSV summaries, JLD2 outputs and HTML are ignored by Git.

```bash
python -m pip install numpy scipy matplotlib
julia --threads=1 --project=docs docs/make.jl
python scripts/check_documentation_images.py docs/build
```

The numerical 2023 VIIRS CAFE map input is retained at
`data/maps/north_atlantic_cafe_npp_2023.nc`. Its PNG and the other published
figures are regenerated from source code, with no upstream downloads during
CI builds.

## Run scientific smoke tests

```bash
julia --threads=1 --project=oceanbiome oceanbiome/test/runtests.jl
python -m unittest discover -s abil/tests -p 'test_*.py' -v
```

The full scientific documentation build also validates the figures and annual
budget checks for every exercise. The container image can be tested through
the manual publish-workflow and `scripts/test_container.sh`.
