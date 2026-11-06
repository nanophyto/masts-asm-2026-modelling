module MASTSWorkshopMakieExt

using MASTSWorkshop
using CairoMakie
using Oceananigans.Units: days
using Oceananigans: Center
using Oceananigans.Grids: znodes

const blue = :steelblue
const orange = :darkorange

function matching_times(control, reduced)
    control.day == reduced.day || throw(ArgumentError("The two simulations must have matching output times"))
end

function compare_lines!(axis, control, reduced, metric; label = "Reduced grazing")
    lines!(axis, control.day, metric(control); color = blue, linewidth = 2.5, label = "Control")
    lines!(axis, reduced.day, metric(reduced); color = orange, linestyle = :dash,
           linewidth = 2.5, label)
    return axis
end

# Show the evolving vertical structure of the main LOBSTER tracers.
function MASTSWorkshop.plot_vertical_evolution(control, filename::AbstractString; preview::Bool = isinteractive())
    figure = Figure(size = (1650, 900), fontsize = 15)
    tracer_panels = (
        (1, 1, "Zooplankton", control.vertical_Z),
        (1, 3, "Phytoplankton", control.vertical_P),
        (1, 5, "Nitrate", control.vertical_NO₃),
        (2, 1, "Small POM", control.vertical_sPOM),
        (2, 3, "Large POM", control.vertical_bPOM),
        (2, 5, "DOM", control.vertical_DOM),
    )

    for (row, column, title, values) in tracer_panels
        axis = Axis(figure[row, column]; title, xlabel = "Day", ylabel = "Depth (m)")
        map = heatmap!(axis, control.day, control.z, permutedims(values))
        Colorbar(figure[row, column + 1], map; label = "mmol N m⁻³")
    end

    save(filename, figure)
    preview && display(figure)
    return filename
end

# The seven tracers form four complementary nitrogen categories in the upper 100 m.
function MASTSWorkshop.plot_nitrogen_partition(d, filename::AbstractString; preview::Bool = isinteractive())
    nitrogen = d.upper_100m
    categories = (("Inorganic (NO₃ + NH₄)", nitrogen.inorganic, :steelblue),
                  ("Living (P + Z)", nitrogen.living, :seagreen),
                  ("Detrital (sPOM + bPOM)", nitrogen.detrital, :darkorange),
                  ("Dissolved organic (DOM)", nitrogen.dissolved_organic, :mediumpurple))

    figure = Figure(size = (1450, 530), fontsize = 15)
    inventory = Axis(figure[1, 1]; title = "Upper 100 m nitrogen inventory",
                     xlabel = "Day", ylabel = "mmol N m⁻²")
    fractions = Axis(figure[1, 2]; title = "Upper 100 m nitrogen partition",
                     xlabel = "Day", ylabel = "Share of total N (%)")

    lower_inventory = zeros(length(d.day))
    lower_fraction = zeros(length(d.day))
    for (label, values, color) in categories
        top_inventory = lower_inventory .+ values
        band!(inventory, d.day, lower_inventory, top_inventory; color, label)
        lower_inventory = top_inventory

        fraction = 100 .* values ./ nitrogen.total
        top_fraction = lower_fraction .+ fraction
        band!(fractions, d.day, lower_fraction, top_fraction; color)
        lower_fraction = top_fraction
    end
    ylims!(fractions, 0, 100)
    axislegend(inventory; position = :rt, framevisible = false)
    save(filename, figure)
    preview && display(figure)
    return filename
end

