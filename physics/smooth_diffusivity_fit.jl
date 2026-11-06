# Fit a smooth two-layer 1D mixing cycle from saved CATKE Kz.
# Kz defines the actively mixing-layer boundary; T-derived MLD is a diagnostic.

module SmoothDiffusivityFit

export fit_smooth_diffusivity, mixing_depth_from_profile, fit_mld_harmonics, rolling_mixing_depth_quantile

using Statistics: median, quantile
using Oceananigans.Units: days
using MASTSWorkshop: SmoothDiffusivity, smooth_mixed_layer_depth

include(joinpath(@__DIR__, "mld_temperature_diagnostic.jl"))
using .TemperatureMLD: temperature_mld

function fit_mld_harmonics(t, h; period = 365days, harmonics = 3)
    harmonics in (2, 3) || throw(ArgumentError("Expected two or three seasonal harmonics"))
    length(t) == length(h) >= 2 * harmonics + 1 ||
        throw(ArgumentError("Insufficient daily mixing depths for the harmonic fit"))
    θ = 2pi .* t ./ period
    basis = Matrix{Float64}(undef, length(t), 1 + 2 * harmonics)
    basis[:, 1] .= 1
    for n in 1:harmonics
        basis[:, 2 * n] .= cos.(n .* θ)
        basis[:, 2 * n + 1] .= sin.(n .* θ)
    end
    return Tuple(basis \ h)
end

# The surface face can be zero because of the boundary condition. Use cell-
# centred Kz, and find the first downward crossing of the midpoint in log Kz
# between the actively mixed surface and the deep background. This estimates
# a *mixing depth*, not a density- or temperature-defined MLD.
function mixing_depth_from_profile(centres, diffusivity;
                                   surface_reference_depth = 25.0,
                                   deep_reference_depth = 500.0,
                                   max_depth = 450.0, min_depth = 10.0)
    length(centres) == length(diffusivity) >= 3 ||
        throw(ArgumentError("Depth and diffusivity profiles must match"))
    logκ = log10.(max.(diffusivity, 1e-10))
    surface = logκ[(-centres) .<= surface_reference_depth]
    deep = logκ[(-centres) .>= deep_reference_depth]
    isempty(surface) && throw(ArgumentError("No surface cells for mixing-depth estimate"))
    isempty(deep) && throw(ArgumentError("No deep reference cells for mixing-depth estimate"))
    top, bottom = median(surface), median(deep)
    top - bottom >= 1.0 || return min_depth
    threshold = (top + bottom) / 2

    # A three-cell median suppresses isolated low-Kz points in the upper layer.
    profile = [median(view(logκ, max(1, k - 1):min(length(logκ), k + 1)))
               for k in eachindex(logκ)]
    profile[end] > threshold || return min_depth
    for k in (length(centres) - 1):-1:1
        -centres[k] > max_depth && break
        if profile[k] <= threshold < profile[k + 1]
            fraction = (threshold - profile[k + 1]) / (profile[k] - profile[k + 1])
            return clamp(-(centres[k + 1] + fraction * (centres[k] - centres[k + 1])),
                         min_depth, max_depth)
        end
    end
    return max_depth
end

function daily_mixing_depth(forcing; period = 365days)
    times, faces, centres = forcing.seconds, forcing.faces, forcing.centres
    isapprox(period, 365days; rtol = 0, atol = 1e-6) ||
        throw(ArgumentError("Expected a 365-day CATKE forcing year"))
    last(times) >= period - 1e-6 ||
        throw(ArgumentError("A full 365-day CATKE output is required"))
    cell_k = (forcing.diffusivity[1:end-1, :] .+
              forcing.diffusivity[2:end, :]) ./ 2
    daily_depths = Vector{Float64}(undef, 365)
    daily_times = (collect(0:364) .+ 0.5) .* days
    i = firstindex(times)
    for d in 0:364
        first_sample = i
        while i <= lastindex(times) && times[i] < (d + 1) * days
            i += 1
        end
        first_sample < i || throw(ArgumentError("Missing CATKE data for day $(d + 1)"))
        profile = [median(view(cell_k, k, first_sample:(i - 1)))
                   for k in eachindex(centres)]
        daily_depths[d + 1] = mixing_depth_from_profile(centres, profile)
    end
    return daily_times, daily_depths
end

"""
    rolling_mixing_depth_quantile(depths; probability = 0.75, window_days = 21)

Centred, circular running quantile of daily positive-down CATKE mixing depths.
The 21-day window wraps around the end of the year, preserving a periodic
seasonal target; a 75th percentile represents regularly attained deep mixing
rather than single-day extremes.
"""
function rolling_mixing_depth_quantile(depths; probability = 0.75, window_days = 21)
    0 < probability < 1 || throw(ArgumentError("Quantile probability must be between 0 and 1"))
    isodd(window_days) && 1 <= window_days <= length(depths) ||
        throw(ArgumentError("Window must be odd, positive, and no longer than the daily series"))
    all(x -> isfinite(x) && x > 0, depths) ||
        throw(ArgumentError("Mixing depths must be finite and positive"))
    half = (window_days - 1) ÷ 2
    n = length(depths)
    return [quantile([Float64(depths[mod1(i + offset, n)]) for offset in -half:half],
                     probability) for i in eachindex(depths)]
