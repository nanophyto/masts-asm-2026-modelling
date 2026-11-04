# # Run a reference LOBSTER column
#
# We begin with one idealised ocean column. This is the reference simulation
# for the workshop: we construct a LOBSTER ecosystem, provide seasonal light
# and mixing, and examine the evolving tracer structure and particulate
# carbon export.
#
# The simulation runs a full 365-day seasonal cycle.

# ## Load OceanBioME, Oceananigans, and the workshop utilities

using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
import MASTSWorkshop
using MASTSWorkshop: results_directory, analyse_column_output, write_diagnostics, write_export_profile,
                     plot_vertical_evolution, plot_nitrogen_partition, plot_living_fraction,
                     plot_reference_export, plot_export_profile, plot_idealised_physics

# ## Define the water column
#
# The prepared BATS-like environment supplies the 500 m grid, 30-minute
# time step, initial concentrations, light and vertically implicit mixing.

grid, time_step, initial, closure, surface_PAR = MASTSWorkshop.column(:BATS)

# ## Construct the biological model
#
# `PhytoZoo` defines phytoplankton and zooplankton processes. The seven-tracer
# `LOBSTER` model then combines them with nutrients and dissolved/particulate
# organic matter. The parameters are set to the default LOBSTER values.

plankton = PhytoZoo()
biogeochemistry = LOBSTER(grid; plankton, surface_PAR)

# ## Couple biology to the water column
#
# `NonhydrostaticModel` is an Oceananigans physical oceanography constructor. The prescribed
# closure mixes the seven tracers through the water column.

model = NonhydrostaticModel(grid; closure, biogeochemistry)
set!(model; initial...)

# ## Run and save the simulation
#
# The simulation estimates the evolution of the seven tracers over 365 days. 

output_dir = results_directory("reference_column")

simulation = Simulation(model; Δt = time_step, stop_time = 365days)
filename = joinpath(output_dir, "reference_column.jld2")
simulation.output_writers[:profiles] = JLD2Writer(model, model.tracers;
                                                   filename,
                                                   schedule = TimeInterval(1day),
                                                   overwrite_files = true)
run!(simulation)

# This output is then analysed to produce a nitrogen budget, vertical tracer evolution, and cumulative
# organic-carbon export at 100 m and 300 m. Profiles are saved daily throughout the year.

reference_results = analyse_column_output(filename, model)

# And then exported:
write_diagnostics(joinpath(output_dir, "reference_diagnostics.csv"), reference_results)
write_export_profile(joinpath(output_dir, "reference_export_profile.csv"), reference_results)

# We can print some key results to the console for quick inspection:
println("Reference: final surface phytoplankton = ", last(reference_results.surface_P), " mmol N/m³")
println("Reference: cumulative export at 100 m = ", last(reference_results.export_100.cumulative_g_C), " g C/m²")
println("Reference: cumulative export at 300 m = ", last(reference_results.export_300.cumulative_g_C), " g C/m²")
println("Reference: fitted Martin b = ", reference_results.export_profile.martin_b)
println("Reference: nitrogen budget residual = ", last(reference_results.budget_residual),
        " mmol N/m² (", 100 * last(reference_results.budget_residual) / first(reference_results.nitrogen_inventory),
        "% of sampled starting inventory)")
println("Saved $filename and diagnostics CSV")

# ## Inspect the reference output
#
# The annual simulation results are summarised below.
#md # WORKSHOP_REFERENCE_OUTPUT

# ## Plot the vertical tracer evolution
#
# These depth-time sections show the major LOBSTER tracers in the annual
# reference simulation: zooplankton, phytoplankton, nitrate, small POM,
# large POM and DOM. Together they show how the initially uniform ecosystem
# responds to light, mixing and biological processes.

vertical_figure_path = joinpath(output_dir, "reference_vertical_evolution.png")
plot_vertical_evolution(reference_results, vertical_figure_path)
println("Saved $vertical_figure_path")

