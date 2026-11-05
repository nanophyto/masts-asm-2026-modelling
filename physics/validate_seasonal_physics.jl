# Compare spin-up year and following physical year, including NOAA GOSML MLD.
# julia --threads=1 --project=oceanbiome physics/validate_seasonal_physics.jl BATS outputs/physics/bats_catke_spin365d_365d.jld2

using Dates
using CairoMakie
using MASTSWorkshop
using Oceananigans: FieldTimeSeries
using Oceananigans.Fields: interior
using Oceananigans.Units: days

include(joinpath(@__DIR__, "mld_temperature_diagnostic.jl"))
using .TemperatureMLD: temperature_mld

const MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
const MONTH_STARTS = cumsum([0; collect(MONTH_DAYS)])
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function load_validation(path)
    forcing = load_offline_physics(path)
    S = FieldTimeSeries(path, "S")
    length(S.times) == length(forcing.seconds) || error("T/S sample counts differ in $path")
    salinity = hcat((collect(interior(S[i], 1, 1, :)) for i in eachindex(S.times))...)
    mld = [temperature_mld(forcing.centres, view(forcing.temperature, :, i))
           for i in eachindex(forcing.seconds)]
    return (; forcing, salinity, mld)
end

function at_depth(centres, matrix, index, depth)
    z = -Float64(depth)
    k = clamp(searchsortedlast(centres, z), 1, length(centres) - 1)
    fraction = clamp((z - centres[k]) / (centres[k + 1] - centres[k]), 0, 1)
    return (1 - fraction) * matrix[k, index] + fraction * matrix[k + 1, index]
end

function monthly_means(seconds, values)
    sums, counts = zeros(12), zeros(Int, 12)
    for (t, value) in zip(seconds, values)
        0 <= t < 365days || continue # drop next January's endpoint
        day = floor(Int, t / days)
        month = searchsortedlast(MONTH_STARTS, day)
        sums[month] += value
        counts[month] += 1
    end
    all(>(0), counts) || error("An annual physical series needs data in every month")
    return sums ./ counts
end

function surface_monthly(data, name, depth)
    field = name == :T ? data.forcing.temperature : data.salinity
    values = [at_depth(data.forcing.centres, field, i, depth)
              for i in eachindex(data.forcing.seconds)]
    return monthly_means(data.forcing.seconds, values)
end

