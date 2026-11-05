module MLDComparison

using Oceananigans.Units: days
using ..IdealisedPhysics: mixed_layer_depth

export read_gosml_mld, compare_mld_climatology, write_mld_summary

# One non-leap climatological year; the idealised forcing starts on 1 January
# (t = 0, midwinter). Observational values describe whole calendar months.
const MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
const MONTH_STARTS = cumsum([0; collect(MONTH_DAYS)])
const REQUIRED_COLUMNS = ("station", "month", "mld_mean_m", "mld_p05_m",
                          "mld_p50_m", "mld_p95_m", "lat_selected",
                          "lon_selected", "distance_km", "n_profiles",
                          "sum_mapping_weights")

function read_gosml_mld(filename::AbstractString)
    isfile(filename) || throw(ArgumentError(
        "GOSML CSV not found: $filename. Run `conda run -n masts-gosml python scripts/prepare_mld_climatology.py` first."))
    lines = readlines(filename)
    isempty(lines) && throw(ArgumentError("Empty GOSML CSV: $filename"))
    headers = strip.(split(first(lines), ','))
    length(unique(headers)) == length(headers) ||
        throw(ArgumentError("Duplicate GOSML CSV column headers"))
    index = Dict(name => i for (i, name) in enumerate(headers))
    for name in REQUIRED_COLUMNS
        haskey(index, name) || throw(ArgumentError("Missing GOSML column: $name"))
    end

    groups = Dict(:BATS => NamedTuple[], :NABE => NamedTuple[])
    for (offset, line) in enumerate(lines[2:end])
        line_number = offset + 1
        isempty(strip(line)) && continue
        cells = strip.(split(line, ','))
        length(cells) == length(headers) ||
            throw(ArgumentError("Invalid number of CSV columns on line $line_number"))
        station = Symbol(cells[index["station"]])
        haskey(groups, station) ||
            throw(ArgumentError("Unexpected station $station on line $line_number"))
        month = tryparse(Int, cells[index["month"]])
        isnothing(month) && throw(ArgumentError("Invalid month on line $line_number"))

        function numeric(name)
            value = tryparse(Float64, cells[index[name]])
            (isnothing(value) || !isfinite(value)) &&
                throw(ArgumentError("Invalid $name on line $line_number"))
            return value
        end
        observed = (; month,
                    mean = numeric("mld_mean_m"),
                    p05 = numeric("mld_p05_m"),
                    p50 = numeric("mld_p50_m"),
                    p95 = numeric("mld_p95_m"),
                    lat = numeric("lat_selected"),
                    lon = numeric("lon_selected"),
                    distance_km = numeric("distance_km"),
                    n_profiles = numeric("n_profiles"),
                    mapping_weights = numeric("sum_mapping_weights"))
        (observed.mean > 0 && 0 < observed.p05 <= observed.p50 <= observed.p95 &&
         observed.n_profiles > 0 && observed.mapping_weights > 0 &&
         observed.distance_km >= 0 && -90 <= observed.lat <= 90 &&
         -180 <= observed.lon <= 180) ||
            throw(ArgumentError("Invalid MLD, percentile ordering, or station metadata on line $line_number"))
        push!(groups[station], observed)
    end

    function station_data(station)
        rows = sort(groups[station]; by = row -> row.month)
        getproperty.(rows, :month) == collect(1:12) ||
            throw(ArgumentError("$station needs exactly one observation for each month (Jan-Dec)"))
        all(row -> row.lat == first(rows).lat && row.lon == first(rows).lon, rows) ||
            throw(ArgumentError("$station has inconsistent selected coordinates"))
        return (; months = collect(1:12), observed_mean = getproperty.(rows, :mean),
                observed_p05 = getproperty.(rows, :p05),
                observed_p50 = getproperty.(rows, :p50),
                observed_p95 = getproperty.(rows, :p95),
                n_profiles = getproperty.(rows, :n_profiles),
                lat_selected = first(rows).lat, lon_selected = first(rows).lon,
                distance_km = first(rows).distance_km)
    end
    return (; BATS = station_data(:BATS), NABE = station_data(:NABE))
end

# Plot daily forcing against observations at calendar-month midpoints. Each
# month occupies a unit-width interval centred on its calendar month number.
function month_coordinate(day)
    day == 365 && return 12.5
    month = searchsortedlast(MONTH_STARTS, day)
    return month - 0.5 + (day - MONTH_STARTS[month]) / MONTH_DAYS[month]
end

function compare_mld_climatology(filename::AbstractString)
    observed = read_gosml_mld(filename)
    daily_days = collect(0:365)
    month_x = month_coordinate.(daily_days)
    function compare(station)
        data = getproperty(observed, station)
        model_monthly = [sum(-mixed_layer_depth(station, (day + 0.5) * days)
                             for day in MONTH_STARTS[m]:(MONTH_STARTS[m + 1] - 1)) / MONTH_DAYS[m]
                         for m in 1:12]
        model_daily = [-mixed_layer_depth(station, day * days) for day in daily_days]
        differences = model_monthly .- data.observed_mean
        metrics = (; observed_annual_mean_m = sum(MONTH_DAYS[m] * data.observed_mean[m]
                                                   for m in 1:12) / 365,
                     model_annual_mean_m = sum(MONTH_DAYS[m] * model_monthly[m]
                                                for m in 1:12) / 365,
                     bias_m = sum(differences) / 12,
                     rmse_m = sqrt(sum(abs2, differences) / 12),
                     observed_winter_max_m = maximum(data.observed_mean[[12, 1, 2, 3]]),
                     model_winter_max_m = maximum(model_monthly[[12, 1, 2, 3]]),
                     observed_summer_min_m = minimum(data.observed_mean[6:8]),
                     model_summer_min_m = minimum(model_monthly[6:8]))
        return merge(data, (; model_monthly, model_daily, month_x, metrics))
    end
    return (; BATS = compare(:BATS), NABE = compare(:NABE))
end

function write_mld_summary(filename::AbstractString, comparison)
    mkpath(dirname(filename))
    fmt(x) = string(round(x; digits = 1))
    open(filename, "w") do io
        println(io, "| Station | Observed annual mean (m) | Model annual mean (m) | Bias (m) | RMSE (m) |")
        println(io, "|:--|--:|--:|--:|--:|")
        for station in (:BATS, :NABE)
            m = getproperty(comparison, station).metrics
            println(io, "| $station | $(fmt(m.observed_annual_mean_m)) | $(fmt(m.model_annual_mean_m)) | " *
                        "$(fmt(m.bias_m)) | $(fmt(m.rmse_m)) |")
        end
        println(io, "\n| Station | Observed winter max (m) | Model winter max (m) | Observed summer min (m) | Model summer min (m) |")
        println(io, "|:--|--:|--:|--:|--:|")
        for station in (:BATS, :NABE)
            m = getproperty(comparison, station).metrics
            println(io, "| $station | $(fmt(m.observed_winter_max_m)) | $(fmt(m.model_winter_max_m)) | " *
                        "$(fmt(m.observed_summer_min_m)) | $(fmt(m.model_summer_min_m)) |")
        end
        println(io, "\nModel minus observed bias: positive values mean the idealised mixed layer is deeper. " *
                    "Annual means are weighted by calendar-month length; RMSE and bias use the 12 monthly means. " *
                    "Winter maximum uses December–March; summer minimum uses June–August. " *
                    "The figure uses only the observed monthly means; the CSV retains variability statistics.")
    end
    return filename
end

end
