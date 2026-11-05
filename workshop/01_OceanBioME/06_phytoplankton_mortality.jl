# # Experiment: What happens when phytoplankton mortality increases?
#
# Phytoplankton cells are removed by grazing mortality, and sinking.
# Mortality includes unresolved grazing, and sensensence but primarily represents viral lysis. 
# Here, we explore the impact of increasing phytoplankton mortality on stock and particulate carbon export.
#
# Both simulations run a full 365-day seasonal cycle.

# ## Load OceanBioME, Oceananigans, and the workshop utilities

using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
import MASTSWorkshop
using MASTSWorkshop: results_directory, analyse_column_output, write_diagnostics, write_export_profile,
                     plot_parameter_response, plot_parameter_export

# ## Define the water column
#
# The prepared BATS-like environment supplies a 300 m column with 30 cells,
# a 30-minute time step, initial tracer concentrations, seasonal light,
# and vertically implicit mixing. Both experiments use the same physics.

grid, time_step, initial, closure, surface_PAR = MASTSWorkshop.column(:BATS)
output_dir = results_directory("phytoplankton_mortality")

# ## Choose the biological experiment
#
# LOBSTER uses a density-dependent phytoplankton loss term m * P^2. We change the
# coefficient m; the model routes this lost biomass through the configured waste
# pathways. 

# ## Control experiment: reference biology
#
# The default density-dependent mortality coefficient is 5.8e-7
# (m³/mmol N)/s ([LOBSTER defaults](https://oceanbiome.github.io/OceanBioME.jl/stable/generated/LOBSTER_parameters/)).

# `LOBSTER` constructs the default `PhytoZoo` plankton, nutrient and detritus
# components; [LOBSTER's parameters](https://oceanbiome.github.io/OceanBioME.jl/stable/generated/LOBSTER_parameters/)
# provide the reference values. `NonhydrostaticModel` couples all seven
# tracers to the physical column, where the closure mixes them vertically.

control_biogeochemistry = LOBSTER(grid; surface_PAR, scale_negatives = true)
control_model = NonhydrostaticModel(grid; closure, biogeochemistry = control_biogeochemistry)
set!(control_model; initial...)

# ## Run and save the control simulation
#
# We evolve the seven tracers for 365 days and save daily JLD2 profiles.

control_simulation = Simulation(control_model; Δt = time_step, stop_time = 365days)
control_file = joinpath(output_dir, "control.jld2")
control_simulation.output_writers[:profiles] = JLD2Writer(control_model, control_model.tracers;
    filename = control_file, schedule = TimeInterval(1day), overwrite_files = true)
run!(control_simulation)

# The saved profiles are analysed to calculate the nitrogen budget, tracer
# evolution, and cumulative organic-carbon export at 100 m and 300 m.

control_results = analyse_column_output(control_file, control_model)

# Export the diagnostic summary and depth-dependent carbon fluxes:
write_diagnostics(joinpath(output_dir, "control_diagnostics.csv"), control_results)
write_export_profile(joinpath(output_dir, "control_export_profile.csv"), control_results)

# Print a few key results to the Julia REPL:
println("Control: final surface phytoplankton = ", last(control_results.surface_P), " mmol N/m³")
println("Control: cumulative export at 100 m = ", last(control_results.export_100.cumulative_g_C), " g C/m²")
println("Control: cumulative export at 300 m = ", last(control_results.export_300.cumulative_g_C), " g C/m²")
println("Control: nitrogen budget residual = ", last(control_results.budget_residual), " mmol N/m²")

# ## Modified biology: higher phytoplankton mortality
#
# Double the phytoplankton mortality coefficient to 1.16e-6 (m3/mmol N)/s; keep
# zooplankton grazing unchanged.

modified_plankton = PhytoZoo(; phytoplankton_mortality_rate = 1.16e-6)
modified_biogeochemistry = LOBSTER(grid; plankton = modified_plankton,
                                   surface_PAR, scale_negatives = true)
modified_model = NonhydrostaticModel(grid; closure, biogeochemistry = modified_biogeochemistry)
set!(modified_model; initial...)

# ## Run and save the modified simulation
#
# We repeat the 365-day seasonal cycle, retaining the same daily output schedule.

modified_simulation = Simulation(modified_model; Δt = time_step, stop_time = 365days)
modified_file = joinpath(output_dir, "higher_mortality.jld2")
modified_simulation.output_writers[:profiles] = JLD2Writer(modified_model, modified_model.tracers;
    filename = modified_file, schedule = TimeInterval(1day), overwrite_files = true)
run!(modified_simulation)

# Analyse the second run in the same way so the two results are comparable.

modified_results = analyse_column_output(modified_file, modified_model)

# Export the corresponding diagnostic summary and carbon fluxes:
write_diagnostics(joinpath(output_dir, "higher_mortality_diagnostics.csv"), modified_results)
write_export_profile(joinpath(output_dir, "higher_mortality_export_profile.csv"), modified_results)

# Print the modified-run results for comparison:
println("Modified: final surface phytoplankton = ", last(modified_results.surface_P), " mmol N/m³")
println("Modified: cumulative export at 100 m = ", last(modified_results.export_100.cumulative_g_C), " g C/m²")
println("Modified: cumulative export at 300 m = ", last(modified_results.export_300.cumulative_g_C), " g C/m²")
println("Modified: nitrogen budget residual = ", last(modified_results.budget_residual), " mmol N/m²")

# ## Inspect the two simulation outputs
#
# The left panels show both treatments, and the right panels show
# modified minus control. All curves use the same daily output times.
#md # WORKSHOP_PARAMETER_OUTPUT

response_figure_path = joinpath(output_dir, "phytoplankton_mortality_response.png")
plot_parameter_response(control_results, modified_results, response_figure_path;
                        label = "Higher phytoplankton mortality",
                        figure_title = "Phytoplankton mortality — surface response and detritus")
println("Saved $response_figure_path")

#md # WORKSHOP_PARAMETER_RESPONSE_FIGURE

# ## Compare particulate carbon export
#
# Compare daily and cumulative export at both 100 m and 300 m. The
# first days also reflect adjustment of initially prescribed particles.

export_figure_path = joinpath(output_dir, "phytoplankton_mortality_export.png")
plot_parameter_export(control_results, modified_results, export_figure_path;
                      label = "Higher phytoplankton mortality",
                      figure_title = "Phytoplankton mortality — carbon export")
println("Saved $export_figure_path")

#md # WORKSHOP_PARAMETER_EXPORT_FIGURE

# ## What to look for
#
# Does increased phytoplankton mortality reduce living biomass and increase particulate
# detritus? Compare phytoplankton, nutrients and carbon export. Can a stronger loss
# process increase detrital export even when the living biomass decreases?
#
