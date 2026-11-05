using Oceananigans: RectilinearGrid, Flat, Bounded
using Oceananigans.Units: meters, minutes
using Oceananigans.TurbulenceClosures: ScalarDiffusivity, VerticallyImplicitTimeDiscretization

"""
    deep_grid_faces()

The shared BATS/NABE research grid extends to 1200 m. It has 10 m cells in
0-300 m, 20 m cells in 300-600 m, and 40 m cells in 600-1200 m (60 cells).
Its faces include 100, 300, and 1000 m for carbon export diagnostics.
"""
function deep_grid_faces()
    return vcat(collect(-1200.0:40.0:-600.0),
                collect(-580.0:20.0:-300.0),
                collect(-290.0:10.0:0.0))
end

"""
    column(:BATS; deep=false)
    column(:NABE; deep=false)

Return `(grid, time_step, initial, closure, surface_PAR)` for the native
OceanBioME `LOBSTER` and Oceananigans `NonhydrostaticModel` constructors.
Both stations use a 300 m / 30-cell teaching column by default, or the same
1200 m / 60-cell stretched grid when `deep=true`. Their biological parameters
are shared; idealised seasonal light, mixing, and nitrate differ by station.
The annual cycle starts at midwinter (`t = 0`).
"""
function column(station::Symbol; deep::Bool = false)
    station in (:BATS, :NABE) ||
        throw(ArgumentError("No prepared column for $station (available: :BATS, :NABE)"))

    grid = if deep
        faces = deep_grid_faces()
        RectilinearGrid(size = length(faces) - 1, z = faces,
                        topology = (Flat, Flat, Bounded))
    else
        RectilinearGrid(size = 30, extent = 300meters,
                        topology = (Flat, Flat, Bounded))
    end

    light = station === :BATS ? surface_PAR : nabe_surface_PAR
    mixing = station === :BATS ? vertical_diffusivity : nabe_vertical_diffusivity
    initial = station === :NABE ? nabe_initial_conditions() : deep_bats_initial_conditions()
    time_step = 30minutes
    closure = ScalarDiffusivity(VerticallyImplicitTimeDiscretization();
                                ν = mixing, κ = mixing)
    return (; grid, time_step, initial, closure, surface_PAR = light)
end

"""Return the folder for an experiment's saved results, creating it if needed."""
function results_directory(experiment::AbstractString)
    project_root = dirname(dirname(Base.active_project()))
    path = get(ENV, "MASTS_OUTPUT_DIR",
               joinpath(project_root, "workshop", "results", "oceanbiome", experiment))
    mkpath(path)
    return path
end
