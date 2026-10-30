# Plotting is loaded after the model runs; the --quick CI smoke test skips Makie.
using CairoMakie

function plot_grazing(control, reduced, filename)
    figure = Figure(size = (1250, 760), fontsize = 15)
    panels = (
        (1, 1, "Surface phytoplankton", "mmol N m⁻³", :surface_P),
        (1, 2, "Surface nitrate", "mmol N m⁻³", :surface_NO₃),
        (1, 3, "Carbon export at 100 m", "mg C m⁻² day⁻¹", :daily_100),
        (2, 1, "Carbon export at 300 m", "mg C m⁻² day⁻¹", :daily_300),
        (2, 2, "Cumulative export at 100 m", "g C m⁻²", :cumulative_100),
        (2, 3, "Cumulative export at 300 m", "g C m⁻²", :cumulative_300),
    )

    # The plotted quantities come from the same diagnosed numerical results as the CSV.
    function metric(d, name)
        name === :surface_P && return d.surface_P
        name === :surface_NO₃ && return d.surface_NO₃
        name === :daily_100 && return d.export_100.daily_mg_C
        name === :daily_300 && return d.export_300.daily_mg_C
        name === :cumulative_100 && return d.export_100.cumulative_g_C
        return d.export_300.cumulative_g_C
    end

    for (row, col, heading, unit, name) in panels
        axis = Axis(figure[row, col]; title = heading, xlabel = "Day", ylabel = unit)
        lines!(axis, control.day, metric(control, name); label = "Control",
               color = :steelblue, linewidth = 2.5)
        lines!(axis, reduced.day, metric(reduced, name); label = "Reduced grazing",
               color = :darkorange, linestyle = :dash, linewidth = 2.5)
        if row == 1 && col == 1
            axislegend(axis; position = :rt, framevisible = false)
        end
    end

    save(filename, figure)
    return filename
end