# Compare living and dissolved-organic shares with particulate abundance.
function MASTSWorkshop.plot_living_fraction(d, filename::AbstractString; preview::Bool = isinteractive())
    particulate = d.vertical_P .+ d.vertical_Z .+ d.vertical_sPOM .+ d.vertical_bPOM
    figure = Figure(size = (1650, 530), fontsize = 15)

    living_axis = Axis(figure[1, 1]; title = "Living fraction of particulate N",
                       xlabel = "Day", ylabel = "Depth (m)")
    living_map = heatmap!(living_axis, d.day, d.z, permutedims(100 .* d.living_fraction);
                          colormap = :viridis, colorrange = (0, 100))
    Colorbar(figure[1, 2], living_map; label = "Living (%)")

    dissolved_axis = Axis(figure[1, 3]; title = "Dissolved fraction of organic N",
                          xlabel = "Day", ylabel = "Depth (m)")
    dissolved_map = heatmap!(dissolved_axis, d.day, d.z,
                             permutedims(100 .* d.dissolved_fraction);
                             colormap = :viridis, colorrange = (0, 100))
    Colorbar(figure[1, 4], dissolved_map; label = "DOM (%)")

    amount_axis = Axis(figure[1, 5]; title = "Total particulate N",
                       xlabel = "Day", ylabel = "Depth (m)")
    amount_map = heatmap!(amount_axis, d.day, d.z, permutedims(particulate))
    Colorbar(figure[1, 6], amount_map; label = "mmol N m⁻³")

    save(filename, figure)
    preview && display(figure)
    return filename
end

# Examine the response of upper-ocean phytoplankton and zooplankton biomass.
function MASTSWorkshop.plot_plankton_balance(control, reduced, filename::AbstractString;
                                          figure_title::AbstractString = "Grazing experiment — upper-100 m plankton inventories",
                                          preview::Bool = isinteractive())
    matching_times(control, reduced)
    metrics = (("Phytoplankton", "mmol N m⁻²", d -> d.upper_100m.phytoplankton),
               ("Zooplankton", "mmol N m⁻²", d -> d.upper_100m.zooplankton),
               ("Zooplankton share", "% of P + Z", d -> 100 .* d.upper_100m.zoo_fraction))
    figure = Figure(size = (1320, 1050), fontsize = 15)
    Label(figure[0, :], figure_title; fontsize = 22, font = :bold)
    for (row, (title, unit, metric)) in enumerate(metrics)
        axis = Axis(figure[row, 1]; title, xlabel = "Day", ylabel = unit)
        compare_lines!(axis, control, reduced, metric)
        axislegend(axis; position = :rt, framevisible = false)

        difference_axis = Axis(figure[row, 2]; title = "Change in $title",
                               xlabel = "Day", ylabel = "Reduced − control ($unit)")
        lines!(difference_axis, control.day, metric(reduced) .- metric(control);
               color = orange, linewidth = 2.5)
        hlines!(difference_axis, [0.0]; color = :gray, linestyle = :dot)
    end
    save(filename, figure)
    preview && display(figure)
    return filename
end

# Plot the two sinking-flux horizons for a single reference simulation.
function MASTSWorkshop.plot_reference_export(reference, filename::AbstractString; preview::Bool = isinteractive())
    figure = Figure(size = (1100, 700), fontsize = 15)
    for (row, depth, particle_export) in ((1, 100, reference.export_100),
                                          (2, 300, reference.export_300))
        daily = Axis(figure[row, 1]; title = "Daily export at $depth m",
                     xlabel = "Day", ylabel = "mg C m⁻² day⁻¹")
        lines!(daily, reference.day, particle_export.daily_mg_C; color = blue, linewidth = 2.5)

        cumulative = Axis(figure[row, 2]; title = "Cumulative export at $depth m",
                          xlabel = "Day", ylabel = "g C m⁻²")
        lines!(cumulative, reference.day, particle_export.cumulative_g_C;
               color = blue, linewidth = 2.5)
    end
    save(filename, figure)
    preview && display(figure)
    return filename
end

