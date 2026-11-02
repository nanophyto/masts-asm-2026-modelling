module MASTSWorkshop

include("idealised_physics.jl")
include("column_diagnostics.jl")

using .IdealisedPhysics: surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions
using .ColumnDiagnostics: face_index, sinking_courant, downward_nitrogen_flux, cumulative_trapezoid,
                          carbon_flux_mg_per_day, carbon_export_g_per_m2,
                          martin_flux, fit_martin_exponent,
                          living_particulate_fraction, dissolved_organic_fraction,
                          upper_nitrogen_partition,
                          diagnose_column, write_diagnostics, write_export_profile

export surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions,
       face_index, sinking_courant, downward_nitrogen_flux, cumulative_trapezoid,
       carbon_flux_mg_per_day, carbon_export_g_per_m2,
       martin_flux, fit_martin_exponent, living_particulate_fraction, dissolved_organic_fraction,
       upper_nitrogen_partition, diagnose_column, write_diagnostics, write_export_profile,
       plot_vertical_evolution, plot_reference_export, plot_export_profile, plot_idealised_physics,
       plot_nitrogen_partition, plot_living_fraction, plot_plankton_balance,
       plot_grazing_response, plot_carbon_export

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

end
