# MASTS ASM 2026 - Modelling workshop

**Begin with `01_OceanBioME/00_reference_column.jl`.** Open the file in Explorer
and choose **Julia: Execute File in REPL**. Use the Julia Plot Pane history to
review figures as they appear. Reuse the same REPL for the other exercises.

Then choose one or more self-paced biological questions:

- **Light affinity:** `04_light_affinity.jl` - how does growth respond to dim light?
- **Nutrient affinity:** `05_nutrient_affinity.jl` - how does nitrate affinity affect blooms?
- **Grazing:** `01_grazing.jl` - what happens when zooplankton graze less?
- **Particle sinking:** `02_sinking.jl` - how does sinking change carbon export?
- **Remineralisation:** `03_remineralisation.jl` - how does particle recycling affect nutrients?
- **Phytoplankton mortality:** `06_phytoplankton_mortality.jl` - explore virus-like losses.

The `07_bats_nabe.jl` exercise compares idealised Atlantic station forcing
and deep carbon export on a common 1200 m grid.

Each biological comparison runs two explicit 365-day columns using OceanBioME.jl and
Oceananigans.jl. The scripts save PNG plots, JLD2 profiles and CSV summaries to
**`results/oceanbiome/`**.

See [START_HERE.md](START_HERE.md) for instructions and questions to explore.
