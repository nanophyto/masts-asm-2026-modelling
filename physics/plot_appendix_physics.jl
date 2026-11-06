# Render the two NumericalEarth appendix figures from existing annual CATKE files.
# Usage: julia --threads=1 --project=oceanbiome physics/plot_appendix_physics.jl \
#   outputs/physics/bats_catke_spin365d_365d.jld2 \
#   outputs/physics/nabe_catke_spin365d_365d.jld2 \
#   docs/src/assets/numericalearth_inputs.png \
#   docs/src/assets/numericalearth_diffusivity.png

using CairoMakie, MASTSWorkshop
using Oceananigans: FieldTimeSeries
using Oceananigans.Fields: interior
using Oceananigans.Units: days

length(ARGS) == 4 || error("Usage: plot_appendix_physics.jl BATS.jld2 NABE.jld2 inputs.png diffusivity.png")

function profiles(path, name)
    series = FieldTimeSeries(path, name)
    return hcat((collect(interior(series[i], 1, 1, :)) for i in eachindex(series.times))...)
end

stations = (:BATS, :NABE)
files = ARGS[1:2]
forcings = load_offline_physics.(files)

# Figure 1: actual column response to surface forcing, with evolving T and S.
# Wind input is prescribed by JRA55; the horizontal current speed plotted here
# is the wind-driven response, not an observed or prescribed wind speed.
fig = Figure(size = (1740, 900), fontsize = 15)
Label(fig[0, 1:5], "NumericalEarth: wind-driven current response and hydrography", fontsize = 23)
for (r, station) in enumerate(stations)
    path = files[r]
    f = forcings[r]
    t = f.seconds ./ days
    every_day = 1:8:length(t)  # annual files save at three-hour intervals
    u = profiles(path, "u")
    v = profiles(path, "v")
    speed = hypot.(u[end, :], v[end, :])

    ax0 = Axis(fig[r, 1]; title = "$station — near-surface wind current speed",
               xlabel = "Day", ylabel = "|u,v| (m s⁻¹)")
    lines!(ax0, t, speed; linewidth = 1.7, color = :steelblue)
    xlims!(ax0, 0, 365)

    axT = Axis(fig[r, 2]; title = "Temperature", xlabel = "Day", ylabel = "Depth (m)")
    hmT = heatmap!(axT, t[every_day], f.centres,
                   permutedims(f.temperature[:, every_day]);
                   colormap = :plasma, colorrange = (10, 30))
    ylims!(axT, -300, 0)
    Colorbar(fig[r, 3], hmT; label = "°C")

    S = profiles(path, "S")
    axS = Axis(fig[r, 4]; title = "Salinity", xlabel = "Day", ylabel = "Depth (m)")
    hmS = heatmap!(axS, t[every_day], f.centres,
                   permutedims(S[:, every_day]); colormap = :viridis,
                   colorrange = (35, 37))
    ylims!(axS, -300, 0)
    Colorbar(fig[r, 5], hmS; label = "g kg⁻¹")
end
Label(fig[3, 1:5], "Generated using NumericalEarth.jl with CATKE, JRA55 atmospheric forcing, and EN4 initial temperature and salinity.", fontsize = 13)
mkpath(dirname(abspath(ARGS[3])))
save(ARGS[3], fig)
println("Saved NumericalEarth input/response figure: $(ARGS[3])")

# Figure 2: native face diffusivity, with identical scale at the two stations.
fig = Figure(size = (1390, 610), fontsize = 15)
for (col, station) in enumerate(stations)
    f = forcings[col]
    ax = Axis(fig[1, col]; title = string(station), xlabel = "Day", ylabel = "Depth (m)")
    hm = heatmap!(ax, f.seconds ./ days, f.faces,
                  permutedims(log10.(max.(f.diffusivity, 1e-8)));
                  colormap = :viridis, colorrange = (-8, 1))
    ylims!(ax, -300, 0)
    if col == 2
        Colorbar(fig[1, 3], hm; label = "log₁₀ Kz (m² s⁻¹)")
    end
end
mkpath(dirname(abspath(ARGS[4])))
save(ARGS[4], fig)
println("Saved CATKE diffusivity figure: $(ARGS[4])")
