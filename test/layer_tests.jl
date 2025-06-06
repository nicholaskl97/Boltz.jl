# Only tests that are not run via `vision` or other higher-level test suites are
# included in this snippet.
@testitem "MLP" setup = [SharedTestSetup] tags = [:layers] begin
    @testset "$(mode)" for (mode, aType, dev) in MODES
        @testset "$(act)" for act in (tanh,)
            @testset "$(nType)" for nType in (BatchNorm,)
                norm = if nType === nothing
                    nType
                elseif nType === BatchNorm
                    (i, ch, act; kwargs...) -> BatchNorm(ch, act; kwargs...)
                elseif nType === GroupNorm
                    (i, ch, act; kwargs...) -> GroupNorm(ch, 2, act; kwargs...)
                end

                model = Layers.MLP(2, (4, 4, 2), act; norm_layer=norm)
                ps, st = Lux.setup(StableRNG(0), model) |> dev
                st_test = Lux.testmode(st)

                x = randn(Float32, 2, 2) |> aType

                __f = (x, ps) -> sum(abs2, first(model(x, ps, st)))
                @test_gradients(
                    __f,
                    x,
                    ps;
                    atol=1e-3,
                    rtol=1e-3,
                    soft_fail=[AutoFiniteDiff()],
                    enzyme_set_runtime_activity=true
                )

                if test_reactant(mode)
                    set_reactant_backend!(mode)
                    rdev = reactant_device(; force=true)

                    ps_ra, st_ra, x_ra = rdev((ps, st, x))
                    st_ra_test = Lux.testmode(st_ra)

                    @test @jit(model(x_ra, ps_ra, st_ra_test))[1] ≈ model(x, ps, st_test)[1] atol =
                        1e-3 rtol = 1e-3

                    ∂x_ra, ∂ps_ra =
                        @jit(compute_reactant_gradient(model, x_ra, ps_ra, st_ra)) |>
                        cpu_device()
                    ∂x_zyg, ∂ps_zyg =
                        compute_zygote_gradient(model, x, ps, st) |> cpu_device()
                    @test check_approx(∂x_ra, ∂x_zyg; atol=1e-3, rtol=1e-3)
                    @test check_approx(∂ps_ra, ∂ps_zyg; atol=1e-3, rtol=1e-3)
                end
            end
        end
    end
end

@testitem "Hamiltonian Neural Network" setup = [SharedTestSetup] tags = [:layers] begin
    using ComponentArrays, ForwardDiff, Zygote, MLDataDevices, NNlib

    _remove_nothing(xs) = map(x -> x === nothing ? 0 : x, xs)

    @testset "$(mode): $(autodiff)" for (mode, aType, dev) in MODES,
        autodiff in (nothing, AutoZygote(), AutoForwardDiff())

        dev isa MLDataDevices.AbstractGPUDevice &&
            autodiff === AutoForwardDiff() &&
            continue

        hnn = Layers.HamiltonianNN{true}(Layers.MLP(2, (4, 4, 2), NNlib.gelu); autodiff)
        ps, st = dev(Lux.setup(StableRNG(0), hnn))

        x = aType(randn(Float32, 2, 4))

        @test_throws ArgumentError hnn(x, ps, st)

        hnn = Layers.HamiltonianNN{true}(Layers.MLP(2, (4, 4, 1), NNlib.gelu); autodiff)
        ps, st = dev(Lux.setup(StableRNG(0), hnn))
        ps_ca = dev(ComponentArray(cpu_device()(ps)))

        @test st.first_call
        y, st = hnn(x, ps, st)
        @test !st.first_call

        ∂x_zyg, ∂ps_zyg = Zygote.gradient(
            (x, ps) -> sum(abs2, first(hnn(x, ps, st))), x, ps
        )
        @test ∂x_zyg !== nothing
        @test ∂ps_zyg !== nothing
        if !(dev isa MLDataDevices.AbstractGPUDevice)
            ∂ps_zyg = _remove_nothing(getdata(dev(ComponentArray(cpu_device()(∂ps_zyg)))))
            ∂x_fd = ForwardDiff.gradient(x -> sum(abs2, first(hnn(x, ps, st))), x)
            ∂ps_fd = getdata(
                ForwardDiff.gradient(ps -> sum(abs2, first(hnn(x, ps, st))), ps_ca)
            )

            @test ∂x_zyg ≈ ∂x_fd atol = 1e-3 rtol = 1e-3
            @test ∂ps_zyg ≈ ∂ps_fd atol = 1e-3 rtol = 1e-3
        end

        st = Lux.initialstates(StableRNG(0), hnn) |> dev
        st_test = Lux.testmode(st)

        @test st.first_call
        y, st = hnn(x, ps_ca, st)
        @test !st.first_call

        ∂x_zyg, ∂ps_zyg = Zygote.gradient(
            (x, ps) -> sum(abs2, first(hnn(x, ps, st))), x, ps_ca
        )
        @test ∂x_zyg !== nothing
        @test ∂ps_zyg !== nothing
        if !(dev isa MLDataDevices.AbstractGPUDevice)
            ∂ps_zyg = _remove_nothing(getdata(dev(ComponentArray(cpu_device()(∂ps_zyg)))))
            ∂x_fd = ForwardDiff.gradient(x -> sum(abs2, first(hnn(x, ps_ca, st))), x)
            ∂ps_fd = getdata(
                ForwardDiff.gradient(ps -> sum(abs2, first(hnn(x, ps, st))), ps_ca)
            )

            @test ∂x_zyg ≈ ∂x_fd atol = 1e-3 rtol = 1e-3
            @test ∂ps_zyg ≈ ∂ps_fd atol = 1e-3 rtol = 1e-3
        end

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            ps_ra, st_ra, x_ra = rdev((ps, st, x))
            st_ra_test = Lux.testmode(st_ra)

            @test @jit(hnn(x_ra, ps_ra, st_ra_test))[1] ≈ hnn(x, ps, st_test)[1] atol = 1e-3 rtol =
                1e-3

            ∂x_ra, ∂ps_ra =
                @jit(compute_reactant_gradient(hnn, x_ra, ps_ra, st_ra)) |> cpu_device()
            ∂x_zyg, ∂ps_zyg = compute_zygote_gradient(hnn, x, ps, st) |> cpu_device()

            @test check_approx(∂x_ra, ∂x_zyg; atol=1e-3, rtol=1e-3)
            @test check_approx(∂ps_ra, ∂ps_zyg; atol=1e-3, rtol=1e-3)
        end
    end
