module SmoothPhysics

using TOML
using Oceananigans.Units: days

export SmoothDiffusivity, load_smooth_physics, smooth_mixed_layer_depth

"""
    SmoothDiffusivity

A binary vertical diffusivity with two constant values separated by a
smoothly moving annual mixing-depth boundary. `h(t)` is positive down and is
represented by two or three seasonal Fourier harmonics. At z >= -h(t), Kz is exactly `upper`;
below the boundary, Kz is exactly `deep`.
"""
struct SmoothDiffusivity{N} <: Function
    station::Symbol
    coefficients::NTuple{N, Float64}
    upper::Float64
    deep::Float64
    period::Float64

    function SmoothDiffusivity(station::Symbol, coefficients, upper, deep;
                               period = 365days)
        station in (:BATS, :NABE) || throw(ArgumentError("Unknown station: $station"))
        n = length(coefficients)
        n in (5, 7) || throw(ArgumentError("Expected 5 or 7 seasonal mixing-depth coefficients"))
        a = Tuple(Float64.(coefficients))
        all(isfinite, a) || throw(ArgumentError("MLD coefficients must be finite"))
        u, d, p = Float64(upper), Float64(deep), Float64(period)
        all(isfinite, (u, d, p)) && u > d >= 0 && p > 0 ||
            throw(ArgumentError("Require finite 0 ≤ Kdeep < Kupper and positive period"))
        new{n}(station, a, u, d, p)
    end
end

"""Smooth positive-down mixing depth (metres), with a 10 m minimum."""
@inline function smooth_mixed_layer_depth(k::SmoothDiffusivity{N}, t) where N
    phase = 2pi * t / k.period
    a, c1, s1, c2, s2 = k.coefficients[1:5]
    h = a + c1 * cos(phase) + s1 * sin(phase) + c2 * cos(2phase) + s2 * sin(2phase)
    if N == 7
        h += k.coefficients[6] * cos(3phase) + k.coefficients[7] * sin(3phase)
    end
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
    version = get(config, "fit_version", nothing)
    version in (2, 3, 4) ||
        throw(ArgumentError("Expected a version 2, 3, or 4 binary fit in $path"))
    get(config, "interface_type", nothing) == "binary_step" ||
        throw(ArgumentError("Expected a binary_step interface in $path"))
    expected_harmonics = version == 2 ? 2 : 3
    get(config, "harmonic_count", expected_harmonics) == expected_harmonics ||
        throw(ArgumentError("Invalid harmonic_count in $path"))
    length(config["mld_coefficients_m"]) == 1 + 2 * expected_harmonics ||
        throw(ArgumentError("Unexpected number of mixing-depth coefficients in $path"))
    if version == 4
        0 < get(config, "envelope_quantile", 0.0) < 1 ||
            throw(ArgumentError("Invalid envelope_quantile in $path"))
        window = get(config, "envelope_window_days", 0)
        window isa Integer && isodd(window) && window > 0 ||
            throw(ArgumentError("Invalid envelope_window_days in $path"))
    end
    return SmoothDiffusivity(
        station,
        config["mld_coefficients_m"],
        config["upper_diffusivity_m2_s"],
        config["deep_diffusivity_m2_s"];
        period = config["period_seconds"],
    )
end

end