# Compare the modelled depth-dependent sinking flux with a Martin-curve benchmark.
function MASTSWorkshop.plot_export_profile(reference, filename::AbstractString; preview::Bool = isinteractive())
    profile = reference.export_profile
    depths = profile.depths
    flux = profile.mean_daily_mg_C
    reference_index = findfirst(==(100), depths)
    reference_flux = flux[reference_index]
    martin_depths = range(100, last(depths); length = 150)

    figure = Figure(size = (1100, 680), fontsize = 15)
    daily = Axis(figure[1, 1]; title = "Flux profile: final $(round(profile.window_days; digits = 1)) days",
                 xlabel = "mg C m⁻² day⁻¹", ylabel = "Depth (m)")
    scatterlines!(daily, flux, .-depths; color = blue, markersize = 9,
                  linewidth = 2.5, label = "LOBSTER")

    if reference_flux > 0
        # Classical Martin attenuation is a comparison, normalized to model F(100).
        classical = MASTSWorkshop.martin_flux.(martin_depths, reference_flux, 0.858)
        lines!(daily, classical, .-martin_depths; color = :gray, linestyle = :dash,
               linewidth = 2.5, label = "Martin b = 0.858")
        if !isnothing(profile.martin_b)
            fitted = MASTSWorkshop.martin_flux.(martin_depths, reference_flux, profile.martin_b)
            lines!(daily, fitted, .-martin_depths; color = orange, linestyle = :dot,
                   linewidth = 2.5, label = "Model fit b = $(round(profile.martin_b; digits = 2))")
        end
    end
    axislegend(daily; position = :rb, framevisible = false)

    integrated = Axis(figure[1, 2]; title = "Total export over the simulated period",
                      xlabel = "g C m⁻²", ylabel = "Depth (m)")
    scatterlines!(integrated, profile.integrated_g_C, .-depths;
                  color = blue, markersize = 9, linewidth = 2.5)
    save(filename, figure)
    preview && display(figure)
    return filename
end

# Describe the physical environment actually used by the idealised column.
function MASTSWorkshop.plot_idealised_physics(filename::AbstractString; preview::Bool = isinteractive())
    day_samples = collect(0:5:365)
    times = day_samples .* days
    depths = collect(range(-MASTSWorkshop.column(:BATS).grid.Lz, 0.0; length = 101))
    mixing = [MASTSWorkshop.vertical_diffusivity(z, t) for t in times, z in depths]

    figure = Figure(size = (1100, 760), fontsize = 15)
    par = Axis(figure[1, 1]; title = "Surface PAR", xlabel = "Day",
               ylabel = "W m⁻²")
    lines!(par, day_samples, MASTSWorkshop.surface_PAR.(times);
           color = blue, linewidth = 2.5)

    mld = Axis(figure[1, 2]; title = "Mixed-layer depth", xlabel = "Day",
               ylabel = "Depth (m)")
    lines!(mld, day_samples, MASTSWorkshop.mixed_layer_depth.(times);
           color = orange, linewidth = 2.5)

    diffusivity = Axis(figure[2, 1:2]; title = "Prescribed vertical diffusivity",
                       xlabel = "Day", ylabel = "Depth (m)")
    colors = heatmap!(diffusivity, day_samples, depths, mixing)
    lines!(diffusivity, day_samples, MASTSWorkshop.mixed_layer_depth.(times);
           color = :white, linewidth = 2)
    Colorbar(figure[2, 3], colors; label = "m² s⁻¹")
    save(filename, figure)
    preview && display(figure)
    return filename
end

# The difference panels resolve a grazing response even when curves overlap.
function MASTSWorkshop.plot_grazing_response(control, reduced, filename::AbstractString;
                                           figure_title::AbstractString = "Grazing experiment — surface phytoplankton and nitrate",
                                           preview::Bool = isinteractive())
    matching_times(control, reduced)
    figure = Figure(size = (1100, 740), fontsize = 15)
    Label(figure[0, :], figure_title; fontsize = 22, font = :bold)
    for (row, title, unit, metric) in ((1, "Phytoplankton", "mmol N m⁻³", d -> d.surface_P),
                                       (2, "Nitrate", "mmol N m⁻³", d -> d.surface_NO₃))
        axis = Axis(figure[row, 1]; title, xlabel = "Day", ylabel = unit)
        compare_lines!(axis, control, reduced, metric)
        axislegend(axis; position = :rt, framevisible = false)

        difference_axis = Axis(figure[row, 2]; title = "Change in $title",
                               xlabel = "Day", ylabel = "Reduced − control ($unit)")
        lines!(difference_axis, control.day, metric(reduced) .- metric(control);
               color = orange, linewidth = 2.5)
        hlines!(difference_axis, [0.0]; color = :gray, linestyle = :dot)
    end
    save(filename, figure)
    preview && display(figure)
    return filename
end

