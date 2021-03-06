# Estimation of finite mixture model using EM

immutable FiniteMixtureEM
	maxiter::Int
	tol::Float64
	display::Symbol
	alpha::Float64
end

function fmm_em(;
	maxiter::Integer=100, 
	tol::Real=1.0e-6, 
	display::Symbol=:none, 
	alpha::Float64=1.0)

	FiniteMixtureEM(maxiter, tol, display, alpha)
end

immutable FiniteMixtureEMResults{C}
	mixture::Mixture{C}
	Q::Matrix{Float64}
	L::Matrix{Float64}
	niters::Int
	converged::Bool
	objective::Float64
end


function fit_fmm!{C<:Distribution}(estimator::Estimator{C}, 
	data, Q::Matrix{Float64}, alg::FiniteMixtureEM)

	# basic numbers

	n = nsamples(estimator, data)
	@check_argdims size(Q, 1) == n

	K = size(Q, 2)
	maxiter = alg.maxiter
	tol = alg.tol
	verbose = verbosity_level(alg.display)

	# prepare storage

	components = Array(C, K)
	L = Array(Float64, n, K)
	E = Array(Float64, n, K)
	pi = Array(Float64, K)
	lpi = Array(Float64, K)
	qent = Array(Float64, n)
	objv = NaN

	# main loop

	t = 0
	converged = false

	if verbose >= VERBOSE_PROC
		@printf("%6s    %12s     %12s\n", "iter", "objective", "obj.change")
		println("------------------------------------------")
	end

	while !converged && t < maxiter
		t = t + 1

		# M-step
		sum!(pi, Q, 1)
		multiply!(pi, inv(n))
		for k in 1 : K
			lpi[k] = log(pi[k])
		end

		for k in 1 : K
			comp::C = estimate(estimator, data, refcolumn(Q, k))
			components[k] = comp
			logpdf!(refcolumn(L, k), comp, data)
		end 

		# E-step
		vbroadcast!(Add(), E, L, lpi, 2)
		softmax!(Q, E, 2)

		# evaluate objective
		t_lpi = sum(Q * lpi)
		t_llik = dot(L, Q)
		t_qent = sum(entropy!(qent, Q, 2))
		t_lpri = 0.
		for k in 1 : K
			t_lpri += prior_score(estimator, components[k])
		end

		objv_pre = objv 
		objv = t_lpi + t_llik + t_qent + t_lpri

		# decide convergence
		converged = t > 1 && abs(objv - objv_pre) < tol

		if verbose >= VERBOSE_ITER
			@printf("%6d    %12.4e     %12.4e\n", t, objv, objv - objv_pre)
		end
	end

	if verbose >= VERBOSE_PROC
		if converged
			println("EM procedure converged with $t iterations.")
		else
			println("EM procedure terminated after $t iterations without convergence.")
		end
	end

	mixture = Mixture(components, pi)
	return FiniteMixtureEMResults{C}(mixture, Q, L, t, converged, objv)
end

function fit_fmm!{C<:Distribution}(dty::Type{C}, data, Q::Matrix{Float64}, alg::FiniteMixtureEM)
	fit_fmm!(MLEstimator(C), data, Q, alg)
end

function fit_fmm{C<:Distribution}(dty::Type{C}, data, K::Int, alg::FiniteMixtureEM)
	n = nsamples(C, data)
	fit_fmm!(MLEstimator(C), data, qmatrix(n, K), alg)
end


