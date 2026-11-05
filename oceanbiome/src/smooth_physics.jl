module SmoothPhysics

using TOML
using Oceananigans.Units: days

export SmoothDiffusivity, load_smooth_physics, smooth_mixed_layer_depth

"""
    SmoothDiffusivity

A binary vertical diffusivity with two constant values separated by a
smoothly moving annual mixing-depth boundary. `h(t)` is positive down and is
represented by two seasonal harmonics. At z >= -h(t), Kz is exactly `upper`;
below the boundary, Kz is exactly `deep`.
"""
struct SmoothDiffusivity <: Function
    station::Symbol
    coefficients::NTuple{5, Float64}
    upper::Float64
    deep::Float64
    period::Float64

    function SmoothDiffusivity(station::Symbol, coefficients, upper, deep;
                               period = 365days)
        station in (:BATS, :NABE) || throw(ArgumentError("Unknown station: $station"))
        length(coefficients) == 5 || throw(ArgumentError("Expected five seasonal MLD coefficients"))
        a = Tuple(Float64.(coefficients))
        all(isfinite, a) || throw(ArgumentError("MLD coefficients must be finite"))
        u, d, p = Float64(upper), Float64(deep), Float64(period)
        all(isfinite, (u, d, p)) && u > d >= 0 && p > 0 ||
            throw(ArgumentError("Require finite 0 ≤ Kdeep < Kupper and positive period"))
        new(station, a, u, d, p)
    end
end

"""Smooth positive-down mixing depth (metres), with a 10 m minimum."""
@inline function smooth_mixed_layer_depth(k::SmoothDiffusivity, t)
    phase = 2pi * t / k.period
    a, c1, s1, c2, s2 = k.coefficients
    h = a + c1 * cos(phase) + s1 * sin(phase) + c2 * cos(2phase) + s2 * sin(2phase)
    return max(10.0, h)
end

@inline function (k::SmoothDiffusivity)(z, t)
    h = smooth_mixed_layer_depth(k, t)
    return z >= -h ? k.upper : k.deep
end
(k::SmoothDiffusivity)(x, y, z, t) = k(z, t)

"""Read the small, recorded fit produced by `physics/fit_smooth_diffusivity.jl`."""
function load_smooth_physics(path::AbstractString; station::Symbol)
    isfile(path) || throw(ArgumentError("Missing smooth physics fit: $path"))
    config = TOML.parsefile(path)
    get(config, "station", nothing) == string(station) ||
        throw(ArgumentError("Smooth physics file $path is not for $station"))
    get(config, "fit_version", nothing) == 2 ||
        throw(ArgumentError("Expected a version 2 binary fit in $path; rerun physics/fit_smooth_diffusivity.jl"))
    get(config, "interface_type", nothing) == "binary_step" ||
        throw(ArgumentError("Expected a binary_step interface in $path"))
    return SmoothDiffusivity(
        station,
        config["mld_coefficients_m"],
        config["upper_diffusivity_m2_s"],
        config["deep_diffusivity_m2_s"];
        period = config["period_seconds"],
    )
end

end
