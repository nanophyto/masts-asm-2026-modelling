# # Compare idealised BATS and NABE columns
#
# BATS and NABE are contrasting North Atlantic environments. BATS represents a
# subtropical, relatively nutrient-poor seasonal ecosystem; NABE represents
# the strongly seasonal North Atlantic spring-bloom regime around 47 N, 20 W.
# Here both stations use the same 1200 m stretched grid and default LOBSTER
# biological parameters. Only light, mixing, and initial nitrate differ.
#
# These are idealised physical scenarios rather than data-assimilative station
# reconstructions. First compare their forcing; then examine the ecological
# response and how much carbon reaches 1000 m.
#
# For a quick two-day functional check in a terminal, use
# `MASTS_COMPARISON_DAYS=2`; the standard experiment runs 365 days.

# ## Load the ecosystem model and workshop functions

using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
import MASTSWorkshop
using MASTSWorkshop: analyse_column_output, results_directory,
                     write_diagnostics, write_export_profile,
                     plot_station_forcing, plot_station_diffusivity, plot_station_comparison

output_dir = results_directory("bats_nabe")

# ## Compare the prescribed physical environments
#
# Both deep columns share 60 cells: 10 m spacing from 0-300 m, 20 m from
# 300-600 m, and 40 m from 600-1200 m. They share 30-minute time steps.
# The physical figure compares annual light, mixed-layer depth, winter
# nitrate structure and spring mixing. The depth-time panels show
# diffusivity over the upper 500 m, with the mixed-layer depth overlaid.

forcing_figure = joinpath(output_dir, "station_forcing.png")
plot_station_forcing(forcing_figure)
println("Saved $forcing_figure")

#md # WORKSHOP_STATION_FORCING_FIGURE

# ## How does vertical mixing evolve with depth?
#
# Both deep columns use the same 1200 m grid. These depth-time panels zoom
# into the upper 500 m and use the same logarithmic diffusivity colour scale.
# The white dashed curve marks mixed-layer depth; the horizontal dotted line
# marks the bottom of the 300 m teaching column. Below the winter mixed layer,
# diffusivity is approximately 1e-4 m²/s at both stations.

diffusivity_figure = joinpath(output_dir, "station_diffusivity.png")
plot_station_diffusivity(diffusivity_figure)
println("Saved $diffusivity_figure")

#md # WORKSHOP_STATION_DIFFUSIVITY_FIGURE

# ## How does the prescribed mixed layer compare with observations?
#
# Blue points show NOAA GOSML monthly mean MLD only, overlaid on the
# smooth idealised seasonal curves. Depth is plotted as negative downward. Both
# curves were revised toward the observed seasonal timing and magnitude.
# Calendar-month mean forcing determines the bias and RMSE table below.
# Winter means December–March; positive bias indicates overly deep mixing.
# The observations were extracted offline by the dedicated Conda data-prep
# environment. The full docs build regenerates the figure and table from the
# committed CSV; normal participant runs use these published reference results.

#md # WORKSHOP_GOSML_COMPARISON_FIGURE

#md # WORKSHOP_GOSML_SUMMARY_TABLE

# ## Run a reference ecosystem at each station
#
# Each simulation uses the same default LOBSTER biology. The nitrate profiles
# are preliminary idealisations; the next development cycle will test them
# against observed station climatologies and assess multi-year equilibration.

simulation_days = parse(Int, get(ENV, "MASTS_COMPARISON_DAYS", "365"))
2 <= simulation_days <= 365 || error("MASTS_COMPARISON_DAYS must be between 2 and 365")

results = Dict{Symbol, Any}()
for station in (:BATS, :NABE)
    grid, time_step, initial, closure, surface_PAR = MASTSWorkshop.column(station; deep = true)
    biogeochemistry = LOBSTER(grid; surface_PAR, scale_negatives = true)
    model = NonhydrostaticModel(grid; closure, biogeochemistry)
    set!(model; initial...)

    filename = joinpath(output_dir, "$(lowercase(string(station)))_reference.jld2")
    simulation = Simulation(model; Δt = time_step, stop_time = simulation_days * days)
    simulation.output_writers[:profiles] = JLD2Writer(model, model.tracers;
        filename, schedule = TimeInterval(1day), overwrite_files = true)
    run!(simulation)

    diagnosed = analyse_column_output(filename, model)
    write_diagnostics(joinpath(output_dir, "$(lowercase(string(station)))_diagnostics.csv"), diagnosed)
    write_export_profile(joinpath(output_dir, "$(lowercase(string(station)))_export_profile.csv"), diagnosed)
    results[station] = diagnosed
    println("$station: final surface P = ", last(diagnosed.surface_P), " mmol N/m3")
    println("$station: total export at 1000 m = ", last(diagnosed.export_1000.cumulative_g_C), " g C/m2")
    println("$station: late-season Martin b = ", diagnosed.export_profile.martin_b)
end

# ## Compare the two ecosystem responses
#
# In the plots, "surface" means the top 0-10 m model cell, represented at
# its centre (z = -5 m), not an average of the upper 100 m. Concentrations
# are in mmol N/m³. The prominent NABE bloom is a provisional first-year
# result influenced by the prescribed winter mixing and initial nitrate
# profile; observed biomass and spin-up sensitivity remain to be checked.
# The upper panels show seasonal top-cell biomass and nitrate. The lower panels
# show the final-window normalised particle flux profile and cumulative export
# at 1000 m. Flux profiles include the effects of initialisation and seasonal
# adjustment; subsequent multi-year runs will distinguish persistent export
# behaviour from the first-year transient.

comparison_figure = joinpath(output_dir, "station_comparison.png")
plot_station_comparison(results[:BATS], results[:NABE], comparison_figure)
println("Saved $comparison_figure")

#md # WORKSHOP_STATION_COMPARISON_FIGURE

# ## Research questions for the next experiments
#
# 1. Which environment produces the stronger bloom and larger deep carbon flux?
# 2. Does the station with greater surface phytoplankton necessarily export
#    more POC at 1000 m?
# 3. Which aspects of the response depend on physical forcing versus the
#    biological parameter values? These controls establish the comparison
#    needed for production, particle-routing and combined interventions.