end

@testitem "Tensor Product Layer" setup = [SharedTestSetup] tags = [:layers] begin
    @testset "$(mode)" for (mode, aType, dev) in MODES
        @testset "$(basis)" for basis in (
            Basis.Chebyshev,
            Basis.Sin,
            Basis.Cos,
            Basis.Fourier,
            Basis.Legendre,
            Basis.Polynomial,
        )
            tensor_project = Layers.TensorProductLayer([basis(n + 2) for n in 1:3], 4)
            ps, st = dev(Lux.setup(StableRNG(0), tensor_project))

            x = aType(tanh.(randn(Float32, 2, 4, 5)))

            @test_throws ArgumentError tensor_project(x, ps, st)

            x = aType(tanh.(randn(Float32, 2, 3, 5)))

            y, st = tensor_project(x, ps, st)
            @test size(y) == (2, 4, 5)

            __f = (x, ps) -> sum(abs2, first(tensor_project(x, ps, st)))
            @test_gradients(
                __f,
                x,
                ps;
                atol=1e-3,
                rtol=1e-3,
                skip_backends=[AutoTracker(), AutoEnzyme(), AutoReverseDiff()]
            )

            if test_reactant(mode)
                set_reactant_backend!(mode)

                # XXX: Currently causes some issues with tracing
                basis == Basis.Legendre && continue

                rdev = reactant_device(; force=true)

                x_ra = rdev(x)
                ps_ra, st_ra = rdev((ps, st))
                st_ra_test = Lux.testmode(st_ra)

                @test @jit(tensor_project(x_ra, ps_ra, st_ra_test))[1] ≈
                    tensor_project(x, ps, st)[1] atol = 1e-3 rtol = 1e-3

                ∂x_ra, ∂ps_ra =
                    @jit(compute_reactant_gradient(tensor_project, x_ra, ps_ra, st_ra)) |>
                    cpu_device()
                ∂x_zyg, ∂ps_zyg =
                    compute_zygote_gradient(tensor_project, x, ps, st) |> cpu_device()

                @test check_approx(∂x_ra, ∂x_zyg; atol=1e-3, rtol=1e-3)
                @test check_approx(∂ps_ra, ∂ps_zyg; atol=1e-3, rtol=1e-3)
            end
        end
    end
end

