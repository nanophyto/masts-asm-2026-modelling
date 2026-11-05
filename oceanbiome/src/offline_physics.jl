module OfflinePhysics

using Oceananigans: FieldTimeSeries, Center, Face
using Oceananigans.Fields: interior
using Oceananigans.Grids: znodes

export OfflineColumnForcing, OfflineDiffusivity, load_offline_physics,
       offline_diffusivity, offline_temperature

"""
    OfflineColumnForcing

In-memory, one-dimensional snapshots from NumericalEarth's JLD2Writer:
`κc` is sampled at vertical faces (m²/s), `T` at cell centres (°C).
Times are seconds elapsed since the first saved snapshot, with no implicit periodic repetition.
"""
struct OfflineColumnForcing
    faces::Vector{Float64}
    centres::Vector{Float64}
    seconds::Vector{Float64}
    diffusivity::Matrix{Float64}
    temperature::Matrix{Float64}

    function OfflineColumnForcing(faces, centres, seconds, diffusivity, temperature)
        zf, zc, t = Float64.(faces), Float64.(centres), Float64.(seconds)
        κ, T = Matrix{Float64}(diffusivity), Matrix{Float64}(temperature)
        length(zf) == length(zc) + 1 || throw(ArgumentError("Invalid face/centre grid"))
        length(t) >= 2 || throw(ArgumentError("At least two time samples are required"))
        all(isfinite, zf) && all(isfinite, zc) && all(isfinite, t) ||
            throw(ArgumentError("Non-finite depths or times"))
        all(>(0), diff(zf)) && all(>(0), diff(zc)) && all(>(0), diff(t)) ||
            throw(ArgumentError("Depths and times must increase strictly"))
        size(κ) == (length(zf), length(t)) || throw(ArgumentError("Invalid κc dimensions"))
        size(T) == (length(zc), length(t)) || throw(ArgumentError("Invalid temperature dimensions"))
        all(x -> isfinite(x) && x >= 0, κ) || throw(ArgumentError("Invalid diffusivity"))
        all(isfinite, T) || throw(ArgumentError("Invalid temperature"))
        new(zf, zc, t, κ, T)
    end
end

"""Load only κc and temperature from a NumericalEarth one-column JLD2 file."""
function load_offline_physics(path::AbstractString)
    isfile(path) || throw(ArgumentError("Missing NumericalEarth column: $path"))
    κc = FieldTimeSeries(path, "κc")
    T = FieldTimeSeries(path, "T")
    t = collect(κc.times)
    length(T.times) == length(t) && all(T.times .== t) ||
        throw(ArgumentError("κc and T have different output times"))
    # Physical spin-up continues on the same clock. A file covering days
    # 365-730 must drive the offline biology at days 0-365.
    elapsed = Float64.(t) .- first(t)
    faces = collect(znodes(κc.grid, Face()))
    centres = collect(znodes(T.grid, Center()))
    κ = hcat((collect(interior(κc[i], 1, 1, :)) for i in eachindex(t))...)
    temp = hcat((collect(interior(T[i], 1, 1, :)) for i in eachindex(t))...)
    return OfflineColumnForcing(faces, centres, elapsed, κ, temp)
end

# Piecewise-linear interpolation in z and time: this transports the Kz
# computed by CATKE without constructing any new turbulence parameterization.
@inline function interpolate_profile(zs, ts, values, z, t)
    time = Float64(t)
    0 <= time <= last(ts) + 1e-6 ||
        throw(ArgumentError("Time $time is outside offline forcing (0 to $(last(ts)) s)"))
    iz = clamp(searchsortedlast(zs, Float64(z)), 1, length(zs) - 1)
    it = clamp(searchsortedlast(ts, time), 1, length(ts) - 1)
    wz = clamp((z - zs[iz]) / (zs[iz + 1] - zs[iz]), 0.0, 1.0)
    wt = clamp((time - ts[it]) / (ts[it + 1] - ts[it]), 0.0, 1.0)
    k0 = (1 - wz) * values[iz, it] + wz * values[iz + 1, it]
    k1 = (1 - wz) * values[iz, it + 1] + wz * values[iz + 1, it + 1]
    return (1 - wt) * k0 + wt * k1
end

"""Return tracer eddy diffusivity at depth `z` and elapsed time `t` (seconds)."""
offline_diffusivity(forcing::OfflineColumnForcing, z, t) =
    interpolate_profile(forcing.faces, forcing.seconds, forcing.diffusivity, z, t)

"""Return physical temperature (°C) at depth `z` and elapsed time `t`."""
offline_temperature(forcing::OfflineColumnForcing, z, t) =
    interpolate_profile(forcing.centres, forcing.seconds, forcing.temperature, z, t)

# Oceananigans can evaluate Flat columns with (z, t) and also supports the
# regular (x, y, z, t) callback signature. Accept both forms, as the
# existing idealised diffusivity functions do.
# Oceananigans ScalarDiffusivity requires κ to be a Function, Number,
# AbstractArray, or named tracer diffusivities; a merely callable struct
# is not accepted by its tracer_diffusivities dispatch.
struct OfflineDiffusivity <: Function
    forcing::OfflineColumnForcing
end
(κ::OfflineDiffusivity)(z, t) = offline_diffusivity(κ.forcing, z, t)
(κ::OfflineDiffusivity)(x, y, z, t) = offline_diffusivity(κ.forcing, z, t)

end
