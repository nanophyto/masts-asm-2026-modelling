# Getting started with modelling

**MASTS Annual Science Meeting · 12 November 2026**

This workshop introduces two approaches to marine biogeochemistry:

- **Mechanistic models:** OceanBioME.jl and Oceananigans.jl represent
  plankton growth, grazing, nutrient uptake and particle sinking. Begin
  with a single reference column before changing biological parameters.
- **Data-driven models:** Abil.py is available for the companion Python
  exercises.

## Workshop workstation

Open the personal workstation link provided by the instructor and sign in with
your assigned `nanophyto.org` account. The editor starts inside the
participant-friendly `workshop/` folder. See [Getting started](getting_started.md)
for Julia REPL and figure-viewing instructions.

## Workshop walkthrough

Begin with the [reference LOBSTER column](generated/00_reference_column.md) and
then choose any self-paced investigation:

1. **[Light affinity](generated/04_light_affinity.md):** How does the light response affect seasonal growth?
2. **[Nutrient affinity](generated/05_nutrient_affinity.md):** When does nitrate affinity matter?
3. **[Grazing](generated/01_grazing.md):** How does grazing redistribute plankton and export?
4. **[Particle sinking](generated/02_sinking.md):** How do sinking speeds alter carbon export?
5. **[Remineralisation](generated/03_remineralisation.md):** Where is organic matter recycled?
6. **[Phytoplankton mortality](generated/06_phytoplankton_mortality.md):** What does stronger virus-like loss do to living and detrital nitrogen?

The [BATS-NABE comparison](generated/07_bats_nabe.md) introduces a deeper,
vertically stretched 1200 m column with contrasting idealised North Atlantic
light, mixing, and nitrate profiles. Both stations use the same LOBSTER biology.
The [physical-forcing appendix](generated/physical_forcing.md) explains the
assumptions and grid choices for both reference environments.
