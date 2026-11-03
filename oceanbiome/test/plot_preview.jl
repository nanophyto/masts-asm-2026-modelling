using CairoMakie

struct PreviewCapture <: Base.Multimedia.AbstractDisplay
    count::Base.RefValue{Int}
end
Base.display(d::PreviewCapture, ::CairoMakie.Figure) = (d.count[] += 1; nothing)

@testset "Scientific plot previews" begin
    @test !isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt))
    day = [0.0, 1.0, 2.0]
    z = [-20.0, -10.0, 0.0]
    values = fill(0.1, 3, 3)
    control = (; day, z, vertical_Z = values, vertical_P = values, vertical_NO₃ = values,
               vertical_sPOM = values, vertical_bPOM = values, vertical_DOM = values,
               surface_P = [0.1, 0.2, 0.3], surface_NO₃ = [1.0, 0.9, 0.8])
    reduced = (; day, surface_P = [0.2, 0.3, 0.4], surface_NO₃ = [0.9, 0.8, 0.7])
    capture = PreviewCapture(Ref(0))
    Base.Multimedia.pushdisplay(capture)
    try
        mktempdir() do dir
            for (i, (plot, args, name)) in enumerate(((MASTSWorkshop.plot_vertical_evolution,
                                                        (control,), "reference.png"),
                                                       (MASTSWorkshop.plot_grazing_response,
                                                        (control, reduced), "grazing.png")))
                filename = joinpath(dir, name)
                @test plot(args..., filename; preview = false) == filename
                @test isfile(filename) && filesize(filename) > 1000
                @test capture.count[] == i - 1
                @test plot(args..., filename; preview = true) == filename
                @test capture.count[] == i
            end
        end
    finally
        Base.Multimedia.popdisplay(capture)
    end
end
