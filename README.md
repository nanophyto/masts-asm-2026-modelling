# MASTS ASM 2026 modelling materials

This repository contains the OceanBioME workshop exercises, supporting data,
and the Documenter source used for the accompanying notes.

## If you downloaded a zip file

From a terminal:

```bash
unzip npp_doc_work.zip
cd npp_doc_work
```

If your zip has a different filename, substitute that instead.

Then start with:

- `workshop/START_HERE.md` for the hands-on exercises
- `docs/src/index.md` for the documentation source
- `oceanbiome/README.md` for the Julia package environment

## Quick workshop run

From the repository root:

```bash
cd workshop
julia --project=../oceanbiome 01_OceanBioME/00_reference_column.jl
```

## Regenerating the BATS/NABE locator map

The station map now uses the **VIIRS CAFE** satellite productivity product,
masked to **open-ocean waters deeper than 200 m**.

```bash
conda env create -f scripts/npp-map-environment.yml
conda activate masts-npp-map
python scripts/prepare_satellite_npp_map.py --year 2023
```
