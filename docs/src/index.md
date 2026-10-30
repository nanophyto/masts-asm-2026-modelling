# Getting started with modelling

**MASTS Annual Science Meeting · 12 November 2026**

This workshop introduces two approaches to marine biogeochemistry:

- **Mechanistic models:** OceanBioME.jl and Oceananigans.jl represent
  plankton growth, grazing, nutrient uptake and particle sinking. Begin
  with a single reference column before changing biological parameters.
- **Data-driven models:** Abil.py is available for the companion Python
  exercises.

## Workshop walkthrough

1. **[Run a reference column](generated/00_reference_column.md):** Build a
   LOBSTER water column using the real OceanBioME/Oceananigans constructors,
   run the simulation and inspect its plots of vertical ecology and carbon export.
2. **[Change the grazing rate](generated/01_grazing.md):** Compare control
   and reduced-grazing experiments and interpret the effect on plankton and
   export at 100 m and 300 m.
3. **[Running the examples on your own system](running_locally.md):** Set up
   Julia and Python on a laptop and reproduce the exercises after the workshop.

The [physical-forcing appendix](generated/physical_forcing.md) explains the
prescribed light and vertical mixing in the reference column and will
compare the BATS, HOT, NABE and DYFAMED station forcings as they are added.