function MASTSWorkshop.plot_carbon_export(control, reduced, filename::AbstractString;
                                        figure_title::AbstractString = "Grazing experiment — carbon export",
                                        preview::Bool = isinteractive())
    matching_times(control, reduced)
    figure = Figure(size = (1550, 780), fontsize = 15)
    Label(figure[0, :], figure_title; fontsize = 22, font = :bold)
    for (row, depth, get_export) in ((1, 100, d -> d.export_100),
                                     (2, 300, d -> d.export_300))
        daily_axis = Axis(figure[row, 1]; title = "Daily export at $depth m",
                          xlabel = "Day", ylabel = "mg C m⁻² day⁻¹")
        compare_lines!(daily_axis, control, reduced, d -> get_export(d).daily_mg_C)
        axislegend(daily_axis; position = :rt, framevisible = false)

        cumulative_axis = Axis(figure[row, 2]; title = "Cumulative export at $depth m",
                               xlabel = "Day", ylabel = "g C m⁻²")
        compare_lines!(cumulative_axis, control, reduced, d -> get_export(d).cumulative_g_C)

        difference_axis = Axis(figure[row, 3]; title = "Change in cumulative export at $depth m",
                               xlabel = "Day", ylabel = "Reduced − control (g C m⁻²)")
        lines!(difference_axis, control.day,
               get_export(reduced).cumulative_g_C .- get_export(control).cumulative_g_C;
               color = orange, linewidth = 2.5)
        hlines!(difference_axis, [0.0]; color = :gray, linestyle = :dot)
    end
    save(filename, figure)
    preview && display(figure)
    return filename
end

# One comparison layout is reused by the self-paced parameter experiments.
function MASTSWorkshop.plot_parameter_response(control, changed, filename::AbstractString;
                                               label::AbstractString = "Modified",
                                               figure_title::Union{Nothing, AbstractString} = nothing,
                                               preview::Bool = isinteractive())
    matching_times(control, changed)
    metrics = (("Surface phytoplankton", "mmol N m⁻³", d -> d.surface_P),
               ("Surface nitrate", "mmol N m⁻³", d -> d.surface_NO₃),
               ("Upper 100 m detritus", "mmol N m⁻²", d -> d.upper_100m.detrital))
    figure = Figure(size = (1280, 1000), fontsize = 15)
    Label(figure[0, :], something(figure_title, "$label — surface response and detritus");
          fontsize = 22, font = :bold)
    for (row, (title, unit, metric)) in enumerate(metrics)
        axis = Axis(figure[row, 1]; title, xlabel = "Day", ylabel = unit)
        compare_lines!(axis, control, changed, metric; label)
        axislegend(axis; position = :rt, framevisible = false)

        difference = Axis(figure[row, 2]; title = "Change in $title",
                          xlabel = "Day", ylabel = "$label − control ($unit)")
        lines!(difference, control.day, metric(changed) .- metric(control);
               color = orange, linewidth = 2.5)
        hlines!(difference, [0.0]; color = :gray, linestyle = :dot)
    end
    save(filename, figure)
    preview && display(figure)
    return filename
end

function MASTSWorkshop.plot_parameter_export(control, changed, filename::AbstractString;
                                             label::AbstractString = "Modified",
                                             figure_title::Union{Nothing, AbstractString} = nothing,
                                             preview::Bool = isinteractive())
    matching_times(control, changed)
    figure = Figure(size = (1550, 780), fontsize = 15)
    Label(figure[0, :], something(figure_title, "$label — carbon export");
          fontsize = 22, font = :bold)
    for (row, depth, get_export) in ((1, 100, d -> d.export_100),
                                     (2, 300, d -> d.export_300))
        daily = Axis(figure[row, 1]; title = "Daily export at $depth m",
                     xlabel = "Day", ylabel = "mg C m⁻² day⁻¹")
        compare_lines!(daily, control, changed, d -> get_export(d).daily_mg_C; label)
        axislegend(daily; position = :rt, framevisible = false)

        cumulative = Axis(figure[row, 2]; title = "Cumulative export at $depth m",
                          xlabel = "Day", ylabel = "g C m⁻²")
        compare_lines!(cumulative, control, changed, d -> get_export(d).cumulative_g_C; label)

        difference = Axis(figure[row, 3]; title = "Change in cumulative export at $depth m",
                          xlabel = "Day", ylabel = "$label − control (g C m⁻²)")
        lines!(difference, control.day,
               get_export(changed).cumulative_g_C .- get_export(control).cumulative_g_C;
               color = orange, linewidth = 2.5)
        hlines!(difference, [0.0]; color = :gray, linestyle = :dot)
    end
    save(filename, figure)
    preview && display(figure)
    return filename
