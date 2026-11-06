# Generate 1D CATKE physical forcing for the separate OceanBioME column.
#
# Smoke test (no spin-up):
#   julia --threads=1 --project=physics physics/generate_column.jl BATS 2
# Annual reference (365-day spin-up, then a saved 365-day cycle):
#   julia --threads=1 --project=physics physics/generate_column.jl BATS 365 365
#
# CLI arguments: STATION [output_days=2] [spinup_days=0] [output_hours=3]

using Dates
using NumericalEarth
using Oceananigans
using Oceananigans.Units: minutes, hours, days
using Oceananigans.OutputReaders: Cyclical

const STATIONS = Dict(:BATS => (-64.17, 31.67), :NABE => (-20.0, 47.0))

# Same 1,200 m faces as MASTSWorkshop.deep_grid_faces().
function column_faces()
    vcat(collect(-1200.0:40.0:-600.0),
         collect(-580.0:20.0:-300.0),
         collect(-290.0:10.0:0.0))
end

# Explicit times guarantee a complete post-spin-up output window, including
# both endpoints. The physical model and its clock remain continuous across
# the spin-up and output phases.
function output_times(spinup_days::Int, output_days::Int, output_hours::Int)
    spinup_days >= 0 || throw(ArgumentError("spinup_days must be nonnegative"))
    1 <= output_days <= 365 || throw(ArgumentError("output_days must be 1-365"))
    output_hours > 0 && 24 % output_hours == 0 ||
        throw(ArgumentError("output_hours must divide 24"))
    start = spinup_days * days
    stop = (spinup_days + output_days) * days
    return collect(start:(output_hours * hours):stop)
end

