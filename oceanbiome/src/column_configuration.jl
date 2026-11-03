using Oceananigans: RectilinearGrid, Flat, Bounded
using Oceananigans.Units: meters, minutes
using Oceananigans.TurbulenceClosures: ScalarDiffusivity, VerticallyImplicitTimeDiscretization

"""
    column(:BATS)

Prepare the physical and numerical environment for an OceanBioME column.
Returns `(grid, time_step, initial, closure, surface_PAR)` for use with the
native `LOBSTER` and `NonhydrostaticModel` constructors.

`:BATS` currently uses the tested **idealised BATS-like** annual cycle; observed
station forcings will be added after validation.
"""
function column(station::Symbol)
    station === :BATS || throw(ArgumentError("No prepared column for $station (available: :BATS)"))

    grid = RectilinearGrid(size = 50, extent = 500meters,
                           topology = (Flat, Flat, Bounded))
    time_step = 30minutes
    initial = initial_conditions()
    closure = ScalarDiffusivity(VerticallyImplicitTimeDiscretization();
                                ν = vertical_diffusivity, κ = vertical_diffusivity)
    return (; grid, time_step, initial, closure, surface_PAR)
end

"""Return the folder for an experiment's saved results, creating it if needed."""
function results_directory(experiment::AbstractString)
    project_root = dirname(dirname(Base.active_project()))
    path = get(ENV, "MASTS_OUTPUT_DIR",
               joinpath(project_root, "workshop", "results", "oceanbiome", experiment))
    mkpath(path)
    return path
end