end

# A thickness- and time-weighted median selects a representative diffusivity
# without letting intermittent extreme Kz events dominate either layer.
function weighted_median(values, weights)
    isempty(values) && throw(ArgumentError("No diffusivity samples"))
    halfway = sum(weights) / 2
    total = 0.0
    for i in sortperm(values)
        total += weights[i]
        total >= halfway && return values[i]
    end
    return last(values)
end

"""
    fit_smooth_diffusivity(forcing, station; exclusion_band = 15, surface_exclusion_depth = 20,
                           deep_fit_limit = 300)

Fit a three-harmonic seasonal curve to the circular 21-day running 75th
percentile of CATKE-defined daily mixing depths. Retain the three-harmonic
least-squares fit to the original daily depths as a comparison. Representative
upper/deep diffusivities are unchanged: thickness/time-weighted medians in
the previous two-harmonic sampling regions. The resulting diffusivity is an
exact binary step.
"""
function fit_smooth_diffusivity(forcing, station::Symbol;
                                exclusion_band = 15.0,
                                surface_exclusion_depth = 20.0,
                                deep_fit_limit = 300.0,
                                envelope_probability = 0.75,
                                envelope_window_days = 21,
                                period = 365days)
    exclusion_band >= 0 && surface_exclusion_depth >= 0 && deep_fit_limit > 0 ||
        throw(ArgumentError("Expected non-negative exclusions and positive deep fit limit"))
    times = forcing.seconds
    faces, centres = forcing.faces, forcing.centres
    daily_times, daily_depths = daily_mixing_depth(forcing; period)
    two_harmonic_coeff = fit_mld_harmonics(daily_times, daily_depths; period, harmonics = 2)
    three_harmonic_coeff = fit_mld_harmonics(daily_times, daily_depths; period, harmonics = 3)
    envelope_depths = rolling_mixing_depth_quantile(daily_depths;
                                                    probability = envelope_probability,
                                                    window_days = envelope_window_days)
    envelope_coeff = fit_mld_harmonics(daily_times, envelope_depths; period, harmonics = 3)
    raw_temperature_mld = [temperature_mld(centres, view(forcing.temperature, :, j))
                           for j in eachindex(times)]

    # Depth is negative, so the upper layer is z >= -h(t). Cell-volume
    # fractions ensure partial cells at the boundaries are properly counted.
    upper_values, upper_weights = Float64[], Float64[]
    lower_values, lower_weights = Float64[], Float64[]
    # Keep the original two-harmonic sampling boundary so that changing
    # the number of harmonics does not change either representative Kz value.
    boundary_model = SmoothDiffusivity(station, two_harmonic_coeff, 1.0, 0.0; period)
    for j in 1:(length(times) - 1)  # exclude next January's repeated endpoint
        dt = times[j + 1] - times[j]
        boundary = -smooth_mixed_layer_depth(boundary_model, times[j])
        for k in eachindex(centres)
            low, high = faces[k], faces[k + 1]
            κ = (forcing.diffusivity[k, j] + forcing.diffusivity[k + 1, j]) / 2
            # Sample the mixed layer below the excluded surface band.
            # The upper bound is -surface_exclusion_depth, not the sea surface;
            # using it as a lower bound would select only the excluded band.
            upper_thickness = max(0.0, min(high, -surface_exclusion_depth) -
                                      max(low, boundary + exclusion_band))
            lower_thickness = max(0.0, min(high, boundary - exclusion_band) -
                                      max(low, -deep_fit_limit))
            if upper_thickness > 0
                push!(upper_values, κ)
                push!(upper_weights, upper_thickness * dt)
            end
            if lower_thickness > 0
                push!(lower_values, κ)
                push!(lower_weights, lower_thickness * dt)
            end
        end
    end
    upper = weighted_median(upper_values, upper_weights)
    deep = weighted_median(lower_values, lower_weights)
    upper > deep || throw(ArgumentError("Upper diffusivity must exceed deep background"))
    previous_model = SmoothDiffusivity(station, two_harmonic_coeff, upper, deep; period)
    mean_model = SmoothDiffusivity(station, three_harmonic_coeff, upper, deep; period)
    model = SmoothDiffusivity(station, envelope_coeff, upper, deep; period)
    rms(m, depths) = sqrt(sum(abs2, [smooth_mixed_layer_depth(m, t) - h
                                     for (t, h) in zip(daily_times, depths)]) / length(depths))
    return (; model, mean_model, previous_model,
             raw_temperature_mld, daily_times, daily_depths, envelope_depths,
             previous_rmse = rms(previous_model, daily_depths),
             mean_rmse = rms(mean_model, daily_depths),
             envelope_rmse = rms(model, envelope_depths),
             envelope_daily_rmse = rms(model, daily_depths),
             envelope_probability, envelope_window_days,
             exclusion_band, surface_exclusion_depth, deep_fit_limit)
end

end # module SmoothDiffusivityFit