@testitem "Basis Functions" setup = [SharedTestSetup] tags = [:layers] begin
    @testset "$(mode)" for (mode, aType, dev) in MODES
        @testset "$(basis)" for basis in (
            Basis.Chebyshev,
            Basis.Sin,
            Basis.Cos,
            Basis.Fourier,
            Basis.Legendre,
            Basis.Polynomial,
        )
            x = aType(tanh.(randn(Float32, 2, 4)))
            grid = aType(collect(1:3))

            fn1 = basis(3)
            @test size(fn1(x)) == (3, 2, 4)
            @test size(fn1(x, grid)) == (3, 2, 4)

            fn2 = basis(3; dim=2)
            @test size(fn2(x)) == (2, 3, 4)
            @test size(fn2(x, grid)) == (2, 3, 4)

            fn3 = basis(3; dim=3)
            @test size(fn3(x)) == (2, 4, 3)
            @test size(fn3(x, grid)) == (2, 4, 3)

            fn4 = basis(3; dim=4)
            @test_throws ArgumentError fn4(x)

            grid2 = aType(1:5)
            @test_throws ArgumentError fn4(x, grid2)

            if test_reactant(mode)
                set_reactant_backend!(mode)

                # XXX: Currently causes some issues with tracing
                basis == Basis.Legendre && continue

                rdev = reactant_device(; force=true)

                x_ra = rdev(x)
                grid_ra = rdev(grid)

                @test @jit(fn1(x_ra)) ≈ fn1(x) atol = 1e-3 rtol = 1e-3
                @test @jit(fn1(x_ra, grid_ra)) ≈ fn1(x, grid) atol = 1e-3 rtol = 1e-3

                @test @jit(fn2(x_ra)) ≈ fn2(x) atol = 1e-3 rtol = 1e-3
                @test @jit(fn2(x_ra, grid_ra)) ≈ fn2(x, grid) atol = 1e-3 rtol = 1e-3

                @test @jit(fn3(x_ra)) ≈ fn3(x) atol = 1e-3 rtol = 1e-3
                @test @jit(fn3(x_ra, grid_ra)) ≈ fn3(x, grid) atol = 1e-3 rtol = 1e-3
            end
        end
    end
end

# Unskip once https://github.com/SciML/DataInterpolations.jl/pull/414 lands
@testitem "Spline Layer" setup = [SharedTestSetup] tags = [:integration] skip = true begin
    using ComponentArrays, DataInterpolations, ForwardDiff, Zygote, MLDataDevices

    @testset "$(mode)" for (mode, aType, dev) in MODES
        dev isa MLDataDevices.AbstractGPUDevice && continue

        @testset "$(spl): train_grid $(train_grid), dims $(dims)" for spl in (
                ConstantInterpolation,
                LinearInterpolation,
                QuadraticInterpolation,
                # QuadraticSpline, # XXX: DataInterpolations.jl broke it again!!!
                CubicSpline,
            ),
            train_grid in (true, false),
            dims in ((), (8,))

            spline = Layers.SplineLayer(dims, 0.0f0, 1.0f0, 0.1f0, spl; train_grid)
            ps, st = dev(Lux.setup(StableRNG(0), spline))
            ps_ca = dev(ComponentArray(cpu_device()(ps)))

            x = aType(rand(Float32, 4))

            y, st = spline(x, ps, st)
            @test size(y) == (dims..., 4)

            y, st = spline(x, ps_ca, st)
            @test size(y) == (dims..., 4)

            ∂x, ∂ps = Zygote.gradient((x, ps) -> sum(abs2, first(spline(x, ps, st))), x, ps)
            spl !== ConstantInterpolation && @test ∂x !== nothing
            @test ∂ps !== nothing

            ∂x_fd = ForwardDiff.gradient(x -> sum(abs2, first(spline(x, ps, st))), x)
            ∂ps_fd = ForwardDiff.gradient(ps -> sum(abs2, first(spline(x, ps, st))), ps_ca)

            spl !== ConstantInterpolation && @test ∂x ≈ ∂x_fd atol = 1e-3 rtol = 1e-3

            @test ∂ps.saved_points ≈ ∂ps_fd.saved_points atol = 1e-3 rtol = 1e-3
            if train_grid
                if ∂ps.grid === nothing
                    @test_softfail all(Base.Fix1(isapprox, 0), ∂ps_fd.grid)
                else
                    @test ∂ps.grid ≈ ∂ps_fd.grid atol = 1e-3 rtol = 1e-3
                end
            end
        end
    end
end

