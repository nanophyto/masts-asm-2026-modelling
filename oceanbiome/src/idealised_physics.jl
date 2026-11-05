module IdealisedPhysics

using Oceananigans.Units: days

export surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions,
       nabe_surface_PAR, nabe_mixed_layer_depth, nabe_vertical_diffusivity,
       nabe_initial_conditions, deep_bats_initial_conditions

const year = 365days

# Idealised Northern Hemisphere annual cycle. t = 0 corresponds to midwinter.
surface_PAR(t) = 2 + 60 * (1 - cos(2pi * t / year))  # W / m^2
surface_PAR(x, y, t) = surface_PAR(t)

# Negative depths: approximately 140 m in winter and 15 m in summer.
mixed_layer_depth(t) = -(15 + 125 * (1 + cos(2pi * t / year)) / 2)

# Stronger turbulent mixing above the mixed-layer base (m^2 / s).
vertical_diffusivity(z, t) =
    1e-4 + 5e-3 * (1 + tanh((z - mixed_layer_depth(t)) / 10)) / 2
vertical_diffusivity(x, y, z, t) = vertical_diffusivity(z, t)

# LOBSTER core tracer concentrations, mmol N / m^3.
initial_conditions() = (
    P = 0.03,
    Z = 0.03,
    NO₃ = 4.0,
    NH₄ = 0.05,
    DOM = 0.02,
    sPOM = 0.01,
    bPOM = 0.005,
)

# Idealised North Atlantic Bloom Experiment (NABE; approximately 47 N, 20 W).
# t = 0 is midwinter. These curves are tunable teaching assumptions based on
# the North Atlantic seasonal regime, not a reconstruction of the 1989 cruise.
nabe_surface_PAR(t) = 2 + 48 * (1 - cos(2pi * t / year))
nabe_surface_PAR(x, y, t) = nabe_surface_PAR(t)

# Rapid spring shoaling and autumn deepening; roughly 350 m winter / 20 m summer.
function nabe_mixed_layer_depth(t)
    day = mod(t, year) / days
    spring = 1 / (1 + exp(-(day - 100) / 10))
    autumn = 1 / (1 + exp(-(day - 290) / 15))
    return -(20 + 330 * (1 - spring * (1 - autumn)))
end

nabe_vertical_diffusivity(z, t) =
    1e-4 + 1e-2 * (1 + tanh((z - nabe_mixed_layer_depth(t)) / 10)) / 2
nabe_vertical_diffusivity(x, y, z, t) = nabe_vertical_diffusivity(z, t)

# Provisional depth-varying nitrate fields (mmol N/m3), with winter conditions
# as the start of each annual simulation. Replace with WOA-derived station
# profiles once the comparison has been validated against observations.
bats_deep_nitrate(x, y, z) = 0.5 + 11.5 * (1 + tanh((-z - 150) / 75)) / 2
nabe_nitrate(x, y, z) = 6.0 + 6.0 * (1 + tanh((-z - 250) / 100)) / 2

# Begin with most plankton concentrated near the surface. These idealised
# profiles limit artificial deep plankton/particle inventories on a 1200 m
# column. Spin-up sensitivity remains part of subsequent validation.
function deep_initial_conditions(nitrate)
    return (
        P = (x, y, z) -> 0.03 * exp(z / 75),
        Z = (x, y, z) -> 0.03 * exp(z / 100),
        NO₃ = nitrate,
        NH₄ = (x, y, z) -> 0.05 * exp(z / 200),
        DOM = (x, y, z) -> 0.02 * exp(z / 300),
        sPOM = (x, y, z) -> 0.01 * exp(z / 200),
        bPOM = (x, y, z) -> 0.005 * exp(z / 350),
    )
end

deep_bats_initial_conditions() = deep_initial_conditions(bats_deep_nitrate)
nabe_initial_conditions() = deep_initial_conditions(nabe_nitrate)

end
