mutable struct MOEAD_DE
    D::Int
    nobjectives::Int
    N::Int
    F::Float64
    CR::Float64
    λ::Array{Vector{Float64}}
    η::Float64
    p_m::Float64
    H::Int
    T::Int
    δ::Float64
    n_r::Float64
    z::Vector{Float64}
    B::Array{Vector{Int}}
    s1::Float64
end

"""
    MOEAD_DE(D::Int, nobjectives::Int)

`MOEAD_DE` implements the original version of MOEA/D-DE. It uses the contraint handling method
based on the sum of violations (for constrained optimizaton):
`g(x, λ, z) = max(λ .* abs.(fx - z)) + sum(max.(0, gx)) + sum(abs.(hx))`

To use MOEAD_DE, the output from the objective function should be a 3-touple
`(f::Vector, g::Vector, h::Vector)`, where `f` contains the objective functions,
`g` and `h` are the equality and inequality constraints respectively.

A feasible solution is such that g_i(x) ≤ 0 and h_j(x) = 0.

# Example

Assume you want to solve the following optimizaton problem:

Minimize:

f(x) = (x_1, x_2)

subject to:

g(x) = x_1^2 + x_2^2 - 1 ≤ 0

x_1, x_2 ∈ [-1, 1]

A solution can be:

```julia

# Dimension
D = 2

# Objective function
f(x) = ( x, [sum(x.^2) - 1], [0.0] ) 

# bounds
bounds = [-1 -1;
           1  1.0
        ]

# define the parameters
moead_de = MOEAD_DE(D, 2, N = 300, options=Options(debug=false, iterations = 500))

# optimize
status_moead = optimize(f, bounds, moead_de)

# show results
display(status_moead)
```
"""
function MOEAD_DE(D, nobjectives;
    N::Int = 0,
    F = 0.5,
    CR = 1.0,
    λ = Array{Vector{Float64}}[],
    η = 20,
    p_m = 1.0 / D,
    H = 299,
    T = 20,
    δ = 0.9,
    n_r = 2,
    z::Vector{Float64} = fill(Inf, nobjectives),
    B = Array{Int}[],
    s1 = 0.5,
    information = Information(),
    options = Options(),
)


    parameters = MOEAD_DE(D, nobjectives, N, promote(F, CR)..., λ, η,p_m, H, T, δ, n_r, z, B, s1)

    Algorithm(
        parameters,
        initialize! = initialize_MOEAD_DE!,
        update_state! = update_state_MOEAD_DE!,
        is_better = is_better_MOEAD_DE,
        stop_criteria = stop_criteria_moead_de,
        final_stage! = final_stage_MOEAD_DE!,
        information = information,
        options = options,
    )

end

function initialize_weight_vectors!(parameters, problem)
    values = (0:parameters.H) ./ parameters.H

    parameters.λ =  [rand(values, parameters.nobjectives) for i in 1:parameters.N]
end

function initialize_closest_weight_vectors!(parameters, problem)
    distances = zeros(parameters.N, parameters.N)
    λ = parameters.λ
    for i in 1:parameters.N
        for j in (i+1):parameters.N
            distances[i, j] = norm(λ[i] - λ[j])
            distances[j, i] = distances[i, j]
        end
        I = sortperm(distances[i, :])
        push!(parameters.B, I[2:parameters.T+1])
    end
end

function update_reference_point!(z::Vector{Float64}, F::Vector{Float64})
    for i in 1:length(z)
        if z[i] > F[i]
            z[i] = F[i]
        end
    end
end

function update_reference_point!(z::Vector{Float64}, sol::xFgh_indiv)
    update_reference_point!(z, sol.f)
end

function update_reference_point!(z::Vector{Float64}, population)
    for sol in population
        update_reference_point!(z, sol)
    end
end

@inline g(fx, λ, z) = maximum(λ .* abs.(fx - z))

function initialize_MOEAD_DE!(
    problem,
    engine,
    parameters,
    status,
    information,
    options,
)
    D = size(problem.bounds, 2)
    initialize_weight_vectors!(parameters, problem)
    initialize_closest_weight_vectors!(parameters, problem)


    initialize!(problem, engine, parameters, status, information, options)
    update_reference_point!(parameters.z, status.population)

end


function update_state_MOEAD_DE!(
    problem,
    engine,
    parameters,
    status,
    information,
    options,
    iteration,
)




    F = parameters.F
    CR = parameters.CR

    D = size(problem.bounds, 2)


    N = parameters.N

    la = problem.bounds[1, :]
    lb = problem.bounds[2, :]

    D = length(la)
    population = status.population

    for i = 1:N
        if rand() < parameters.δ
            P_idx = copy(parameters.B[i])
        else
            P_idx = collect(1:N)
        end

        # select participats
        r1 = rand(P_idx)
        while r1 == i
            r1 = rand(P_idx)
        end

        r2 = rand(P_idx)
        while r2 == i || r1 == r2
            r2 = rand(P_idx)
        end

        r3 = rand(P_idx)
        while r3 == i || r3 == r1 || r3 == r2
            r3 = rand(P_idx)
        end

        x = population[i].x
        a = population[r1].x
        b = population[r2].x
        c = population[r3].x


        # binomial crossover
        v = zeros(D)
        j_rand = rand(1:D)

        # binomial crossover
        for j = 1:D
            # binomial crossover
            if rand() < CR
                v[j] = a[j] + F * (b[j] - c[j])
            else
                v[j] = a[j]
            end
            # polynomial mutation

            if rand() < parameters.p_m
                r = rand()
                if r < 0.5
                    σ_k = (2.0 * r)^(1.0 / (parameters.η + 1)) - 1
                else
                    σ_k = 1 - (2.0 - 2.0 * r)^(1.0 / (parameters.η + 1))
                end
                v[j] = v[j] + σ_k * (lb[j] - la[j])
            end
        end

        v = correctSol(v, la, lb)

        # instance child
        h = generateChild(v, problem.f(v))
        status.f_calls += 1

        update_reference_point!(parameters.z, h)


        c = 0

        z = parameters.z
        shuffle!(P_idx)
        while c < parameters.n_r && !isempty(P_idx)
            j = pop!(P_idx)
            g1 = g(h.f, parameters.λ[j], z)
            g2 = g(population[j].f, parameters.λ[j], z)
            if is_better_constrained_MOEAD_DE(g1, g2, h, population[j], parameters)
                population[j] = h
                c += 1
            end

        end

        status.stop = engine.stop_criteria(status, information, options)
        if status.stop
            break
        end
    end




end

function is_better_constrained_MOEAD_DE(g1, g2, sol1, sol2, parameters)
    s1 = parameters.s1
    return g1 + s1*sol1.sum_violations <= g2 + s1*sol2.sum_violations
end

function is_better_MOEAD_DE(a, b)
    is_better_eca(a, b)
end

function stop_criteria_moead_de(status, information, options)
    return status.iteration > options.iterations
end
function final_stage_MOEAD_DE!(status, information, options)
    # status.best_sol = get_pareto_front(status.population, is_better_eca)
    # @show length(status.best_sol)
    status.final_time = time()
end