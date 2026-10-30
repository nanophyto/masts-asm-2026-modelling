module MASTSWorkshop

include("idealised_physics.jl")
include("column_diagnostics.jl")

using .IdealisedPhysics: surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions
using .ColumnDiagnostics: face_index, downward_nitrogen_flux, cumulative_trapezoid,
                          carbon_flux_mg_per_day, carbon_export_g_per_m2,
                          diagnose_column, write_diagnostics

export surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions,
       face_index, downward_nitrogen_flux, cumulative_trapezoid,
       carbon_flux_mg_per_day, carbon_export_g_per_m2, diagnose_column, write_diagnostics,
       plot_vertical_evolution, plot_reference_export, plot_idealised_physics,
       plot_grazing_response, plot_carbon_export

# The CairoMakie extension supplies these methods when plotting is requested.
function plot_vertical_evolution end
function plot_reference_export end
function plot_idealised_physics end
function plot_grazing_response end
function plot_carbon_export end

end
