# Run an independent, one-dimensional physical column using NumericalEarth's
# published ocean_simulation / CATKE / JRA55 setup. The only saved fields are
# tracer diffusivity at cell faces, temperature and salinity.
#
# julia --threads=1 --project=physics physics/generate_column.jl BATS 2
# julia --threads=1 --project=physics physics/generate_column.jl NABE 365

using Dates
using NumericalEarth
using Oceananigans
using Oceananigans.Units: minutes, hours, days

const STATIONS = Dict(:BATS => (-64.17, 31.67), :NABE => (-20.0, 47.0))

# Same 1,200 m faces as MASTSWorkshop.deep_grid_faces(), with no extra
# near-surface interpolation in the workshop's offline biological runs.
function column_faces()
    vcat(collect(-1200.0:40.0:-600.0),
         collect(-580.0:20.0:-300.0),
         collect(-290.0:10.0:0.0))
end

function generate(station::Symbol, run_days::Int; output_hours::Int = 3)
    haskey(STATIONS, station) || throw(ArgumentError("Station must be BATS or NABE"))
    1 <= run_days <= 365 || throw(ArgumentError("Run duration must be 1-365 days"))
    output_hours > 0 && 24 % output_hours == 0 ||
        throw(ArgumentError("Output interval must divide 24 hours"))

    longitude, latitude = STATIONS[station]
    grid = RectilinearGrid(size = 60, x = longitude, y = latitude,
                           z = column_faces(), topology = (Flat, Flat, Bounded))

    # ocean_simulation supplies its established CATKE vertically implicit
    # turbulence closure and the TEOS-10 equation of state; no local Kz
    # parameterization is introduced in this repository.
    ocean = ocean_simulation(grid; Δt = 10minutes,
                             coriolis = FPlane(latitude = latitude))

    # EN4's January 1990 hydrography is co-dated with the repeat-year JRA55
    # 1990 atmospheric cycle. This public dataset requires no Copernicus login.
    point = Column(longitude, latitude; interpolation = Nearest())
    first_day = DateTime(1990, 1, 1)
    initial_T = Metadatum(:temperature; dataset = EN4Monthly(),
                          date = first_day, region = point)
    initial_S = Metadatum(:salinity; dataset = EN4Monthly(),
                          date = first_day, region = point)
    set!(ocean.model; T = initial_T, S = initial_S)

    final_date = first_day + Day(run_days + 1)
    atmosphere = JRA55PrescribedAtmosphere(; region = point,
                      start_date = first_day, end_date = final_date,
                      time_indices_in_memory = 16)
    radiation = JRA55PrescribedRadiation(; region = point,
                      start_date = first_day, end_date = final_date,
                      time_indices_in_memory = 16)
    coupled = OceanOnlyModel(ocean; atmosphere, radiation)
    simulation = Simulation(coupled; Δt = ocean.Δt,
                            stop_time = run_days * days)

    # Kz (κc) is already located at vertical FACES in NumericalEarth's CATKE
    # implementation. Save it on its native Oceananigans grid, along with T/S
    # for stratification and mixed-layer-depth diagnostics. The biogeochemical
    # column needs only κc; its surface PAR remains the separately calibrated
    # NASA POWER forcing. u, v, w and TKE do not enter the offline file.
    T, S = ocean.model.tracers.T, ocean.model.tracers.S
    κc = ocean.model.closure_fields.κc
    root = normpath(joinpath(@__DIR__, ".."))
    directory = get(ENV, "MASTS_PHYSICS_OUTPUT_DIR", joinpath(root, "outputs", "physics"))
    mkpath(directory)
    filebase = joinpath(directory, "$(lowercase(string(station)))_catke_$(run_days)d")
    ocean.output_writers[:offline_physics] = JLD2Writer(ocean.model, (; κc, T, S);
                              filename = filebase,
                              schedule = TimeInterval(output_hours * hours),
                              overwrite_files = true)
    @info "Running 1D NumericalEarth CATKE column" station run_days output_hours filebase
    run!(simulation)
    open(filebase * ".provenance.txt", "w") do io
        println(io, "station = $station")
        println(io, "longitude = $longitude")
        println(io, "latitude = $latitude")
        println(io, "initial_conditions = EN4Monthly, 1990-01-01")
        println(io, "atmospheric_forcing = RepeatYearJRA55, 1990")
        println(io, "turbulence_closure = NumericalEarth ocean_simulation CATKE")
        println(io, "vertical_grid = 60 stretched cells; 1200 m")
        println(io, "saved_fields = κc, T, S")
        println(io, "run_days = $run_days")
        println(io, "output_hours = $output_hours")
        println(io, "julia_version = $VERSION")
        println(io, "NumericalEarth_version = $(Base.pkgversion(NumericalEarth))")
        println(io, "Oceananigans_version = $(Base.pkgversion(Oceananigans))")
    end
    println("Saved physical column: $(filebase).jld2")
    return "$(filebase).jld2"
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (1, 2) || error("Usage: generate_column.jl BATS|NABE [days=2]")
    station = Symbol(uppercase(ARGS[1]))
    run_days = length(ARGS) == 2 ? parse(Int, ARGS[2]) : 2
    generate(station, run_days)
end
