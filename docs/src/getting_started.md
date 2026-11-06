# Getting started

## On a workshop Cloud Workstation

Open your personal workshop link and sign in with your assigned `nanophyto.org`
account. The link opens the participant `workshop/` directory containing the
OceanBioME examples, Python material, and a `results/` folder.

Open **`01_OceanBioME/00_reference_column.jl`** and use **Julia: Execute File
in REPL** from the Command Palette (`Ctrl+Shift+P`). Reuse the same REPL to
run another example. Julia Plot Pane history keeps the displayed figures.
Saved PNGs and CSVs are in `results/oceanbiome/`. Use `Ctrl+B` and
`Ctrl+Shift+E` to restore Explorer if required.

## Choose a scientific question

Each biological example changes one parameter between two 365-day columns.
The reference seasonal forcing is identical in both treatments.

1. [Light affinity](generated/04_light_affinity.md): reduce light half-saturation.
2. [Nutrient affinity](generated/05_nutrient_affinity.md): reduce nitrate half-saturation.
3. [Grazing](generated/01_grazing.md): reduce zooplankton grazing.
4. [Particle sinking](generated/02_sinking.md): reduce large-particle sinking speed.
5. [Remineralisation](generated/03_remineralisation.md): increase particulate recycling.
6. [Phytoplankton mortality](generated/06_phytoplankton_mortality.md): increase density-dependent losses.

Begin with the [reference column](generated/00_reference_column.md) to see
how the model is constructed. The
[physical-forcing appendix](generated/physical_forcing.md) explains the
prepared light and mixing conditions used by every exercise.

For the physical setting, see the [BATS and NABE comparison](generated/07_bats_nabe.md)
for a location map, seasonal light and mixing depth, and upper-300 m
vertical diffusivity.

The mortality experiment provides a simple analogue of virus-like losses.
The LOBSTER model has no separate virus population or infection process.

For local installations and scripts, see
[Running on your own system](running_locally.md).
