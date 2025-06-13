@testsetup module PretrainedWeightsTestSetup

using Lux, Downloads, JLD2, Pickle, Reactant

function normalize_imagenet(data)
    cmean = reshape(Float32[0.485, 0.456, 0.406], (1, 1, 3, 1))
    cstd = reshape(Float32[0.229, 0.224, 0.225], (1, 1, 3, 1))
    return (data .- cmean) ./ cstd
end

# The images are normalized and saved
@load joinpath(@__DIR__, "testimages", "monarch_color.jld2") monarch_color_224 monarch_color_256
const MONARCH_224 = monarch_color_224
const MONARCH_256 = monarch_color_256

const TEST_LBLS = readlines(
    Downloads.download(
        "https://raw.githubusercontent.com/pytorch/hub/master/imagenet_classes.txt"
    ),
)

function imagenet_acctest(model, ps, st, dev; size=224)
    ps = dev(ps)
    st = dev(Lux.testmode(st))
    TEST_X = if size == 224
        MONARCH_224
    else
        (size == 256 ? MONARCH_256 : error("size must be 224 or 256"))
    end
    x = dev(TEST_X)

    if dev isa ReactantDevice
        model = @compile model(x, ps, st)
    end

    ypred = vec(collect(cpu_device()(first(model(x, ps, st)))))
    top5 = TEST_LBLS[partialsortperm(ypred, 1:5; rev=true)]
    return "monarch" in top5
end

export imagenet_acctest

end

@testitem "AlexNet" setup = [SharedTestSetup, PretrainedWeightsTestSetup] tags = [:vision] begin
    for (mode, aType, dev) in MODES
        @testset "pretrained: $(pretrained)" for pretrained in [true, false]
            model = Vision.AlexNet(; pretrained)
            ps, st = dev(Lux.setup(Random.default_rng(), model))
            st = Lux.testmode(st)
            img = aType(randn(Float32, 224, 224, 3, 2))

            @test size(first(model(img, ps, st))) == (1000, 2)

            if pretrained
                @test imagenet_acctest(model, ps, st, dev)
            end

            GC.gc(true)

            if test_reactant(mode)
                set_reactant_backend!(mode)

                rdev = reactant_device(; force=true)

                ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

                @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol =
                    1e-3 rtol = 1e-3

                if pretrained
                    @test imagenet_acctest(model, ps, st, rdev)
                end
            end
        end
    end
end

@testitem "ConvMixer" setup = [SharedTestSetup] tags = [:vision_metalhead] begin
    using Metalhead: Metalhead

    for (mode, aType, dev) in MODES, name in [:small, :base, :large]
        model = Vision.ConvMixer(name; pretrained=false)
        ps, st = dev(Lux.setup(Random.default_rng(), model))
        st = Lux.testmode(st)
        img = aType(randn(Float32, 256, 256, 3, 2))

        @test size(first(model(img, ps, st))) == (1000, 2)

        GC.gc(true)

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

            @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol = 1e-3 rtol =
                1e-3
        end
    end
end

@testitem "GoogLeNet" setup = [SharedTestSetup] tags = [:vision_metalhead] begin
    using Metalhead: Metalhead

    for (mode, aType, dev) in MODES
        model = Vision.GoogLeNet(; pretrained=false)
        ps, st = dev(Lux.setup(Random.default_rng(), model))
        st = Lux.testmode(st)
        img = aType(randn(Float32, 224, 224, 3, 2))

        @test size(first(model(img, ps, st))) == (1000, 2)

        GC.gc(true)

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

            @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol = 1e-3 rtol =
                1e-3
        end
    end
end

@testitem "MobileNet" setup = [SharedTestSetup] tags = [:vision_metalhead] begin
    using Metalhead: Metalhead

    for (mode, aType, dev) in MODES, name in [:v1, :v2, :v3_small, :v3_large]
        model = Vision.MobileNet(name; pretrained=false)
        ps, st = dev(Lux.setup(Random.default_rng(), model))
        st = Lux.testmode(st)
        img = aType(randn(Float32, 224, 224, 3, 2))

        @test size(first(model(img, ps, st))) == (1000, 2)

        GC.gc(true)

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

            @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol = 1e-3 rtol =
                1e-3
        end
    end
