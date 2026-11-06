module PARComparison

using Oceananigans.Units: days
using ..IdealisedPhysics: surface_PAR
using ..MLDComparison: MONTH_DAYS, MONTH_STARTS, month_coordinate

export read_power_par, compare_par_climatology, write_par_summary

const PAR_COLUMNS = ("station", "month", "latitude", "longitude", "par_w_m2")
const STATIONS = (; BATS = (31.67, -64.17), NABE = (47.0, -20.0))

function read_power_par(filename::AbstractString)
    isfile(filename) || throw(ArgumentError("Missing NASA POWER PAR observations: $filename. " *
        "Run `conda run -n masts-gosml python scripts/prepare_par_climatology.py` first."))
    lines = readlines(filename)
    isempty(lines) && throw(ArgumentError("Empty NASA POWER PAR CSV: $filename"))
    headers = strip.(split(first(lines), ','))
    length(unique(headers)) == length(headers) || throw(ArgumentError("Duplicate NASA POWER CSV headers"))
    all(name -> name in headers, PAR_COLUMNS) || throw(ArgumentError("Missing NASA POWER CSV column"))
    index = Dict(name => i for (i, name) in enumerate(headers))
    groups = Dict(:BATS => NamedTuple[], :NABE => NamedTuple[])
    for (number, line) in enumerate(lines[2:end])
        isempty(strip(line)) && continue
        cells = strip.(split(line, ','))
        length(cells) == length(headers) || throw(ArgumentError("Bad PAR row $(number + 1)"))
        station = Symbol(cells[index["station"]])
        haskey(groups, station) || throw(ArgumentError("Unknown PAR station: $station"))
        month = tryparse(Int, cells[index["month"]])
        isnothing(month) && throw(ArgumentError("Invalid PAR month on row $(number + 1)"))
        function number_value(name)
            value = tryparse(Float64, cells[index[name]])
            (isnothing(value) || !isfinite(value)) &&
                throw(ArgumentError("Invalid $name on row $(number + 1)"))
            return value
        end
        latitude = number_value("latitude")
        longitude = number_value("longitude")
        par = number_value("par_w_m2")
        lat_expected, lon_expected = getproperty(STATIONS, station)
        (abs(latitude - lat_expected) < 0.05 && abs(longitude - lon_expected) < 0.05 &&
         0 < par < 400) || throw(ArgumentError("Invalid PAR or coordinates on row $(number + 1)"))
        push!(groups[station], (; month, par))
    end
    function station_rows(station)
        rows = sort(groups[station]; by = row -> row.month)
        getproperty.(rows, :month) == collect(1:12) ||
            throw(ArgumentError("$station needs exactly one observation for each calendar month"))
        return (; months = collect(1:12), observed_mean = getproperty.(rows, :par))
    end
    return (; BATS = station_rows(:BATS), NABE = station_rows(:NABE))
end

function compare_par_climatology(filename::AbstractString)
    observations = read_power_par(filename)
    daily_days = collect(0:365)
    month_x = month_coordinate.(daily_days)
    function compare(station)
        observed = getproperty(observations, station)
        model_monthly = [sum(surface_PAR(station, (day + 0.5) * days)
                             for day in MONTH_STARTS[m]:(MONTH_STARTS[m + 1] - 1)) / MONTH_DAYS[m]
                         for m in 1:12]
        model_daily = [surface_PAR(station, day * days) for day in daily_days]
        differences = model_monthly .- observed.observed_mean
        metrics = (; observed_annual_mean = sum(MONTH_DAYS[m] * observed.observed_mean[m]
                                                 for m in 1:12) / 365,
                     model_annual_mean = sum(MONTH_DAYS[m] * model_monthly[m]
                                              for m in 1:12) / 365,
                     bias = sum(differences) / 12,
                     rmse = sqrt(sum(abs2, differences) / 12),
                     observed_winter_mean = sum(observed.observed_mean[[12, 1, 2]]) / 3,
                     model_winter_mean = sum(model_monthly[[12, 1, 2]]) / 3)
        return merge(observed, (; model_daily, model_monthly, month_x, metrics))
    end
    return (; BATS = compare(:BATS), NABE = compare(:NABE))
end

function write_par_summary(filename::AbstractString, comparison)
    mkpath(dirname(filename))
    fmt(x) = string(round(x; digits = 1))
    open(filename, "w") do io
        println(io, "| Station | Observed annual mean | Idealised annual mean | Monthly bias | Monthly RMSE | Observed winter mean | Idealised winter mean |")
        println(io, "|:--|--:|--:|--:|--:|--:|--:|")
        for station in (:BATS, :NABE)
            m = getproperty(comparison, station).metrics
            println(io, "| $station | $(fmt(m.observed_annual_mean)) | $(fmt(m.model_annual_mean)) | " *
                        "$(fmt(m.bias)) | $(fmt(m.rmse)) | $(fmt(m.observed_winter_mean)) | " *
                        "$(fmt(m.model_winter_mean)) |")
        end
        println(io, "\nAll values are in W m⁻² of daily-average surface PAR. " *
                    "Model minus observed monthly bias is positive for excess model light; " *
                    "RMSE uses 12 monthly means, annual means use calendar-day weights, " *
                    "and winter is December–February. The model samples continuous daily-average light.")
    end
    return filename
end

end