end

# North Atlantic locator map. The tiny coastline asset is a clipped, simplified
# public-domain Natural Earth 1:110m layer, committed for offline docs builds.
function MASTSWorkshop.plot_station_map(filename::AbstractString; preview::Bool = isinteractive())
    # CI renders the map from the curated numerical NetCDF via
    # scripts/plot_satellite_npp_map.py. Participant installations retain a
    # lightweight Natural Earth locator if no generated map is available.
    npp_map = joinpath(@__DIR__, "..", "..", "data", "maps",
                       "north_atlantic_cafe_npp_2023.png")
    if isfile(npp_map)
        mkpath(dirname(abspath(filename)))
        abspath(filename) == abspath(npp_map) || cp(npp_map, filename; force = true)
        return filename
    end
    coasts = joinpath(@__DIR__, "..", "..", "data", "maps", "north_atlantic_land.csv")
    figure = Figure(size = (1150, 650), fontsize = 17)
    axis = Axis(figure[1, 1]; xlabel = "Longitude (°)", ylabel = "Latitude (°)",
                aspect = DataAspect(), xticks = -80:20:20, yticks = 10:10:70,
                backgroundcolor = :aliceblue)
    points = Point2f[]
    function land!()
        if length(points) >= 3
            poly!(axis, copy(points); color = :gray90,
                  strokecolor = :gray65, strokewidth = 0.7)
        end
        empty!(points)
    end
    for line in eachline(coasts)
        s = strip(line)
        if isempty(s)
            land!()
        elseif !startswith(s, "#")
            lon, lat = parse.(Float32, split(s, ','))
            push!(points, Point2f(lon, lat))
        end
    end
    land!()
    scatter!(axis, [-64.17, -20.0], [31.67, 47.0]; color = [:steelblue, :darkorange],
             markersize = 23, strokewidth = 2, strokecolor = :white)
    text!(axis, -64.17, 31.67; text = "BATS", color = :steelblue,
          fontsize = 21, offset = (12, -10), align = (:left, :center))
    text!(axis, -20.0, 47.0; text = "NABE", color = :darkorange,
          fontsize = 21, offset = (12, 12), align = (:left, :center))
    xlims!(axis, -91, 18)
    ylims!(axis, 8, 68)
    save(filename, figure)
    preview && display(figure)
    return filename
end

# Two physical inputs used by the classroom BATS and NABE columns.
function MASTSWorkshop.plot_station_forcing(filename::AbstractString; preview::Bool = isinteractive())
    day = collect(0:2:365)
    time = day .* days
    figure = Figure(size = (1380, 560), fontsize = 17)

    light = Axis(figure[1, 1]; title = "Surface PAR", xlabel = "Day of year", ylabel = "W m⁻²")
    lines!(light, day, MASTSWorkshop.surface_PAR.(time);
           color = blue, linewidth = 3, label = "BATS")
    lines!(light, day, MASTSWorkshop.nabe_surface_PAR.(time);
           color = orange, linewidth = 3, label = "NABE")
    axislegend(light; position = :rt, framevisible = false)

    mixing = Axis(figure[1, 2]; title = "Prescribed mixing depth",
                  xlabel = "Day of year", ylabel = "Depth (m)")
    lines!(mixing, day, MASTSWorkshop.mixed_layer_depth.(time);
           color = blue, linewidth = 3, label = "BATS")
    lines!(mixing, day, MASTSWorkshop.nabe_mixed_layer_depth.(time);
           color = orange, linewidth = 3, label = "NABE")
    ylims!(mixing, -230, 0)
    axislegend(mixing; position = :lb, framevisible = false)
    save(filename, figure)
    preview && display(figure)
    return filename