end

@testitem "ResNet" setup = [SharedTestSetup, PretrainedWeightsTestSetup] tags = [
    :vision_metalhead
] begin
    using Metalhead: Metalhead

    for (mode, aType, dev) in MODES, depth in [18, 34, 50, 101, 152]
        @testset for pretrained in [false, true]
            pretrained && pkgversion(Metalhead) > v"0.9.4" && continue

            model = Vision.ResNet(depth; pretrained)
            ps, st = dev(Lux.setup(Random.default_rng(), model))
            st = Lux.testmode(st)
            img = aType(randn(Float32, 224, 224, 3, 2))

            @test size(first(model(img, ps, st))) == (1000, 2)

            if pretrained
                @test imagenet_acctest(model, ps, st, dev)
            end

            GC.gc(true)

            if test_reactant(mode)
                set_reactant_backend!(mode)

                rdev = reactant_device(; force=true)

                ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

                @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol =
                    1e-3 rtol = 1e-3

                if pretrained
                    @test imagenet_acctest(model, ps, st, rdev)
                end
            end
        end
    end
end

@testitem "ResNeXt" setup = [SharedTestSetup, PretrainedWeightsTestSetup] tags = [
    :vision_metalhead
] begin
    using Metalhead: Metalhead

    for (mode, aType, dev) in MODES
        @testset for (depth, cardinality, base_width) in
                     [(50, 32, 4), (101, 32, 8), (101, 64, 4), (152, 64, 4)]
            @testset for pretrained in [false, true]
                depth == 152 && pretrained && continue
                pretrained && pkgversion(Metalhead) > v"0.9.4" && continue

                model = Vision.ResNeXt(depth; pretrained, cardinality, base_width)
                ps, st = dev(Lux.setup(Random.default_rng(), model))
                st = Lux.testmode(st)
                img = aType(randn(Float32, 224, 224, 3, 2))

                @test size(first(model(img, ps, st))) == (1000, 2)

                if pretrained
                    @test imagenet_acctest(model, ps, st, dev)
                end

                GC.gc(true)

                if test_reactant(mode)
                    set_reactant_backend!(mode)

                    rdev = reactant_device(; force=true)

                    ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

                    @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol =
                        1e-3 rtol = 1e-3

                    if pretrained
                        @test imagenet_acctest(model, ps, st, rdev)
                    end
                end
            end
        end
    end
end

@testitem "WideResNet" setup = [SharedTestSetup, PretrainedWeightsTestSetup] tags = [
    :vision_metalhead
] begin
    using Metalhead: Metalhead

    for (mode, aType, dev) in MODES, depth in [50, 101, 152]
        @testset for pretrained in [false, true]
            depth == 152 && pretrained && continue
            pretrained && pkgversion(Metalhead) > v"0.9.4" && continue

            model = Vision.WideResNet(depth; pretrained)
            ps, st = dev(Lux.setup(Random.default_rng(), model))
            st = Lux.testmode(st)
            img = aType(randn(Float32, 224, 224, 3, 2))

            @test size(first(model(img, ps, st))) == (1000, 2)

            if pretrained
                @test imagenet_acctest(model, ps, st, dev)
            end

            GC.gc(true)

            if test_reactant(mode)
                set_reactant_backend!(mode)

                rdev = reactant_device(; force=true)

                ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

                @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol =
                    1e-3 rtol = 1e-3
            end
        end
    end
end