@testitem "Periodic Embedding" setup = [SharedTestSetup] tags = [:layers] begin
    @testset "$(mode)" for (mode, aType, dev) in MODES
        layer = Layers.PeriodicEmbedding([2, 3], [4.0, π / 5])
        ps, st = dev(Lux.setup(StableRNG(0), layer))
        x = aType(randn(StableRNG(0), 6, 4, 3, 2))
        Δx = aType([0.0, 12.0, -2π / 5, 0.0, 0.0, 0.0])

        val = Array(layer(x, ps, st)[1])
        shifted_val = Array(layer(x .+ Δx, ps, st)[1])

        @test all(val[1:4, :, :, :] .== shifted_val[1:4, :, :, :]) && all(
            isapprox.(val[5:8, :, :, :], shifted_val[5:8, :, :, :]; atol=5 * eps(Float32))
        )

        __f = x -> sum(first(layer(x, ps, st)))
        @test_gradients(__f, x; atol=1.0f-3, rtol=1.0f-3, enzyme_set_runtime_activity=true)

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            ps_ra, st_ra, x_ra = rdev((ps, st, x))
            st_ra_test = Lux.testmode(st_ra)

            @test @jit(layer(x_ra, ps_ra, st_ra_test))[1] ≈ layer(x, ps, st)[1] atol = 1e-3 rtol =
                1e-3

            ∂x_ra, ∂ps_ra =
                @jit(compute_reactant_gradient(layer, x_ra, ps_ra, st_ra)) |> cpu_device()
            ∂x_zyg, ∂ps_zyg = compute_zygote_gradient(layer, x, ps, st) |> cpu_device()

            @test check_approx(∂x_ra, ∂x_zyg; atol=1e-3, rtol=1e-3)
            @test check_approx(∂ps_ra, ∂ps_zyg; atol=1e-3, rtol=1e-3)
        end
    end
end

# TODO: enable once https://github.com/SymbolicML/DynamicExpressions.jl/pull/119 lands
@testitem "Dynamic Expressions Layer" setup = [SharedTestSetup] tags = [:integration] begin
    using DynamicExpressions, ForwardDiff, ComponentArrays

    operators = OperatorEnum(; binary_operators=[+, -, *], unary_operators=[cos])

    x1 = Node(; feature=1)
    x2 = Node(; feature=2)

    expr_1 = x1 * cos(x2 - 3.2)
    expr_2 = x2 - x1 * x2 + 2.5 - 1.0 * x1

    for exprs in ((expr_1,), (expr_1, expr_2), ([expr_1, expr_2],))
        layer = Layers.DynamicExpressionsLayer(operators, exprs...)
        ps, st = Lux.setup(StableRNG(0), layer)

        x = [
            1.0f0 2.0f0 3.0f0
            4.0f0 5.0f0 6.0f0
        ]

        y, st_ = layer(x, ps, st)
        @test eltype(y) == Float32
        __f = (x, p) -> sum(abs2, first(layer(x, p, st)))
        @test_gradients(__f, x, ps; atol=1.0f-3, rtol=1.0f-3, skip_backends=[AutoEnzyme()])

        # Particular ForwardDiff dispatches
        ps_ca = ComponentArray(ps)
        dps_ca = ForwardDiff.gradient(ps_ca) do ps_
            sum(abs2, first(layer(x, ps_, st)))
        end
        dx = ForwardDiff.gradient(x) do x_
            sum(abs2, first(layer(x_, ps, st)))
        end
        dxps = ForwardDiff.gradient(ComponentArray(; x, ps)) do ca
            sum(abs2, first(layer(ca.x, ca.ps, st)))
        end

        @test dx ≈ dxps.x atol = 1.0f-3 rtol = 1.0f-3
        @test dps_ca ≈ dxps.ps atol = 1.0f-3 rtol = 1.0f-3

        x = Float64.(x)
        y, st_ = layer(x, ps, st)
        @test eltype(y) == Float64
        __f = (x, p) -> sum(abs2, first(layer(x, p, st)))
        @test_gradients(__f, x, ps; atol=1.0e-3, rtol=1.0e-3, skip_backends=[AutoEnzyme()])
    end

    @testset "$(mode)" for (mode, aType, dev) in MODES
        layer = Layers.DynamicExpressionsLayer(operators, expr_1)
        ps, st = dev(Lux.setup(StableRNG(0), layer))

        x = aType([
            1.0f0 2.0f0 3.0f0
            4.0f0 5.0f0 6.0f0
        ])

        if dev isa MLDataDevices.AbstractGPUDevice
            @test_throws ArgumentError layer(x, ps, st)
        end
    end
