# MASTS ASM 2026 - Getting started with modelling

**Start with `01_OceanBioME/00_reference_column.jl`.** In the editor, choose
**Julia: Execute File in REPL**. Figures appear in the Julia Plot Pane in
creation order; use the plot history to revisit an earlier figure.

Choose any biological experiment and edit the clearly marked parameter in
the modified run. All use the same idealised BATS-like forcing:

- `04_light_affinity.jl` - reduce light half-saturation (higher light affinity).
- `05_nutrient_affinity.jl` - reduce nitrate half-saturation (higher nitrate affinity).
- `01_grazing.jl` - reduce zooplankton grazing.
- `02_sinking.jl` - reduce large-particle sinking speed.
- `03_remineralisation.jl` - increase particulate remineralisation.
- `06_phytoplankton_mortality.jl` - increase virus-like phytoplankton loss.

Each example contains two explicit 365-day simulations, with a common reference
and one changed parameter. Compare surface phytoplankton and nitrate, detrital
inventories, and daily/cumulative carbon export at **100 and 300 m**.

Your PNGs, JLD2 files and diagnostic CSVs are in **`results/oceanbiome/`**.
Click a PNG in Explorer or open a CSV as a table (if it opens as text, select
**Reopen Editor With -> CSV Table Viewer**). The workshop guide and scientific
explanations are available in the [documentation source](../docs/src/index.md).

The mortality exercise is a representation of **density-dependent losses**;
LOBSTER does not explicitly track viruses. We can explore it as a simple
virus-like scenario and discuss how that differs from a mechanistic infection model.

For a deeper Atlantic contrast, open `01_OceanBioME/07_bats_nabe.jl`.
It compares idealised BATS and NABE conditions on the same stretched 1200 m
grid and diagnoses particulate export at 1000 m. A two-day smoke run can be
selected with `MASTS_COMPARISON_DAYS=2`; the default run lasts 365 days.
The Python/Abil.py practical is provided separately.

From this folder, the reference can also be run in a terminal:

```bash
julia --project=../oceanbiome 01_OceanBioME/00_reference_column.jl
```