function validate(station, filepath)
    station in (:BATS, :NABE) || error("Station must be BATS or NABE")
    output = load_validation(filepath)
    last(output.forcing.seconds) >= 365days - 1 ||
        error("Need a full 365-day output year for seasonal validation")
    output_mld = monthly_means(output.forcing.seconds, output.mld)
    previous_file = replace(filepath, r"\.jld2$" => "_spinup_daily.jld2")
    previous = isfile(previous_file) ? load_validation(previous_file) : nothing
    previous_mld = isnothing(previous) ? nothing : monthly_means(previous.forcing.seconds, previous.mld)

    root = normpath(joinpath(@__DIR__, ".."))
    gosml_file = joinpath(root, "data", "observations", "gosml_mld_bats_nabe.csv")
    observed = isfile(gosml_file) ? getproperty(read_gosml_mld(gosml_file), station).observed_mean : nothing
    isnothing(observed) && @warn "GOSML climatology not found; run conda prepare_mld_climatology.py for observational comparison" gosml_file

    figure = Figure(size = (1300, 1220), fontsize = 15)
    Label(figure[0, 1:2], "$station — seasonal 1D CATKE physics validation", fontsize = 22)
    mld_ax = Axis(figure[1, 1:2], title = "Mixed-layer depth (0.2 °C from 10 m)",
                  xlabel = "Month", ylabel = "MLD (m, positive down)",
                  xticks = (1:12, MONTH_NAMES), yreversed = true)
    lines!(mld_ax, 1:12, output_mld; color = :royalblue, linewidth = 3, label = "After spin-up")
    if !isnothing(previous_mld)
        lines!(mld_ax, 1:12, previous_mld; color = :darkorange, linewidth = 2.5,
               linestyle = :dash, label = "Last spin-up year")
    end
    if !isnothing(observed)
        scatter!(mld_ax, 1:12, observed; color = :black, markersize = 12, label = "GOSML monthly mean")
    end
    axislegend(mld_ax; position = :rt)

    for (col, name, ylabel) in ((1, :T, "10 m temperature (°C)"),
                                (2, :S, "10 m salinity (g kg⁻¹)"))
        axis = Axis(figure[2, col], title = "Near-surface $name", xlabel = "Month",
                    ylabel, xticks = (1:12, MONTH_NAMES))
        lines!(axis, 1:12, surface_monthly(output, name, 10);
               color = :royalblue, linewidth = 3)
        if !isnothing(previous)
            lines!(axis, 1:12, surface_monthly(previous, name, 10);
                   color = :darkorange, linewidth = 2.5, linestyle = :dash)
        end
    end

    # Inspect the actual T/S stratification, not just an MLD estimate.
    # The first profile of a 365-day spin-up originates from EN4; the
    # subsequent profiles show the corresponding January adjustment.
    for (col, name, xlabel) in ((1, :T, "Temperature (°C)"),
                                (2, :S, "Salinity (g kg⁻¹)"))
        ax = Axis(figure[3, col]; title = "January column hydrography",
                  xlabel, ylabel = "Depth (m)")
        field = name == :T ? output.forcing.temperature : output.salinity
        lines!(ax, field[:, 1], output.forcing.centres; color = :royalblue,
               linewidth = 3, label = "After spin-up")
        lines!(ax, field[:, end], output.forcing.centres; color = :midnightblue,
               linewidth = 2, linestyle = :dot, label = "Following January")
        if !isnothing(previous)
            prior = name == :T ? previous.forcing.temperature : previous.salinity
            lines!(ax, prior[:, 1], previous.forcing.centres;
                   color = :darkorange, linestyle = :dash,
                   linewidth = 2.5, label = "Previous January")
        end
        ylims!(ax, -300, 0)
        axislegend(ax; position = :rb, framevisible = false)
    end

    output_png = replace(filepath, r"\.jld2$" => "_seasonal_validation.png")
    output_md = replace(filepath, r"\.jld2$" => "_seasonal_validation.md")
    save(output_png, figure)
    open(output_md, "w") do io
        println(io, "# $station: 1D CATKE physical validation")
        println(io, "\nMLD: temperature threshold |ΔT| = 0.2 °C relative to 10 m " *
                    "(de Boyer Montégut et al., 2004). Positive depths are metres below the surface.")
        println(io, "\n| Metric | Value |\n|:--|--:|")
        fmt(x) = string(round(x; digits = 2))
        println(io, "| After-spin-up mean MLD (m) | $(fmt(sum(output_mld) / 12)) |")
        if !isnothing(observed)
            println(io, "| MLD RMSE vs GOSML (m; 12 monthly means) | $(fmt(sqrt(sum(abs2, output_mld .- observed) / 12))) |")
            println(io, "| MLD bias vs GOSML (m) | $(fmt(sum(output_mld .- observed) / 12)) |")
        end
        if !isnothing(previous)
            println(io, "| Interannual MLD RMSE (m) | $(fmt(sqrt(sum(abs2, output_mld .- previous_mld) / 12))) |")
            for (name, label) in ((:T, "Temperature"), (:S, "Salinity"))
                for depth in (10, 100)
                    current = surface_monthly(output, name, depth)
                    earlier = surface_monthly(previous, name, depth)
                    println(io, "| Interannual $label RMS difference at $depth m | $(fmt(sqrt(sum(abs2, current .- earlier) / 12))) |")
                end
            end
        end
        println(io, "\nThe initial temperature and salinity profiles came from EN4 January 1990. " *
                    "A change between the two physical years indicates drift or continuing adjustment, " *
                    "not necessarily improved realism. Compare the observed GOSML seasonal range " *
                    "before adopting the forcing for workshop biology.")
    end
    println("Saved seasonal validation: $output_png")
    println("Saved seasonal summary: $output_md")
    return output_png
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: validate_seasonal_physics.jl BATS|NABE <annual_physics.jld2>")
    validate(Symbol(uppercase(ARGS[1])), ARGS[2])
end