end

@testitem "Positive Definite Container" setup = [SharedTestSetup] tags = [:layers] begin
    @testset "$(mode)" for (mode, aType, dev) in MODES
        model = Layers.MLP(2, (4, 4, 2), gelu)
        pd = Layers.PositiveDefinite(model; in_dims=2)
        ps, st = dev(Lux.setup(StableRNG(0), pd))

        x = aType(randn(StableRNG(0), Float32, 2, 2))
        x0 = aType(zeros(Float32, 2))

        y, _ = pd(x, ps, st)
        z, _ = model(x, ps, st.model)
        z0, _ = model(x0, ps, st.model)
        y_by_hand = sum(abs2, z .- z0; dims=1) .+ sum(abs2, x .- x0; dims=1)

        @test maximum(abs, y - y_by_hand) < 1.0f-8

        __f = (x, ps) -> sum(first(pd(x, ps, st)))
        broken_backends = if dev isa MLDataDevices.AbstractGPUDevice
            [AutoTracker()]
        else
            [AutoReverseDiff(), AutoEnzyme()]
        end
        @test_gradients(__f, x, ps; atol=1.0f-3, rtol=1.0f-3, broken_backends)

        pd2 = Layers.PositiveDefinite(model, ones(2))
        ps, st = dev(Lux.setup(StableRNG(0), pd2))

        x0 = aType(ones(Float32, 2))
        y, _ = pd2(x0, ps, st)

        @test maximum(abs, y) < 1.0f-8

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            pd = Layers.PositiveDefinite(model; in_dims=2)
            ps, st = dev(Lux.setup(StableRNG(0), pd))
            x = aType(randn(StableRNG(0), Float32, 2, 2))
            ps_ra, st_ra, x_ra = rdev((ps, st, x))
            st_ra_test = Lux.testmode(st_ra)

            @test @jit(pd(x_ra, ps_ra, st_ra_test))[1] ≈ pd(x, ps, st)[1] atol = 1e-3 rtol =
                1e-3

            ∂x_ra, ∂ps_ra =
                @jit(compute_reactant_gradient(pd, x_ra, ps_ra, st_ra)) |> cpu_device()
            ∂x_zyg, ∂ps_zyg = compute_zygote_gradient(pd, x, ps, st) |> cpu_device()

            @test check_approx(∂x_ra, ∂x_zyg; atol=1e-3, rtol=1e-3)
            @test check_approx(∂ps_ra, ∂ps_zyg; atol=1e-3, rtol=1e-3)
        end
    end
end

@testitem "ShiftTo Container" setup = [SharedTestSetup] tags = [:layers] begin
    @testset "$(mode)" for (mode, aType, dev) in MODES
        model = Layers.MLP(2, (4, 4, 2), gelu)
        shiftto = Layers.ShiftTo(model, ones(Float32, 2), zeros(Float32, 2))
        ps, st = Lux.setup(StableRNG(0), shiftto) |> dev

        y0, _ = shiftto(st.in_val, ps, st)
        @test maximum(abs, y0) < 1.0f-8

        x = randn(StableRNG(0), Float32, 2, 2) |> aType

        __f = (x, ps) -> sum(first(shiftto(x, ps, st)))
        broken_backends = if dev isa MLDataDevices.AbstractGPUDevice
            []
        else
            [AutoEnzyme()]
        end
        @test_gradients(__f, x, ps; atol=1.0f-3, rtol=1.0f-3, broken_backends)

        if test_reactant(mode)
            set_reactant_backend!(mode)

            rdev = reactant_device(; force=true)

            ps_ra, st_ra, x_ra = rdev((ps, st, x))
            st_ra_test = Lux.testmode(st_ra)

            @test @jit(shiftto(x_ra, ps_ra, st_ra_test))[1] ≈ shiftto(x, ps, st)[1] atol =
                1e-3 rtol = 1e-3

            ∂x_ra, ∂ps_ra =
                @jit(compute_reactant_gradient(shiftto, x_ra, ps_ra, st_ra)) |> cpu_device()
            ∂x_zyg, ∂ps_zyg = compute_zygote_gradient(shiftto, x, ps, st) |> cpu_device()

            @test check_approx(∂x_ra, ∂x_zyg; atol=1e-3, rtol=1e-3)
            @test check_approx(∂ps_ra, ∂ps_zyg; atol=1e-3, rtol=1e-3)
        end
    end
end