@testitem "SqueezeNet" setup = [SharedTestSetup, PretrainedWeightsTestSetup] tags = [
    :vision_metalhead
] begin
    using Metalhead: Metalhead

    for (mode, aType, dev) in MODES
        @testset for pretrained in [false, true]
            model = Vision.SqueezeNet(; pretrained)
            ps, st = dev(Lux.setup(Random.default_rng(), model))
            st = Lux.testmode(st)
            img = aType(randn(Float32, 224, 224, 3, 2))

            @test size(first(model(img, ps, st))) == (1000, 2)

            if pretrained
                @test imagenet_acctest(model, ps, st, dev)
            end

            GC.gc(true)

            if test_reactant(mode)
                set_reactant_backend!(mode)

                rdev = reactant_device(; force=true)

                ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

                @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol =
                    1e-3 rtol = 1e-3

                if pretrained
                    @test imagenet_acctest(model, ps, st, rdev)
                end
            end
        end
    end
end

@testitem "VGG" setup = [SharedTestSetup, PretrainedWeightsTestSetup] tags = [:vision] begin
    for (mode, aType, dev) in MODES, depth in [11, 13, 16, 19]
        @testset for pretrained in [false, true], batchnorm in [false, true]
            model = Vision.VGG(depth; batchnorm, pretrained)
            ps, st = dev(Lux.setup(Random.default_rng(), model))
            st = Lux.testmode(st)
            img = aType(randn(Float32, 224, 224, 3, 2))

            @test size(first(model(img, ps, st))) == (1000, 2)

            if pretrained
                @test imagenet_acctest(model, ps, st, dev)
            end

            GC.gc(true)

            if test_reactant(mode)
                set_reactant_backend!(mode)

                rdev = reactant_device(; force=true)

                ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

                @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol =
                    1e-3 rtol = 1e-3

                if pretrained
                    @test imagenet_acctest(model, ps, st, rdev)
                end
            end
        end
    end
end

@testitem "EfficientNet" setup = [SharedTestSetup, PretrainedWeightsTestSetup] tags = [
    :vision
] begin
    all_names = if parse(Bool, get(ENV, "CI", "false"))
        [:b0, :b1, :b2]
    else
        [:b0, :b1, :b2, :b3, :b4, :b5, :b6, :b7]
    end
    for (mode, aType, dev) in MODES, name in all_names
        @testset for pretrained in [false, true]
            model = Boltz.Vision.EfficientNet(name; pretrained)
            ps, st = Lux.setup(Random.default_rng(), model) |> dev
            st = Lux.testmode(st)
            img = randn(Float32, 224, 224, 3, 2) |> aType

            @test size(first(model(img, ps, st))) == (1000, 2)

            if pretrained
                @test imagenet_acctest(model, ps, st, dev)
            end

            GC.gc(true)

            if test_reactant(mode)
                set_reactant_backend!(mode)

                rdev = reactant_device(; force=true)

                ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

                @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol =
                    1e-3 rtol = 1e-3

                if pretrained
                    @test imagenet_acctest(model, ps, st, rdev)
                end
            end
        end
    end
end

@testitem "VisionTransformer" setup = [SharedTestSetup] tags = [:vision] begin
    all_names = if parse(Bool, get(ENV, "CI", "false"))
        [:tiny, :small, :base]
    else
        [:tiny, :small, :base, :large, :huge, :giant, :gigantic]
    end

    for (mode, aType, dev) in MODES, name in all_names
        model = Vision.VisionTransformer(name; pretrained=false)
        ps, st = dev(Lux.setup(Random.default_rng(), model))
        st = Lux.testmode(st)
        img = aType(randn(Float32, 256, 256, 3, 2))

        @test size(first(model(img, ps, st))) == (1000, 2)

        model = Vision.VisionTransformer(name; pretrained=false)
        ps, st = dev(Lux.setup(Random.default_rng(), model))
        st = Lux.testmode(st)
        img = aType(randn(Float32, 256, 256, 3, 2))

        @test size(first(model(img, ps, st))) == (1000, 2)

        GC.gc(true)

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            ps_ra, st_ra, img_ra = rdev(cpu_device()((ps, st, img)))

            @test @jit(model(img_ra, ps_ra, st_ra))[1] ≈ model(img, ps, st)[1] atol = 1e-3 rtol =
                1e-3
        end
    end
end
