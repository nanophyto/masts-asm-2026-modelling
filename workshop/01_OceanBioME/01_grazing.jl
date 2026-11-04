# # Experiment: change the grazing rate
#
# Start with the [reference column](00_reference_column.md). Now change
# one biological parameter: zooplankton grazing. We run two otherwise
# identical columns and compare phytoplankton, nitrate and carbon export.
#
# From the repository root:
#
# ```bash
# julia --project=oceanbiome workshop/01_OceanBioME/01_grazing.jl
# ```
#
# Both experiments run for 365 days and save comparison figures.

# ## Load the packages and prepared physical forcing

using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
import MASTSWorkshop
using MASTSWorkshop: results_directory, analyse_column_output, write_diagnostics, write_export_profile,
                     plot_grazing_response, plot_plankton_balance, plot_carbon_export

# ## Configure the water column
#
# The physical environment is an idealised BATS-like seasonal cycle.
# Both grazing treatments use the same 500 m column, 50 cells (10 m spacing),
# 30-minute step, physical forcing and initial concentrations.
grid, time_step, initial, closure, surface_PAR = MASTSWorkshop.column(:BATS)
output_dir = results_directory("grazing")

# ## Control experiment: standard grazing
#
# Start with the reference grazing rate of 0.8/day.

control_plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                             maximum_grazing_rate = 0.8 / day)
control_biogeochemistry = LOBSTER(grid; plankton = control_plankton,
                                  surface_PAR, scale_negatives = true)
control_model = NonhydrostaticModel(grid; closure, biogeochemistry = control_biogeochemistry)
set!(control_model; initial...)

control_simulation = Simulation(control_model; Δt = time_step, stop_time = 365days)
control_file = joinpath(output_dir, "control.jld2")
control_simulation.output_writers[:profiles] = JLD2Writer(control_model, control_model.tracers;
                                                            filename = control_file,
                                                            schedule = TimeInterval(1day),
                                                            overwrite_files = true)
run!(control_simulation)

control_results = analyse_column_output(control_file, control_model)
write_diagnostics(joinpath(output_dir, "control_diagnostics.csv"), control_results)
write_export_profile(joinpath(output_dir, "control_export_profile.csv"), control_results)

println("control: final surface phytoplankton = ", last(control_results.surface_P), " mmol N/m³")
println("control: cumulative export at 100 m = ", last(control_results.export_100.cumulative_g_C), " g C/m²")
println("control: cumulative export at 300 m = ", last(control_results.export_300.cumulative_g_C), " g C/m²")
println("control: nitrogen budget residual = ", last(control_results.budget_residual),
        " mmol N/m² (", 100 * last(control_results.budget_residual) / first(control_results.nitrogen_inventory),
        "% of sampled starting inventory)")
println("Saved $control_file and diagnostics CSV")

# ## Reduced-grazing experiment
#
# Repeat the same column with the grazing rate reduced to 0.4/day.
# All other parameters and initial conditions are identical.

reduced_plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                             maximum_grazing_rate = 0.4 / day)
reduced_biogeochemistry = LOBSTER(grid; plankton = reduced_plankton,
                                  surface_PAR, scale_negatives = true)
reduced_model = NonhydrostaticModel(grid; closure, biogeochemistry = reduced_biogeochemistry)
set!(reduced_model; initial...)

reduced_simulation = Simulation(reduced_model; Δt = time_step, stop_time = 365days)
reduced_file = joinpath(output_dir, "reduced_grazing.jld2")
reduced_simulation.output_writers[:profiles] = JLD2Writer(reduced_model, reduced_model.tracers;
                                                            filename = reduced_file,
                                                            schedule = TimeInterval(1day),
                                                            overwrite_files = true)
run!(reduced_simulation)

reduced_results = analyse_column_output(reduced_file, reduced_model)
write_diagnostics(joinpath(output_dir, "reduced_grazing_diagnostics.csv"), reduced_results)
write_export_profile(joinpath(output_dir, "reduced_grazing_export_profile.csv"), reduced_results)

println("reduced_grazing: final surface phytoplankton = ", last(reduced_results.surface_P), " mmol N/m³")
println("reduced_grazing: cumulative export at 100 m = ", last(reduced_results.export_100.cumulative_g_C), " g C/m²")
println("reduced_grazing: cumulative export at 300 m = ", last(reduced_results.export_300.cumulative_g_C), " g C/m²")
println("reduced_grazing: nitrogen budget residual = ", last(reduced_results.budget_residual),
        " mmol N/m² (", 100 * last(reduced_results.budget_residual) / first(reduced_results.nitrogen_inventory),
        "% of sampled starting inventory)")
println("Saved $reduced_file and diagnostics CSV")

# ## Inspect the simulation output
#
# Compare the annual results of the two grazing configurations.
#md # WORKSHOP_RUN_OUTPUT

# ## Compare the grazing response
#
# A difference panel complements each comparison. It reveals the change due
# to reduced grazing even when the two trajectories nearly overlap.

filename = joinpath(output_dir, "grazing_response.png")
plot_grazing_response(control_results, reduced_results, filename)
println("Saved $filename")

#md # WORKSHOP_GRAZING_FIGURE

# ## Compare phytoplankton and zooplankton
#
# The upper-100 m phytoplankton and zooplankton nitrogen inventories show
# how changing grazing redistributes living biomass. The zooplankton share,
# Z / (P + Z), is a bounded alternative to a potentially very large Z:P ratio.
# Compare both experiments and their differences through the annual cycle.

filename = joinpath(output_dir, "grazing_plankton_balance.png")
plot_plankton_balance(control_results, reduced_results, filename)
println("Saved $filename")

#md # WORKSHOP_PLANKTON_BALANCE_FIGURE

# ## Plot particulate carbon export
#
# Instantaneous and cumulative fluxes are shown at 100 m and 300 m, with
# separate difference panels. Both depths can initially reflect the sinking
# particulate matter prescribed in the initial conditions; interpret later
# changes alongside the developing phytoplankton and nutrient distributions.

filename = joinpath(output_dir, "carbon_export.png")
plot_carbon_export(control_results, reduced_results, filename)
println("Saved $filename")

#md # WORKSHOP_EXPORT_FIGURE

# ## Interpret the results
#
# Compare the phytoplankton and zooplankton inventories and their ratio.
# Does reduced grazing change the share of zooplankton in living biomass?
# Compare the phytoplankton response with export at each depth. Does a change
# in surface biomass produce a proportional change in carbon export? How does
# the cumulative flux differ from the instantaneous flux?
#
# The particle fluxes use a fixed molar C:N ratio of 106:16. Each day's
# export is calculated from the two sinking particulate pools; the nitrogen
# budget includes all seven LOBSTER tracers. The budget closes against
# sinking loss through the open bottom boundary.
#md # WORKSHOP_BUDGET_CHECK
