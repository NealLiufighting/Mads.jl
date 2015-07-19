# sse(x) gives the L2 norm of x
sse(x) = (x'*x)[1]

function makelmfunctions(madsdata)
	f = makemadscommandfunction(madsdata)
	g = makemadscommandgradient(madsdata, f)
	#f, g = makemadscommandfunctionandgradient(madsdata)
	obskeys = getobskeys(madsdata)
	paramkeys = getparamkeys(madsdata)
	function f_lm(arrayparameters::Vector)
		parameters = Dict(paramkeys, arrayparameters)
		resultdict = f(parameters)
		residuals = Array(Float64, length(madsdata["Observations"]))
		i = 1
		for obskey in obskeys
			diff = resultdict[obskey] - madsdata["Observations"][obskey]["target"]
			residuals[i] = diff * sqrt(madsdata["Observations"][obskey]["weight"])
			i += 1
		end
		return residuals
	end
	function g_lm(arrayparameters::Vector)
		parameters = Dict(paramkeys, arrayparameters)
		gradientdict = g(parameters)
		jacobian = Array(Float64, (length(obskeys), length(paramkeys)))
		for i in 1:length(obskeys)
			for j in 1:length(paramkeys)
				jacobian[i, j] = gradientdict[obskeys[i]][paramkeys[j]]
			end
		end
		return jacobian
	end
	return f_lm, g_lm
end

function levenberg_marquardt(f::Function, g::Function, x0; tolX=1e-3, tolG=1e-6, maxIter=100, lambda=100.0, lambda_mu=10.0, np_lambda=10, show_trace=false)
	println("np_lambda $np_lambda")
	# finds argmin sum(f(x).^2) using the Levenberg-Marquardt algorithm
	#          x
	# The function f should take an input vector of length n and return an output vector of length m
	# The function g is the Jacobian of f, and should be an m x n matrix
	# x0 is an initial guess for the solution
	# fargs is a tuple of additional arguments to pass to f
	# available options:
	#   tolX - search tolerance in x
	#   tolG - search tolerance in gradient
	#   maxIter - maximum number of iterations
	#   lambda - (inverse of) initial trust region radius
	#   lambda_mu - lambda multiplication factor
	#   np_lambda - number of parallel lambdas to test
	#   show_trace - print a status summary on each iteration if true
	# returns: x, J
	#   x - least squares solution for x
	#   J - estimate of the Jacobian of f at x

	# other constants
	const MAX_LAMBDA = 1e16 # minimum trust region radius
	const MIN_LAMBDA = 1e-16 # maximum trust region radius
	const MIN_STEP_QUALITY = 1e-3
	const MIN_DIAGONAL = 1e-6 # lower bound on values of diagonal matrix used to regularize the trust region step

	converged = false
	x_converged = false
	g_converged = false
	need_jacobian = true
	iterCt = 0
	x = x0
	delta_x = copy(x0)
	f_calls = 0
	g_calls = 0
	if np_lambda > 1
		madsoutput("""Parallel lambda search; number of parallel lambdas = $np_lambda\n"""; level = 1)
	end

	fcur = f(x) # TODO execute the initial estimate in parallel with the first jacobian
	f_calls += 1
	best_residual = residual = sse(fcur)
	madsoutput("""Initial OF: $residual\n"""; level = 1)

	# Maintain a trace of the system.
	tr = Optim.OptimizationTrace()
	if show_trace
		d = {"lambda" => lambda}
		os = Optim.OptimizationState(iterCt, sse(fcur), NaN, d)
		push!(tr, os)
		println(os)
	end

	delta_xp = Array(Float64, (np_lambda, length(x)))
	trial_fp = Array(Float64, (np_lambda, length(fcur)))
	lambda_p = Array(Float64, np_lambda)
	phi = Array(Float64, np_lambda)
	while ( ~converged && iterCt < maxIter )
		if need_jacobian
			#println("Jacobian time:")
			#@time J = g(x) # TODO compute this in parallel
			J = g(x) # TODO compute this in parallel
			g_calls += 1
			need_jacobian = false
			madsoutput("Jacobian #$g_calls\n"; level = 1)
		end
		madsoutput("""Current Best OF: $best_residual\n"""; level = 1)
		# we want to solve:
		#    argmin 0.5*||J(x)*delta_x + f(x)||^2 + lambda*||diagm(J'*J)*delta_x||^2
		# Solving for the minimum gives:
		#    (J'*J + lambda*DtD) * delta_x == -J^T * f(x), where DtD = diagm(sum(J.^2,1))
		# Where we have used the equivalence: diagm(J'*J) = diagm(sum(J.^2, 1))
		# It is additionally useful to bound the elements of DtD below to help prevent "parameter evaporation".
		DtD = diagm( Float64[max(x, MIN_DIAGONAL) for x in sum( J.^2, 1 )] )
		lambda_current = lambda_down = lambda_up = lambda
		JpJ = J' * J
		for npl = 1:np_lambda
			if npl == 1 # first
				lambda_current = lambda_p[npl] = lambda
			elseif npl % 2 == 0 # even up
				lambda_up *= lambda_mu
				lambda_current = lambda_p[npl] = lambda_up
			else # odd down
				lambda_down /= lambda_mu
				lambda_current = lambda_p[npl] = lambda_down
			end
			madsoutput(@sprintf "#%02d lambda: %e\n" npl lambda_current; level = 2)
			print("Solve time: ")
			@time delta_x = delta_xp[npl,:] = ( JpJ + sqrt(lambda_current) * DtD ) \ -J' * fcur # TODO replace with SVD
			#delta_x = delta_xp[npl,:] = ( J' * J + sqrt(lambda_current) * DtD ) \ -J' * fcur # TODO replace with SVD
			# if the linear assumption is valid, our new residual should be:
			predicted_residual = phi[npl] = sse(J * delta_x + fcur)
			# check for numerical problems in solving for delta_x by ensuring that the predicted residual is smaller than the current residual
			madsoutput(@sprintf "OF predicted: %e" predicted_residual; level = 2)
			if predicted_residual > residual + 2max( eps(predicted_residual), eps(residual) )
				madsoutput(" -> not good"; level = 2)
				if np_lambda == 1
					madsoutput("""Problem solving for delta_x: predicted residual increase. $predicted_residual (predicted_residual) > $residual (residual) + $(eps(predicted_residual)) (eps)"""; level = 3)
				end
			else
				madsoutput(" -> ok"; level = 2)
			end
		end

		for npl = 1:np_lambda # TODO execute this in parallel
			delta_x = vec(delta_xp[npl,:])
			madsoutput("""# $npl lambda: Parameter change: $delta_x\n"""; level = 3 )
			trial_f = trial_fp[npl,:] = f(x + delta_x) # TODO pmap equivalent of func_set in MADS
			f_calls += 1
			residual = sse(trial_f)
			madsoutput(@sprintf "#%02d lambda: %e OF: %e (predicted %e)\n" npl lambda_p[npl] residual phi[npl]; level = 2 )
			phi[npl] = residual
		end

		npl_best = indmin(phi)
		npl_worst = indmax(phi)
		madsoutput(@sprintf "OF     range in the parallel lambda search: min  %e max   %e\n" phi[npl_best] phi[npl_worst]; level = 1 )
		madsoutput(@sprintf "Lambda range in the parallel lambda search: best %e worst %e\n" lambda_p[npl_best] lambda_p[npl_worst]; level = 1 )
		lambda = lambda_p[npl_best]
		delta_x = vec(delta_xp[npl_best,:])
		trial_f = vec(trial_fp[npl_best,:])
		trial_residual = phi[npl_best]
		predicted_residual = sse(J * delta_x + fcur)

		# step quality = residual change / predicted residual change
		rho = (trial_residual - residual) / (predicted_residual - residual)
		if rho > MIN_STEP_QUALITY # accept the new lambda
			x += delta_x
			fcur = trial_f
			residual = trial_residual
			# increase trust region radius
			lambda = max(lambda/lambda_mu, MIN_LAMBDA)
			need_jacobian = true
		else # reject the new lambda
			# decrease trust region radius
			lambda = min(lambda_mu*lambda, MAX_LAMBDA)
		end
		if best_residual > residual # check for BEST OF
			x_best = x
			f_best = fcur
			best_residual = residual
		else
			madsoutput("Lambda search did not improve the OF\n"; level = 1 )
		end
		iterCt += 1

		# show state
		if show_trace
			gradnorm = norm(J'*fcur, Inf)
			d = {"g(x)" => gradnorm, "dx" => delta_x, "lambda" => lambda}
			os = Optim.OptimizationState(iterCt, sse(fcur), gradnorm, d)
			push!(tr, os)
			println(os)
		end

		# check convergence criteria:
		# 1. Small gradient: norm(J^T * fcur, Inf) < tolG
		# 2. Small step size: norm(delta_x) < tolX
		if norm(J' * fcur, Inf) < tolG
			g_converged = true
		end
		if norm(delta_x) < tolX*(tolX + norm(x))
			x_converged = true
		end
		converged = g_converged | x_converged
	end
	Optim.MultivariateOptimizationResults("Levenberg-Marquardt", x0, x, sse(fcur), iterCt, !converged, x_converged, 0.0, false, 0.0, g_converged, tolG, tr, f_calls, g_calls)
end