function generate(station::Symbol, output_days::Int;
                  spinup_days::Int = 0, output_hours::Int = 3)
    haskey(STATIONS, station) || throw(ArgumentError("Station must be BATS or NABE"))
    save_at = output_times(spinup_days, output_days, output_hours)
    longitude, latitude = STATIONS[station]
    grid = RectilinearGrid(size = 60, x = longitude, y = latitude,
                           z = column_faces(), topology = (Flat, Flat, Bounded))

    # NumericalEarth supplies CATKE, a vertically implicit physical turbulence
    # closure, and the equation of state. We only prescribe atmosphere and
    # initial hydrography, not Kz or any water velocity.
    ocean = ocean_simulation(grid; Δt = 10minutes,
                             coriolis = FPlane(latitude = latitude))
    point = Column(longitude, latitude; interpolation = Nearest())
    first_day = DateTime(1990, 1, 1)
    initial_T = Metadatum(:temperature; dataset = EN4Monthly(),
                          date = first_day, region = point)
    initial_S = Metadatum(:salinity; dataset = EN4Monthly(),
                          date = first_day, region = point)
    set!(ocean.model; T = initial_T, S = initial_S)

    # IMPORTANT: RepeatYearJRA55 has native samples covering 1990, not an
    # arbitrary short period. Request the full annual record even for 2-day
    # smoke tests. Its default Cyclical indexing repeats this actual 365-day
    # cycle during a multi-year physical integration. For window-mean fluxes,
    # NumericalEarth may report a generic +/-1.5 h edge warning; the full-year
    # wrap is intentional and consistent with the annual climatology.
    final_date = DateTime(1990, 12, 31, 21)
    # Specify the annual period explicitly. An instantaneous JRA55 series
    # ends at 21:00 on 31 December; inferring a period from its first and
    # last samples would otherwise produce 364 days + 21 hours.
    annual_indexing = Cyclical(365days)
    atmosphere = JRA55PrescribedAtmosphere(; region = point,
                      start_date = first_day, end_date = final_date,
                      time_indexing = annual_indexing,
                      time_indices_in_memory = 16)
    radiation = JRA55PrescribedRadiation(; region = point,
                      start_date = first_day, end_date = final_date,
                      time_indexing = annual_indexing,
                      time_indices_in_memory = 16)
    length(atmosphere.times) >= 365 * 8 ||
        error("RepeatYearJRA55 is missing the complete 1990 cycle; check downloaded data")
    coupled = OceanOnlyModel(ocean; atmosphere, radiation)
    simulation = Simulation(coupled; Δt = ocean.Δt,
                            stop_time = (spinup_days + output_days) * days)

    T, S = ocean.model.tracers.T, ocean.model.tracers.S
    u, v = ocean.model.velocities.u, ocean.model.velocities.v
    κc = ocean.model.closure_fields.κc  # tracer Kz at vertical cell faces
    root = normpath(joinpath(@__DIR__, ".."))
    directory = get(ENV, "MASTS_PHYSICS_OUTPUT_DIR", joinpath(root, "outputs", "physics"))
    mkpath(directory)
    tag = spinup_days == 0 ? "$(output_days)d" : "spin$(spinup_days)d_$(output_days)d"
    filebase = joinpath(directory, "$(lowercase(string(station)))_catke_$tag")

    # The post-spin-up writer is registered after the spin-up has finished.
    # Oceananigans 0.113.6 writes an initial snapshot at iteration zero even
    # if SpecifiedTimes begins later, so attaching it earlier would include an
    # unwanted unspun-up snapshot. For no-spin-up smoke tests, register now.
    function attach_primary_writer!()
        writer = JLD2Writer(ocean.model, (; κc, T, S, u, v);
                             filename = filebase,
                             schedule = SpecifiedTimes(save_at),
                             overwrite_files = true)
        ocean.output_writers[:offline_physics] = writer
        if spinup_days > 0
            # At this point the model clock is exactly at the spin-up boundary.
            # Save the first post-spin-up record and consume its schedule time.
            writer.schedule(ocean.model) || error("Spin-up ended off the output boundary")
            Oceananigans.write_output!(writer, ocean.model)
        end
        return nothing
    end

    spinup_days == 0 && attach_primary_writer!()

    # One daily file for the last spin-up year makes comparison with the
    # following year possible without storing full subdaily spin-up history.
    if spinup_days >= 365
        spinup_daily = collect(((spinup_days - 365) * days):days:(spinup_days * days))
        ocean.output_writers[:spinup_diagnostics] = JLD2Writer(ocean.model, (; κc, T, S, u, v);
                                   filename = filebase * "_spinup_daily",
                                   schedule = SpecifiedTimes(spinup_daily),
                                   overwrite_files = true)
    end

    @info "Running 1D NumericalEarth CATKE column" station spinup_days output_days output_hours filebase
    if spinup_days > 0
        # Run the same coupled model through spin-up, retaining its prognostic
        # temperature, salinity, velocities, turbulence and model clock.
        simulation.stop_time = spinup_days * days
        @info "Physical spin-up" station days=spinup_days
        run!(simulation)
        isapprox(ocean.model.clock.time, spinup_days * days; atol = 1e-6) ||
            error("Physical spin-up did not finish at the intended time")
        attach_primary_writer!()
        simulation.stop_time = (spinup_days + output_days) * days
        @info "Saving post-spin-up physical year" station days=output_days
    end
    run!(simulation)

    open(filebase * ".provenance.txt", "w") do io
        println(io, "station = $station")
        println(io, "longitude = $longitude")
        println(io, "latitude = $latitude")
        println(io, "initial_conditions = EN4Monthly, 1990-01-01")
        println(io, "atmospheric_forcing = RepeatYearJRA55, complete 1990 cycle")
        println(io, "repetition_period_days = 365")
        println(io, "turbulence_closure = NumericalEarth ocean_simulation CATKE")
        println(io, "vertical_grid = 60 stretched cells; 1200 m")
        println(io, "saved_fields = κc, T, S, u, v")
        println(io, "spinup_days = $spinup_days")
        println(io, "output_days = $output_days")
        println(io, "output_hours = $output_hours")
        println(io, "file_times = continuous model clock; reader subtracts first output time")
        println(io, "julia_version = $VERSION")
        println(io, "NumericalEarth_version = $(Base.pkgversion(NumericalEarth))")
        println(io, "Oceananigans_version = $(Base.pkgversion(Oceananigans))")
    end
    println("Saved physical column: $(filebase).jld2")
    spinup_days >= 365 && println("Saved previous-year diagnostic: $(filebase)_spinup_daily.jld2")
    return "$(filebase).jld2"
end

# Keyword form is convenient from a Julia session or an agent script.
generate(station::Symbol; spinup_days::Int = 365, output_days::Int = 365,
         output_hours::Int = 3) =
    generate(station, output_days; spinup_days, output_hours)

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in 1:4 || error("Usage: generate_column.jl BATS|NABE [output_days=2] [spinup_days=0] [output_hours=3]")
    station = Symbol(uppercase(ARGS[1]))
    output_days = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 2
    spinup_days = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 0
    output_hours = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 3
    generate(station, output_days; spinup_days, output_hours)
end
