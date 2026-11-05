module MASTSWorkshop

include("idealised_physics.jl")
include("column_diagnostics.jl")
include("mld_comparison.jl")
include("par_comparison.jl")
include("offline_physics.jl")

using .IdealisedPhysics: surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions, par_calibrated,
                         nabe_surface_PAR, nabe_mixed_layer_depth, nabe_vertical_diffusivity,
                         nabe_initial_conditions, deep_bats_initial_conditions
using .MLDComparison: read_gosml_mld, compare_mld_climatology, write_mld_summary
using .PARComparison: read_power_par, compare_par_climatology, write_par_summary
using .OfflinePhysics: OfflineColumnForcing, OfflineDiffusivity, load_offline_physics, offline_diffusivity, offline_temperature
include("column_configuration.jl")

using .ColumnDiagnostics: face_index, sinking_courant, downward_nitrogen_flux, cumulative_trapezoid,
                          carbon_flux_mg_per_day, carbon_export_g_per_m2,
                          martin_flux, fit_martin_exponent,
                          living_particulate_fraction, dissolved_organic_fraction,
                          upper_nitrogen_partition,
                          analyse_column_output, write_diagnostics, write_export_profile

export column, results_directory, deep_grid_faces,
       OfflineColumnForcing, load_offline_physics, offline_diffusivity, offline_temperature,
       surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions, par_calibrated,
       nabe_surface_PAR, nabe_mixed_layer_depth, nabe_vertical_diffusivity,
       nabe_initial_conditions, deep_bats_initial_conditions,
       face_index, sinking_courant, downward_nitrogen_flux, cumulative_trapezoid,
       carbon_flux_mg_per_day, carbon_export_g_per_m2,
       martin_flux, fit_martin_exponent, living_particulate_fraction, dissolved_organic_fraction,
       upper_nitrogen_partition, analyse_column_output, write_diagnostics, write_export_profile,
       plot_vertical_evolution, plot_reference_export, plot_export_profile, plot_idealised_physics,
       plot_nitrogen_partition, plot_living_fraction, plot_plankton_balance,
       plot_grazing_response, plot_carbon_export, plot_parameter_response, plot_parameter_export,
       plot_station_forcing, plot_station_diffusivity, plot_station_comparison,
       read_gosml_mld, compare_mld_climatology, write_mld_summary, plot_mld_comparison,
       read_power_par, compare_par_climatology, write_par_summary, plot_par_comparison

# The CairoMakie extension supplies these methods when plotting is requested.
function plot_vertical_evolution end
function plot_reference_export end
function plot_export_profile end
function plot_idealised_physics end
function plot_nitrogen_partition end
function plot_living_fraction end
function plot_plankton_balance end
function plot_grazing_response end
function plot_carbon_export end
function plot_parameter_response end
function plot_parameter_export end
function plot_station_forcing end
function plot_station_diffusivity end
function plot_station_comparison end
function plot_mld_comparison end
function plot_par_comparison end

end
