module MASTSWorkshopMakieExt

using MASTSWorkshop
using CairoMakie
using Oceananigans.Units: days

const blue = :steelblue
const orange = :darkorange

function matching_times(control, reduced)
    control.day == reduced.day || throw(ArgumentError("The two simulations must have matching output times"))
end

function compare_lines!(axis, control, reduced, metric)
    lines!(axis, control.day, metric(control); color = blue, linewidth = 2.5, label = "Control")
    lines!(axis, reduced.day, metric(reduced); color = orange, linestyle = :dash,
           linewidth = 2.5, label = "Reduced grazing")
    return axis
end

# Show the evolving vertical structure of the main LOBSTER tracers.
function MASTSWorkshop.plot_vertical_evolution(control, filename::AbstractString)
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
    return filename
end

# Plot the two sinking-flux horizons for a single reference simulation.
function MASTSWorkshop.plot_reference_export(reference, filename::AbstractString)
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
    return filename
end

# Compare the modelled depth-dependent sinking flux with a Martin-curve benchmark.
function MASTSWorkshop.plot_export_profile(reference, filename::AbstractString)
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
    return filename
end

# Describe the physical environment actually used by the idealised column.
function MASTSWorkshop.plot_idealised_physics(filename::AbstractString)
    day_samples = collect(0:5:365)
    times = day_samples .* days
    depths = collect(range(-500.0, 0.0; length = 101))
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
    return filename
end

# The difference panels resolve a grazing response even when curves overlap.
function MASTSWorkshop.plot_grazing_response(control, reduced, filename::AbstractString)
    matching_times(control, reduced)
    figure = Figure(size = (1100, 740), fontsize = 15)
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
    return filename
end

function MASTSWorkshop.plot_carbon_export(control, reduced, filename::AbstractString)
    matching_times(control, reduced)
    figure = Figure(size = (1550, 780), fontsize = 15)
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
    return filename
end

end
