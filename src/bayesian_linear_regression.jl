"""
    BayesianLinearRegressor{Tmw, TΛw}

A Bayesian Linear Regressor is a distribution over linear functions given by
```julia
w ~ Normal(mw, Λw)
f(x) = dot(x, w)
```
where `mw` and `Λ` are the mean and precision of `w` respectively.
"""
struct BayesianLinearRegressor{Tmw<:AbstractVector, TΛw<:AbstractMatrix} <: AbstractGP
    mw::Tmw
    Λw::TΛw
end

const FiniteBLR = FiniteGP{<:BayesianLinearRegressor}

# All code below implements the primary + secondary AbstractGPs.jl APIs.

AbstractGPs.mean(fx::FiniteBLR) = fx.x.X' * fx.f.mw

function AbstractGPs.cov(fx::FiniteBLR)
    α = _cholesky(fx.f.Λw).U' \ fx.x.X
    return Symmetric(α' * α + fx.Σy)
end

function AbstractGPs.var(fx::FiniteBLR)
    α = _cholesky(fx.f.Λw).U' \ fx.x.X
    return vec(sum(abs2, α; dims=1)) .+ diag(fx.Σy)
end

AbstractGPs.mean_and_cov(fx::FiniteBLR) = (mean(fx), cov(fx))

AbstractGPs.mean_and_var(fx::FiniteBLR) = (mean(fx), var(fx))

function AbstractGPs.rand(rng::AbstractRNG, fx::FiniteBLR, samples::Int)
    w = fx.f.mw .+ _cholesky(fx.f.Λw).U \ randn(rng, size(fx.x.X, 1), samples)
    y = fx.x.X' * w .+ _cholesky(fx.Σy).U' * randn(rng, size(fx.x.X, 2), samples)
end

function AbstractGPs.logpdf(fx::FiniteBLR, y::AbstractVector{<:Real})
    _, Bt, δy, logpdf_δy, Λεy = __compute_inference_quantities(fx, y)
    return -(logdet(Λεy) - sum(abs2, Λεy.U' \ (Bt'δy))) / 2 + logpdf_δy
end

function AbstractGPs.posterior(fx::FiniteBLR, y::AbstractVector{<:Real})
    Uw, Bt, δy, _, Λεy = __compute_inference_quantities(fx, y)

    # Compute posterior over decorrelated weights.
    mεy = Λεy \ (Bt'δy)

    # Compute posterior over weights.
    T = Λεy.U * Uw
    return BayesianLinearRegressor(fx.f.mw + Uw \ mεy, Symmetric(T'T))
end

# Computation utilised in both `logpdf` and `posterior`.
function __compute_inference_quantities(fx::FiniteBLR, y::AbstractVector{<:Real})
    length(y) == size(fx.x.X, 2) || throw(error("length(y) != size(fx.x.X, 2)"))
    blr = fx.f
    X = fx.x.X
    N = length(y)

    Uw = _cholesky(blr.Λw).U
    Σy = _cholesky(fx.Σy)

    Bt = Σy.U' \ (Uw' \ X)'
    δy = Σy.U' \ (y - mean(fx))

    logpdf_δy = -(N * log(2π) + logdet(Σy) + sum(abs2, δy)) / 2

    Λεy = _cholesky(Symmetric(Bt'Bt + I))

    return Uw, Bt, δy, logpdf_δy, Λεy
end
