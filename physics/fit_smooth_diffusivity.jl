# Fit and plot binary two-layer Kz with a smooth annual mixing depth from CATKE.
# julia --threads=1 --project=oceanbiome physics/fit_smooth_diffusivity.jl BATS outputs/physics/bats_catke_spin365d_365d.jld2

using CairoMakie
using MASTSWorkshop: load_offline_physics, smooth_mixed_layer_depth
using Oceananigans.Units: days
using TOML

include(joinpath(@__DIR__, "smooth_diffusivity_fit.jl"))
using .SmoothDiffusivityFit: fit_smooth_diffusivity

function write_smooth_fit(path, fit, station, source)
    model = fit.model
    metadata = Dict(
        "fit_version" => 2,
        "station" => string(station),
        "source_file" => basename(source),
        "period_seconds" => model.period,
        "mld_coefficients_m" => collect(model.coefficients),
        "upper_diffusivity_m2_s" => model.upper,
        "deep_diffusivity_m2_s" => model.deep,
        "interface_type" => "binary_step",
        "excluded_interface_band_m" => fit.exclusion_band,
        "excluded_surface_depth_m" => fit.surface_exclusion_depth,
        "background_sampling_limit_m" => fit.deep_fit_limit,
        "mixing_depth_method" => "CATKE Kz-defined mixing depth: daily-median centre Kz, first downward half-log-contrast crossing (surface 0-25m versus deep >500m), two annual harmonics",
        "diffusivity_method" => "Upper: thickness/time-weighted median Kz from 20m to 15m above fitted mixing depth; deep: thickness/time-weighted median below 15m interface exclusion within top 300m; Kz is an exact two-value step",
    )
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        TOML.print(io, metadata; sorted = true)
    end
    return path
end

function plot_smooth_fit(path, forcing, fit, station)
    model = fit.model
    t = forcing.seconds ./ days
    z = forcing.faces
    catke = log10.(max.(forcing.diffusivity, 1e-8))
    smooth = [log10(max(model(depth, time), 1e-8))
              for depth in z, time in forcing.seconds]
    change = smooth .- catke
    h = [smooth_mixed_layer_depth(model, time) for time in forcing.seconds]

    figure = Figure(size = (1500, 920), fontsize = 15)
    Label(figure[0, 1:3], "$station — CATKE and binary two-layer mixing", fontsize = 22)

    sharedmap = nothing
    for (position, name, values) in ((figure[1, 1], "NumericalEarth CATKE", catke),
                                     (figure[1, 2], "Binary two-layer fit", smooth))
        ax = Axis(position; title = name, xlabel = "Day of year", ylabel = "Depth (m)")
        hm = heatmap!(ax, t, z, permutedims(values); colormap = :viridis,
                      colorrange = (-8, 1))
        sharedmap = hm
        lines!(ax, t, -h; color = :white, linewidth = 2.2)
        lines!(ax, t, -h; color = :black, linestyle = :dash, linewidth = 1.0)
        ylims!(ax, -500, 0)
    end
    Colorbar(figure[1, 3], sharedmap; label = "log₁₀ Kz (m² s⁻¹)")

    difference_axis = Axis(figure[2, 1]; title = "Smooth − CATKE", xlabel = "Day of year",
                           ylabel = "Depth (m)")
    difference = heatmap!(difference_axis, t, z, permutedims(change);
                          colormap = :balance, colorrange = (-3, 3))
    lines!(difference_axis, t, -h; color = :white, linewidth = 2.2)
    lines!(difference_axis, t, -h; color = :black, linestyle = :dash, linewidth = 1.0)
    ylims!(difference_axis, -500, 0)
    Colorbar(figure[2, 3], difference; label = "Δ log₁₀ Kz")

    mld_axis = Axis(figure[2, 2]; title = "Diagnosed mixing depth",
                    xlabel = "Day of year", ylabel = "Depth (m, positive down)", yreversed = true)
    lines!(mld_axis, t, fit.raw_temperature_mld; color = (:gray35, 0.45), linewidth = 1,
           label = "Temperature-based MLD")
    scatter!(mld_axis, fit.daily_times ./ days, fit.daily_depths;
             color = (:teal, 0.45), markersize = 3, label = "Daily Kz mixing depth")
    lines!(mld_axis, t, h; color = :royalblue, linewidth = 3,
           label = "Smooth Kz mixing depth")
    axislegend(mld_axis; position = :rt)

    Label(figure[3, 1:3],
          "K upper (median, below 20 m) = $(round(model.upper, sigdigits = 3)) m²/s   |   " *
          "K deep (median, upper 300 m) = $(round(model.deep, sigdigits = 3)) m²/s   |   " *
          "binary interface", fontsize = 15)
    mkpath(dirname(abspath(path)))
    save(path, figure)
    return path
end

function main(station, input)
    station in (:BATS, :NABE) || error("Station must be BATS or NABE")
    forcing = load_offline_physics(input)
    fit = fit_smooth_diffusivity(forcing, station)
    prefix = replace(input, r"\.jld2$" => "_smooth")
    params = write_smooth_fit(prefix * ".toml", fit, station, input)
    plot = plot_smooth_fit(prefix * "_comparison.png", forcing, fit, station)
    println("Saved fitted 1D physics: $params")
    println("Saved comparison figure: $plot")
    println("K upper (median) = $(fit.model.upper) m²/s; K deep (median) = $(fit.model.deep) m²/s")
    return params, plot
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: fit_smooth_diffusivity.jl BATS|NABE <annual_catke.jld2>")
    main(Symbol(uppercase(ARGS[1])), ARGS[2])
end
