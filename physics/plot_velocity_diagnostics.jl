# Plot depth-time horizontal velocity diagnostics from the NumericalEarth 1D column.
# julia --threads=1 --project=oceanbiome physics/plot_velocity_diagnostics.jl BATS outputs/physics/bats_catke_spin365d_365d.jld2

using CairoMakie
using MASTSWorkshop
using Oceananigans: FieldTimeSeries
using Oceananigans.Fields: interior
using Oceananigans.Units: days

include(joinpath(@__DIR__, "mld_temperature_diagnostic.jl"))
using .TemperatureMLD: temperature_mld

function load_series(path, field_name)
    try
        return FieldTimeSeries(path, field_name)
    catch error
        message = "Could not read field '$field_name' from $path. Regenerate the physical file with the updated physics/generate_column.jl that saves u and v."
        throw(ArgumentError(message))
    end
end

function collect_profiles(series)
    return hcat((collect(interior(series[i], 1, 1, :)) for i in eachindex(series.times))...)
end

function vertical_shear_magnitude(centres, u, v)
    nz, nt = size(u)
    shear = similar(u, Float64)
    for j in 1:nt
        shear[1, j] = hypot((u[2, j] - u[1, j]) / (centres[2] - centres[1]),
                            (v[2, j] - v[1, j]) / (centres[2] - centres[1]))
        for k in 2:(nz - 1)
            Δz = centres[k + 1] - centres[k - 1]
            shear[k, j] = hypot((u[k + 1, j] - u[k - 1, j]) / Δz,
                                (v[k + 1, j] - v[k - 1, j]) / Δz)
        end
        shear[nz, j] = hypot((u[nz, j] - u[nz - 1, j]) / (centres[nz] - centres[nz - 1]),
                             (v[nz, j] - v[nz - 1, j]) / (centres[nz] - centres[nz - 1]))
    end
    return shear
end

function plot_velocity_diagnostics(station, filepath; output = replace(filepath, r"\.jld2$" => "_velocity_diagnostics.png"))
    station in (:BATS, :NABE) || error("Station must be BATS or NABE")
    forcing = load_offline_physics(filepath)
    U = load_series(filepath, "u")
    V = load_series(filepath, "v")
    u = collect_profiles(U)
    v = collect_profiles(V)
    length(U.times) == length(forcing.seconds) || error("u times do not match κc/T times in $filepath")
    length(V.times) == length(forcing.seconds) || error("v times do not match κc/T times in $filepath")

    centres = forcing.centres
    faces = forcing.faces
    time_days = forcing.seconds ./ days
    shear = vertical_shear_magnitude(centres, u, v)
    mld = [temperature_mld(centres, view(forcing.temperature, :, i)) for i in eachindex(forcing.seconds)]

    maxabs = maximum(abs, vcat(u[:], v[:]))
    vel_limit = max(maxabs, 1e-3)
    shear_log = log10.(max.(shear, 1e-8))
    kz_log = log10.(max.(forcing.diffusivity, 1e-8))

    fig = Figure(size = (1450, 1050), fontsize = 15)
    Label(fig[0, 1:4], "$station — seasonal 1D CATKE velocity diagnostics", fontsize = 22)

    axes = (
        (Axis(fig[1, 1]; title = "Zonal velocity u", xlabel = "Days", ylabel = "Depth (m)"),
         time_days, centres, u, :balance, (-vel_limit, vel_limit), "u (m s⁻¹)", fig[1, 2]),
        (Axis(fig[1, 3]; title = "Meridional velocity v", xlabel = "Days", ylabel = "Depth (m)"),
         time_days, centres, v, :balance, (-vel_limit, vel_limit), "v (m s⁻¹)", fig[1, 4]),
        (Axis(fig[2, 1]; title = "Vertical shear magnitude", xlabel = "Days", ylabel = "Depth (m)"),
         time_days, centres, shear_log, :viridis, (-5, -1), "log₁₀ |∂U/∂z| (s⁻¹)", fig[2, 2]),
        (Axis(fig[2, 3]; title = "Tracer diffusivity κc", xlabel = "Days", ylabel = "Depth (m)"),
         time_days, faces, kz_log, :viridis, (-8, -1), "log₁₀ Kz (m² s⁻¹)", fig[2, 4]),
    )

    for (ax, x, depth, values, cmap, range, cbar_label, cslot) in axes
        hm = heatmap!(ax, x, depth, permutedims(values); colormap = cmap, colorrange = range)
        lines!(ax, time_days, -mld; color = :white, linewidth = 2.5)
        lines!(ax, time_days, -mld; color = :black, linewidth = 1.0, linestyle = :dash)
        ylims!(ax, -300, 0)
        Colorbar(cslot, hm; label = cbar_label)
    end
    Label(fig[3, 1:4], "Mixed-layer depth is overlaid (white/black dashed). Vertical velocity w is not plotted because the 1D offline column uses w = 0 by construction.", fontsize = 13)
    mkpath(dirname(abspath(output)))
    save(output, fig)
    println("Saved velocity diagnostics: $output")
    return output
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (2, 3) || error("Usage: plot_velocity_diagnostics.jl BATS|NABE <physics.jld2> [output.png]")
    station = Symbol(uppercase(ARGS[1]))
    filepath = ARGS[2]
    output = length(ARGS) == 3 ? ARGS[3] : replace(filepath, r"\.jld2$" => "_velocity_diagnostics.png")
    plot_velocity_diagnostics(station, filepath; output)
end
