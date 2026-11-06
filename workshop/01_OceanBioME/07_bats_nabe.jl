# # BATS and NABE: idealised physical environments
#
# Two North Atlantic sites provide contrasting seasonal light and mixing for
# the biogeochemistry exercises. The plots below use the classroom forcing
# functions directly, so they always reflect the reference column setup.

using MASTSWorkshop, CairoMakie
using MASTSWorkshop: results_directory, plot_station_map,
                     plot_station_forcing, plot_station_diffusivity

output_dir = results_directory("bats_nabe")

# ## 1. Where are BATS and NABE?
#
# BATS is in the subtropical western North Atlantic (31.67°N, 64.17°W).
# NABE represents the temperate northeast Atlantic (47°N, 20°W).

map_figure = joinpath(output_dir, "station_map.png")
plot_station_map(map_figure)

#md # WORKSHOP_STATION_MAP_FIGURE

# ## 2. Seasonal PAR and mixing depth
#
# The two sites have different seasonal light and mixing regimes.

forcing_figure = joinpath(output_dir, "station_forcing.png")
plot_station_forcing(forcing_figure)

#md # WORKSHOP_STATION_FORCING_FIGURE

# ## 3. Vertical diffusivity
#
# Colour shows vertical tracer diffusivity through the upper 300 m.
# The dashed curves trace the prescribed mixing depths.

diffusivity_figure = joinpath(output_dir, "station_diffusivity.png")
plot_station_diffusivity(diffusivity_figure)

#md # WORKSHOP_STATION_DIFFUSIVITY_FIGURE
