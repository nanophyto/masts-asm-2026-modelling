module IdealisedPhysics

using Oceananigans.Units: days

export surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions

const year = 365days

# Idealised Northern Hemisphere annual cycle. t = 0 corresponds to midwinter.
surface_PAR(t) = 2 + 60 * (1 - cos(2pi * t / year))  # W / m^2
surface_PAR(x, y, t) = surface_PAR(t)

# Negative depths: approximately 140 m in winter and 15 m in summer.
mixed_layer_depth(t) = -(15 + 125 * (1 + cos(2pi * t / year)) / 2)

# Stronger turbulent mixing above the mixed-layer base (m^2 / s).
vertical_diffusivity(x, y, z, t) =
    1e-4 + 5e-3 * (1 + tanh((z - mixed_layer_depth(t)) / 10)) / 2

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

end
