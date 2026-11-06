module IdealisedPhysics

using Oceananigans.Units: days

export surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions, par_calibrated,
       nabe_surface_PAR, nabe_mixed_layer_depth, nabe_vertical_diffusivity,
       nabe_initial_conditions, deep_bats_initial_conditions

const year = 365days
include("par_forcing_coefficients.jl")

# NASA POWER 2001-2020 climatological 24-hour-mean surface PAR (W m^-2),
# fitted in log space with two periodic harmonics for a smooth, positive
# Oceananigans callback. The preparation script writes the coefficients;
# the initial version retains the former idealised forcing until extraction.
@inline function periodic_PAR(t, coefficients)
    θ = 2pi * t / year
    a, c1, s1, c2, s2 = coefficients
    return exp(a + c1 * cos(θ) + s1 * sin(θ) + c2 * cos(2θ) + s2 * sin(2θ))
end
par_calibrated() = PAR_COEFFICIENT_ORIGIN == "NASA POWER 2001-2020"
# The legacy expressions preserve previous reference results until the data
# extraction has been run. A full docs build requires the calibrated version.
surface_PAR(t) = par_calibrated() ? periodic_PAR(t, BATS_PAR_LOG_COEFFICIENTS) :
                 2 + 60 * (1 - cos(2pi * t / year))
surface_PAR(x, y, t) = surface_PAR(t)

# Smooth, periodic two-harmonic approximations to the GOSML monthly-mean MLD
# seasonal cycles (metres, positive down). Coefficients are deliberately
# rounded, guided by the BATS/NABE observational comparison rather than an
# exact fit. They preserve a fast, standalone forcing callback with no file I/O.
# The quantitative observed-versus-idealised fit is evaluated separately from
# the actual downloaded GOSML CSV in compare_mld_climatology().
@inline function seasonal_mld(t, mean, cos1, sin1, cos2, sin2)
    phase = 2pi * t / year
    return -(mean + cos1 * cos(phase) + sin1 * sin(phase) +
             cos2 * cos(2phase) + sin2 * sin(2phase))
end

# BATS: around 95 m late-winter maximum; around 15 m early-summer minimum.
mixed_layer_depth(t) = seasonal_mld(t, 48.3, 38.0, 9.9, 4.6, 7.9)

# Stronger turbulent mixing above the mixed-layer base (m^2 / s).
vertical_diffusivity(z, t) =
    1e-4 + 5e-3 * (1 + tanh((z - mixed_layer_depth(t)) / 10)) / 2
vertical_diffusivity(x, y, z, t) = vertical_diffusivity(z, t)

# Optional legacy uniform LOBSTER initial conditions, mmol N / m^3.
# The prepared station columns use depth-dependent profiles below.
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
nabe_surface_PAR(t) = par_calibrated() ? periodic_PAR(t, NABE_PAR_LOG_COEFFICIENTS) :
                      2 + 48 * (1 - cos(2pi * t / year))
nabe_surface_PAR(x, y, t) = nabe_surface_PAR(t)

# NABE: late-winter maximum around 190 m (February), rapid spring
# shoaling, a summer minimum around 20 m and gradual autumn deepening.
nabe_mixed_layer_depth(t) = seasonal_mld(t, 84.3, 66.5, 44.3, 1.2, 25.1)

nabe_vertical_diffusivity(z, t) =
    1e-4 + 1e-2 * (1 + tanh((z - nabe_mixed_layer_depth(t)) / 10)) / 2
nabe_vertical_diffusivity(x, y, z, t) = nabe_vertical_diffusivity(z, t)

# Station-aware accessors for plotting and evaluating the prescribed forcing.
# Model callbacks retain the signatures expected by Oceananigans.
function mixed_layer_depth(station::Symbol, t)
    station === :BATS && return mixed_layer_depth(t)
    station === :NABE && return nabe_mixed_layer_depth(t)
    throw(ArgumentError("Unknown station: $station"))
end
function vertical_diffusivity(station::Symbol, z, t)
    station === :BATS && return vertical_diffusivity(z, t)
    station === :NABE && return nabe_vertical_diffusivity(z, t)
    throw(ArgumentError("Unknown station: $station"))
end
function surface_PAR(station::Symbol, t)
    station === :BATS && return surface_PAR(t)
    station === :NABE && return nabe_surface_PAR(t)
    throw(ArgumentError("Unknown station: $station"))
end

# Provisional depth-varying nitrate fields (mmol N/m3), with winter conditions
# as the start of each annual simulation. Replace with WOA-derived station
# profiles once the comparison has been validated against observations.
# Flat/Flat/Bounded Oceananigans columns initialise fields by calling f(z).
# Retain three-coordinate overloads for interactive plotting and inspection.
bats_deep_nitrate(z) = 0.5 + 11.5 * (1 + tanh((-z - 150) / 75)) / 2
bats_deep_nitrate(x, y, z) = bats_deep_nitrate(z)
nabe_nitrate(z) = 6.0 + 6.0 * (1 + tanh((-z - 250) / 100)) / 2
nabe_nitrate(x, y, z) = nabe_nitrate(z)

# Begin with most plankton concentrated near the surface. These idealised
# profiles limit artificial deep plankton/particle inventories on both the
# 300 m teaching and 1200 m research columns. Spin-up sensitivity remains part of subsequent validation.
function deep_initial_conditions(nitrate)
    return (
        P = z -> 0.03 * exp(z / 75),
        Z = z -> 0.03 * exp(z / 100),
        NO₃ = nitrate,
        NH₄ = z -> 0.05 * exp(z / 200),
        DOM = z -> 0.02 * exp(z / 300),
        sPOM = z -> 0.01 * exp(z / 200),
        bPOM = z -> 0.005 * exp(z / 350),
    )
end

deep_bats_initial_conditions() = deep_initial_conditions(bats_deep_nitrate)
nabe_initial_conditions() = deep_initial_conditions(nabe_nitrate)

end
