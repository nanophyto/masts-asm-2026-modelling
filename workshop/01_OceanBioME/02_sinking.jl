# # Experiment: How does particle sinking affect carbon export?
#
# Small and large particulate detritus sink at different speeds. Compare
# the reference speeds (3 and 200 m/day) with slower large-particle sinking.
# Only the large-particle sinking speed changes.
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
# The prepared BATS-like environment supplies a 500 m column with 50 cells,
# a 30-minute time step, initial tracer concentrations, seasonal light,
# and vertically implicit mixing. Both experiments use the same physics.

grid, time_step, initial, closure, surface_PAR = MASTSWorkshop.column(:BATS)
output_dir = results_directory("sinking")

# ## Choose the biological experiment
#
# `DissolvedParticulate` is the detritus component inside LOBSTER.
# The default speeds are (3, 200) m/day for small and large particles.
# In the second run, large particles sink at 100 m/day; small particles
# retain their reference speed. The default particulate decay rates remain.
#
# ## Control experiment: reference biology

# `PhytoZoo` sets phytoplankton and zooplankton processes. `LOBSTER`
# combines these with nutrients and dissolved/particulate organic matter.
# `NonhydrostaticModel` couples all seven tracers to the physical column,
# where the prescribed closure mixes them vertically.

control_plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                          maximum_grazing_rate = 0.8 / day)
control_biogeochemistry = LOBSTER(grid; plankton = control_plankton,
                                  surface_PAR, scale_negatives = true)
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
println("control: export at 100 m = ", last(control_results.export_100.cumulative_g_C), " g C/m²")
println("control: export at 300 m = ", last(control_results.export_300.cumulative_g_C), " g C/m²")
println("control: nitrogen budget residual = ", last(control_results.budget_residual), " mmol N/m²")
println("Saved $(control_file) and CSV summaries")

# ## Modified experiment: slower sinking

slow_detritus = DissolvedParticulate(grid; sinking_speeds = (3/day, 100/day))
modified_plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                          maximum_grazing_rate = 0.8 / day)
modified_biogeochemistry = LOBSTER(grid; plankton = modified_plankton,
                                  detritus = slow_detritus, surface_PAR, scale_negatives = true)
modified_model = NonhydrostaticModel(grid; closure, biogeochemistry = modified_biogeochemistry)
set!(modified_model; initial...)

# ## Run and save the modified simulation
#
# We repeat the 365-day seasonal cycle, retaining the same daily output schedule.

modified_simulation = Simulation(modified_model; Δt = time_step, stop_time = 365days)
modified_file = joinpath(output_dir, "slow_sinking.jld2")
modified_simulation.output_writers[:profiles] = JLD2Writer(modified_model, modified_model.tracers;
    filename = modified_file, schedule = TimeInterval(1day), overwrite_files = true)
run!(modified_simulation)

# Analyse the second run in the same way so the two results are comparable.

modified_results = analyse_column_output(modified_file, modified_model)

# Export the corresponding diagnostic summary and carbon fluxes:
write_diagnostics(joinpath(output_dir, "slow_sinking_diagnostics.csv"), modified_results)
write_export_profile(joinpath(output_dir, "slow_sinking_export_profile.csv"), modified_results)

# Print the modified-run results for comparison:
println("slow_sinking: export at 100 m = ", last(modified_results.export_100.cumulative_g_C), " g C/m²")
println("slow_sinking: export at 300 m = ", last(modified_results.export_300.cumulative_g_C), " g C/m²")
println("slow_sinking: nitrogen budget residual = ", last(modified_results.budget_residual), " mmol N/m²")
println("Saved $(modified_file) and CSV summaries")

# ## Inspect the two simulation outputs
#
# The left panels compare the two columns and the right panels show the
# change relative to the control. The curves use matching daily outputs.
#md # WORKSHOP_PARAMETER_OUTPUT

response_figure_path = joinpath(output_dir, "sinking_response.png")
plot_parameter_response(control_results, modified_results, response_figure_path;
                        label = "Slower sinking")
println("Saved $response_figure_path")

#md # WORKSHOP_PARAMETER_RESPONSE_FIGURE

# ## Compare daily and cumulative organic-carbon export
#
# Fluxes are diagnosed from small and large particulate pools at 100 and
# 300 m. Cumulative export integrates each day's rate over the simulation.
# The first few days include adjustment of initially prescribed particles.

export_figure_path = joinpath(output_dir, "sinking_export.png")
plot_parameter_export(control_results, modified_results, export_figure_path;
                      label = "Slower sinking")
println("Saved $export_figure_path")

#md # WORKSHOP_PARAMETER_EXPORT_FIGURE

# ## What to look for
#
# Which depth shows the clearest change in cumulative export? Is export
# necessarily larger when large particles sink faster? Compare the daily
# and cumulative fluxes, and the upper-100 m detrital inventory. How might
# sinking and remineralisation interact below the surface?
#
# The seven-tracer nitrogen budget should close against sinking loss
# through the open bottom boundary (up to numerical/sampling error).
#md # WORKSHOP_PARAMETER_BUDGET_CHECK