#md # WORKSHOP_REFERENCE_VERTICAL_FIGURE

# ## Where is the nitrogen throughout the year?
#
# Integrate all seven pools over the upper 100 m, grouping them into
# inorganic nutrients (NO₃ + NH₄), living plankton (P + Z), particulate
# detritus (sPOM + bPOM), and DOM. Both the total inventories and their
# percentage contributions are plotted. This is a simplified view of the
# seasonal nitrogen cycling discussed by
# [Fasham et al. (1990)](https://elischolar.library.yale.edu/journal_of_marine_research/1981/).

partition_figure_path = joinpath(output_dir, "reference_nitrogen_partition.png")
plot_nitrogen_partition(reference_results, partition_figure_path)
println("Saved $partition_figure_path")

#md # WORKSHOP_REFERENCE_PARTITION_FIGURE

# ## What fraction of the particulate matter is living?
#
# The ratio (P + Z) / (P + Z + sPOM + bPOM) is shown against day and depth.
# A second ratio shows the dissolved share of organic N, defined as DOM /
# (DOM + P + Z + sPOM + bPOM), while a companion panel shows the absolute
# particulate inventory. Nitrate and ammonium are inorganic and are excluded
# from this organic ratio. At Station ALOHA,
# [Karl et al. (2022)](https://doi.org/10.1016/j.pocean.2022.102803)
# studied living versus nonliving particulate carbon with ATP measurements.
# Their microbial biomass includes organisms not explicitly represented
# by LOBSTER, so our nitrogen ratio illustrates the model's compartments.

living_figure_path = joinpath(output_dir, "reference_living_fraction.png")
plot_living_fraction(reference_results, living_figure_path)
println("Saved $living_figure_path")

#md # WORKSHOP_REFERENCE_LIVING_FIGURE

# ## Examine carbon export
#
# LOBSTER's small and large particulate pools sink at different speeds. The
# fixed C:N conversion of 106:16 gives a carbon-equivalent export at 100 m
# and 300 m. These fluxes include the adjustment of initially prescribed
# particulate matter, particularly early in the simulation.

export_figure_path = joinpath(output_dir, "reference_carbon_export.png")
plot_reference_export(reference_results, export_figure_path)
println("Saved $export_figure_path")

#md # WORKSHOP_REFERENCE_EXPORT_FIGURE

# ## Compare export attenuation with the Martin curve
#
# Diagnose particle flux every 50 m down to 500 m. The first panel compares
# LOBSTER's final 90-day mean flux against the [Martin et al. (1987)](https://doi.org/10.1016/0198-0149(87)90086-0) empirical
# curve, normalized to the simulated flux at 100 m. It also fits a power-law
# exponent to the model values below 100 m. A negative b indicates that
# the flux increases with depth over the fitted range. The second panel shows export
# integrated over the full 365-day run, which includes the initial POM
# adjustment. The power-law comparison summarizes attenuation; LOBSTER's
# biological transformations and particle sinking generate the model profile.

profile_figure_path = joinpath(output_dir, "reference_martin_curve.png")
plot_export_profile(reference_results, profile_figure_path)
println("Saved $profile_figure_path")

#md # WORKSHOP_REFERENCE_MARTIN_FIGURE

# ## What to look for
#
# How do living and detrital pools change throughout the year? How does
# the inorganic nitrogen fraction compare with organic nitrogen? Why might the
# instantaneous export at 100 m differ from that at 300 m? How does
# the flux attenuation compare with the empirical Martin curve, and what
# might explain differences? What do the cumulative fluxes tell us that an
# individual day's flux cannot?
#
# The [physical-forcing appendix](physical_forcing.md) explains the light
# and mixing environment. Continue with the [grazing experiment](01_grazing.md)
# to modify one biological parameter and compare otherwise identical columns.
#md # WORKSHOP_REFERENCE_BUDGET_CHECK
