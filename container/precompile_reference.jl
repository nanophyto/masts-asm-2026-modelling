# Import-only PackageCompiler workload. The real column physics, output writers,
# and figures are exercised by the workshop tests and container smoke test.
# Keeping the sysimage independent of helper source preserves Docker cache reuse.
using OceanBioME, Oceananigans, CairoMakie