end

# Upper 300 m of seasonal idealised vertical tracer diffusivity.
function MASTSWorkshop.plot_station_diffusivity(filename::AbstractString;
                                                preview::Bool = isinteractive())
    day = collect(0:2:365)
    time = day .* days
    grid = MASTSWorkshop.column(:BATS; deep = true).grid
    z = [depth for depth in znodes(grid, Center()) if depth >= -300]
    figure = Figure(size = (1430, 610), fontsize = 17)
    for (i, station) in enumerate((:BATS, :NABE))
        axis = Axis(figure[1, i]; title = string(station), xlabel = "Day of year",
                    ylabel = "Depth (m)")
        kappa = [MASTSWorkshop.vertical_diffusivity(station, depth, t)
                 for t in time, depth in z]
        hm = heatmap!(axis, day, z, kappa;
                      colormap = :viridis, colorscale = log10,
                      colorrange = (1e-4, 1.1e-2))
        mld = [MASTSWorkshop.mixed_layer_depth(station, t) for t in time]
        lines!(axis, day, mld; color = :white, linewidth = 2.5)
        lines!(axis, day, mld; color = :black, linestyle = :dash, linewidth = 1)
        ylims!(axis, -300, 0)
        if i == 2
            Colorbar(figure[1, 3], hm; label = "Kz (m² s⁻¹)",
                     ticks = [1e-4, 1e-3, 1e-2])
        end
    end
    save(filename, figure)
    preview && display(figure)
    return filename
end

# Compare the two annual ecosystem references on the same deep grid.
function MASTSWorkshop.plot_station_comparison(bats, nabe, filename::AbstractString;
                                              preview::Bool = isinteractive())
    matching_times(bats, nabe)
    isnothing(bats.export_1000) && throw(ArgumentError("BATS must use the deep grid"))
    isnothing(nabe.export_1000) && throw(ArgumentError("NABE must use the deep grid"))

    figure = Figure(size = (1250, 860), fontsize = 15)
    Label(figure[0, :], "Idealised BATS and NABE: annual ecosystem response";
          fontsize = 22, font = :bold)
    for (column, title, metric) in ((1, "Top 10 m phytoplankton", d -> d.surface_P),
                                    (2, "Top 10 m nitrate", d -> d.surface_NO₃))
        axis = Axis(figure[1, column]; title, xlabel = "Day", ylabel = "mmol N m⁻³")
        lines!(axis, bats.day, metric(bats); color = blue, linewidth = 2.5, label = "BATS")
        lines!(axis, nabe.day, metric(nabe); color = orange, linewidth = 2.5, label = "NABE")
        axislegend(axis; position = :rt, framevisible = false)
    end

    attenuation = Axis(figure[2, 1]; title = "Late-season particle flux attenuation",
                       xlabel = "F(z) / F(100)", ylabel = "Depth (m)")
    for (station, data, color) in (("BATS", bats, blue), ("NABE", nabe, orange))
        profile = data.export_profile
        index = findfirst(==(100), profile.depths)
        reference = profile.mean_daily_mg_C[index]
        if reference > 0
            selected = findall(d -> 100 <= d <= 1000, profile.depths)
            lines!(attenuation, profile.mean_daily_mg_C[selected] ./ reference,
                   .-profile.depths[selected]; color, linewidth = 2.5, label = station)
        end
    end
    axislegend(attenuation; position = :rt, framevisible = false)

    deep_export = Axis(figure[2, 2]; title = "Cumulative POC export at 1000 m",
                       xlabel = "Day", ylabel = "g C m⁻²")
    lines!(deep_export, bats.day, bats.export_1000.cumulative_g_C;
           color = blue, linewidth = 2.5, label = "BATS")
    lines!(deep_export, nabe.day, nabe.export_1000.cumulative_g_C;
           color = orange, linewidth = 2.5, label = "NABE")
    axislegend(deep_export; position = :lt, framevisible = false)
    save(filename, figure)
    preview && display(figure)
    return filename
end

end # module MASTSWorkshopMakieExt
