# Based on:
# Li, Zhenhua, and Qingfu Zhang. 
# "An efficient rank-1 update for Cholesky CMA-ES using auxiliary evolution path." 
# Evolutionary Computation (CEC), 2017 IEEE Congress on. IEEE, 2017.

function mvnorm(D)
	return rand(MvNormal(zeros(D), eye(D)))
end

function CMAES_AEP(fobj::Function,
                      D::Int;
              max_evals::Int = 10000D, 
            showResults::Bool = true,
               saveLast::String = "",
        saveConvergence::String = "",
                   limits = [-100.0, 100.0])

	# algorithm parameters
	λ = 4 + floor(Int, 3log(D))
	μ = div(λ, 2)
	w = (log(μ+1) .- log.(1:μ)) ./ (μ*log(μ+1) - sum( log.(1:μ) ))
	μw = 1 / sum( w .^ 2 )
	cσ = √(μw) / ( √(D) + √(μw))
	dσ = 1 + 2max(0, √((μw - 1) / (D+1)) - 1) + cσ
	cc = 4 / (D + 4)
	c1 = 2 / ( D + √(2) )^2


	ENN= √(D)*(1-1/(4*D)+1/(21*D^2))

	# Limits
	VarMin, VarMax = limits[1,:], limits[2,:]
	if length(VarMin) < D
		VarMin = ones(D) * VarMin[1]
		VarMax = ones(D) * VarMax[1]
	end

	σ = (VarMax[1] - VarMin[1])/3

	# Auxiliary Evolution Path
	P = zeros(D)
	Pσ= zeros(D)
	V = zeros(D)

	# initialize M
	x = VarMin + (VarMax - VarMin) .* rand(D)
	f = fobj(x)
	M = generateChild(x, f)
	sample = typeof(M)
	A = eye(D)

	# current number of evaluations
	nevals = 1

	# best solution
	bestSol = M

	# convergence values
	convergence = []
	if saveConvergence != "" && isfeasible(bestSol)
		push!(convergence, [nevals bestSol.f])
	end

	# stop condition
	stop = false

	t = 1
	while !stop

		# Generate Samples
		Population = Array{sample}([])
		fVals = zeros(λ)
		ys = []
		zs = []
		for i=1:λ
			z = mvnorm(D)
			y = A*z
			x = M.x + σ * y
			x = correctSol(x, VarMin, VarMax)

			nevals += 1

			sol = generateChild(x, fobj(x))
			fVals[i] = sol.f

			push!(ys, y)
			push!(zs, z)
			
			push!(Population, sol)

			# Update best solution
			if Selection(bestSol, sol)
				bestSol = sol
			end
		end

		if saveConvergence != "" && isfeasible(bestSol)
			push!(convergence, [nevals bestSol.f])
		end

		stop = nevals >= max_evals

		if stop
			break
		end

		# Population = Population[sortperm(fVals)]

		x   = zeros(D)
		y_w = zeros(D)
		z_w = zeros(D)

		Indx = sortperm(Population, lt=is_better)
		for i = 1:μ
			x += w[i] * Population[Indx[i]].x
			y_w += w[i] * ys[Indx[i]]
			z_w += w[i] * zs[Indx[i]]
		end

		M = generateChild(x, 0.0)

		# update paths
		P = (1- cc)*P + √(cc*( 2 - cc )*μw) * y_w
		V = (1- cc)*V + √(cc*( 2 - cc )*μw) * z_w

		norm_v = dot(V, V)
		b = √(1-c1) / norm_v
		b*= √( 1 + norm_v * c1/(1-c1)) - 1

		A = √(1-c1) * A + b*P * V'

		Pσ = (1-cσ)*Pσ + √(cσ * (2-cσ) *μw )*z_w

		σ *= exp( (cσ/dσ)* (norm(Pσ) / ENN - 1) )
		t += 1
	end

	if saveConvergence != ""
		writecsv(saveConvergence, convergence)
	end

	if saveLast != ""
		writecsv(saveLast, M.x)        
	end

	if showResults
		println("===========[CMAES results]=============")
		printResults(bestSol, [], t, nevals)
		println("=======================================")
	end

	return bestSol.x, bestSol.f

end