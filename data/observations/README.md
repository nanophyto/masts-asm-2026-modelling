# BATS/NABE reference climatologies

This directory retains small, sourced **numerical observational inputs** used
to evaluate the idealised physical forcing. They are *inputs and provenance*,
not simulation or documentation outputs.

- `gosml_mld_bats_nabe.csv` and `.metadata.json`: NOAA GOSML mixed-layer-depth
  reference for BATS and NABE. Source: Johnson and Lyman (2022),
  [JGR: Oceans](https://doi.org/10.1029/2021JC018219). The CSV contains
  monthly mean and percentile mixed-layer depths with valid spatial support.
- `nasa_power_par_bats_nabe.csv` and `.metadata.json`: NASA POWER 2001–2020
  monthly surface photosynthetically active radiation climatology.
  The corresponding fitted coefficients used in the classroom are committed as
  `oceanbiome/src/par_forcing_coefficients.jl`.

The workshop's published plots are calculated directly from the current
seasonal forcing functions. These CSVs and provenance records remain available
for comparing the forcing to observations when preparing future exercises.
The documentation build reads local inputs and runs entirely without upstream
observation-server downloads.
