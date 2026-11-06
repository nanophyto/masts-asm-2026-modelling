# Compare the generated CATKE mixing with the previous idealised closure.
# julia --threads=1 --project=oceanbiome physics/plot_diffusivity.jl BATS outputs/physics/bats_catke_2d.jld2

using CairoMakie, MASTSWorkshop
using Oceananigans.Units: days

length(ARGS) in (2, 3) || error("Usage: plot_diffusivity.jl BATS|NABE <physics.jld2> [output.png]")
station = Symbol(uppercase(ARGS[1]))
station in (:BATS, :NABE) || error("Station must be BATS or NABE")
forcing = load_offline_physics(ARGS[2])
output = length(ARGS) == 3 ? ARGS[3] : replace(ARGS[2], r"\.jld2$" => "_diffusivity.png")

z, t = forcing.faces, forcing.seconds
source = forcing.diffusivity
idealised = [vertical_diffusivity(station, depth, time) for depth in z, time in t]
fig = Figure(size = (1350, 560), fontsize = 15)
Label(fig[0, 1:3], "$station — 1D vertical tracer diffusivity"; fontsize = 21)
for (col, title, values) in ((1, "NumericalEarth CATKE", source),
                             (2, "Previous idealised mixing", idealised))
    ax = Axis(fig[1, col]; title, xlabel = "Days", ylabel = "Depth (m)")
    map = heatmap!(ax, t ./ days, z, permutedims(log10.(max.(values, 1e-8)));
                   colormap = :viridis, colorrange = (-8, -1))
    ylims!(ax, -500, 0)
    if col == 2
        Colorbar(fig[1, 3], map; label = "log₁₀ Kz (m² s⁻¹)")
    end
end
mkpath(dirname(abspath(output)))
save(output, fig)
println("Saved 1D diffusivity comparison: $output")
