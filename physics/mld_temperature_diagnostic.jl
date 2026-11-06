# A published, explicitly defined temperature-based mixed-layer diagnostic.
# See de Boyer Montégut et al. (2004), JGR 109, C12003:
# reference depth 10 m, absolute temperature difference 0.2 °C.
module TemperatureMLD

export temperature_mld

function temperature_mld(centres, temperature; reference_depth = 10.0, threshold = 0.2)
    length(centres) == length(temperature) >= 2 ||
        throw(ArgumentError("Temperature and depth must have matching profiles"))
    all(>(0), diff(centres)) && all(isfinite, temperature) ||
        throw(ArgumentError("Depths must increase and temperatures be finite"))
    reference_depth > 0 && threshold > 0 || throw(ArgumentError("Invalid MLD criterion"))
    # Oceananigans depths are negative and ordered deepest to shallowest.
    # The actual 10 m reference lies between cell centres on this grid.
    zref = -reference_depth
    first(centres) < zref < last(centres) ||
        throw(ArgumentError("The reference depth must lie within the column"))
    k = searchsortedlast(centres, zref)
    α = (zref - centres[k]) / (centres[k + 1] - centres[k])
    tref = (1 - α) * temperature[k] + α * temperature[k + 1]
    previous_depth, previous_difference = reference_depth, 0.0
    # Search downward from the 10 m reference for the first threshold crossing.
    for i in k:-1:1
        depth = -centres[i]
        difference = abs(temperature[i] - tref)
        if difference >= threshold
            fraction = (threshold - previous_difference) / (difference - previous_difference)
            return previous_depth + fraction * (depth - previous_depth)
        end
        previous_depth, previous_difference = depth, difference
    end
    return -first(centres) # Criterion not reached: lower-bound estimate.
end

end
