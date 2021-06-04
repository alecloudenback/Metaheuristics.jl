include("weights_and_ideal.jl")

mutable struct MOEAD_DE <: AbstractParameters
    nobjectives::Int
    N::Int
    F::Float64
    CR::Float64
    λ::Array{Vector{Float64}}
    η::Float64
    p_m::Float64
    T::Int
    δ::Float64
    n_r::Float64
    z::Vector{Float64}
    B::Array{Vector{Int}}
    s1::Float64
end

"""
    MOEAD_DE(weights)

`MOEAD_DE` implements the original version of MOEA/D-DE. It uses the contraint handling method
based on the sum of violations (for constrained optimizaton):
`g(x, λ, z) = max(λ .* abs.(fx - z)) + sum(max.(0, gx)) + sum(abs.(hx))`

To use MOEAD_DE, the output from the objective function should be a 3-touple
`(f::Vector, g::Vector, h::Vector)`, where `f` contains the objective functions,
`g` and `h` are the equality and inequality constraints respectively.

A feasible solution is such that `g_i(x) ≤ 0 and h_j(x) = 0`.

Ref. Multiobjective Optimization Problems With Complicated Pareto Sets,
MOEA/D and NSGA-II; Hui Li and Qingfu Zhang.

# Example

Assume you want to solve the following optimizaton problem:

Minimize:

`f(x) = (x_1, x_2)`

subject to:

`g(x) = x_1^2 + x_2^2 - 1 ≤ 0`

`x_1, x_2 ∈ [-1, 1]`

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

nobjectives = 2
npartitions = 100

# reference points (Das and Dennis's method)
weights = gen_ref_dirs(nobjectives, npartitions)

# define the parameters
moead_de = MOEAD_DE(weights, options=Options(debug=false, iterations = 250))

# optimize
status_moead = optimize(f, bounds, moead_de)

# show results
display(status_moead)
```

"""
function MOEAD_DE(weights ;
    F = 0.5,
    CR = 1.0,
    λ = Array{Vector{Float64}}[],
    η = 20,
    p_m = -1.0,
    T = 20,
    δ = 0.9,
    n_r = 2,
    z::Vector{Float64} = zeros(0),
    B = Array{Int}[],
    s1 = 1000.5,
    information = Information(),
    options = Options(),
)


    if isempty(weights)
        error("Provide weights points")
    end



    nobjectives = length(weights[1])
    N = length(weights)

    if isempty(z)
        z = fill(Inf, nobjectives)
    end


    parameters = MOEAD_DE(nobjectives, N, F, CR, weights, η, p_m, T, δ, n_r, z, B, s1)


    initialize_closest_weight_vectors!(parameters)

    alg = Algorithm(
        parameters,
        information = information,
        options = options,
    )



    alg

end

function initialize!(
    status,
    parameters::MOEAD_DE,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
)



    if options.iterations == 0
        options.iterations = 500
    end

    if options.f_calls_limit == 0
        options.f_calls_limit = options.iterations * parameters.N + 1
    end



    status = gen_initial_state(problem,parameters,information,options,status)
    D = size(problem.bounds, 2)
    parameters.nobjectives = length(status.population[1].f)
    parameters.p_m = parameters.p_m < 0.0 ? 1.0 / D : parameters.p_m


    update_reference_point!(parameters.z, status.population)
    return status

end


function update_state!(
    status::State,
    parameters::MOEAD_DE,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
)




    F = parameters.F
    CR = parameters.CR

    D = size(problem.bounds, 2)


    N = parameters.N

    la = problem.bounds[1, :]
    lb = problem.bounds[2, :]

    population = status.population

    for i = 1:N
        if rand() < parameters.δ
            P_idx = copy(parameters.B[i])
        else
            P_idx = collect(1:N)
        end

        # select participats
        r1 = i
        r2 = rand(P_idx)
        while r1 == r2
            r2 = rand(P_idx)
        end

        r3 = rand(P_idx)
        while r3 == r1 || r3 == r2
            r3 = rand(P_idx)
        end

        a = get_position(population[r1])# population[r1].x
        b = get_position(population[r2])# population[r2].x
        c = get_position(population[r3])# population[r3].x


        # binomial crossover
        v = zeros(D)

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

        v = replace_with_random_in_bounds!(v, problem.bounds)

        # instance child
        h = create_solution(v, problem)
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

        stop_criteria!(status, parameters, problem, information, options)
        if status.stop
            break
        end
    end




end

function is_better_constrained_MOEAD_DE(g1, g2, sol1, sol2, parameters)
    # s1 = parameters.s1
    # return g1 + s1*sol1.sum_violations <= g2 + s1*sol2.sum_violations
    if sol2.sum_violations > sol1.sum_violations
        return true
    elseif sol2.sum_violations < sol1.sum_violations
        return false
    end
    return g1 < g2
end


function stop_criteria_moead_de(
    status::State,
    parameters::MOEAD_DE,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
    )
    return status.iteration > options.iterations
end
function final_stage!(
    status::State,
    parameters::MOEAD_DE,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
    )
    status.final_time = time()
    # status.best_sol = get_pareto_front(status.population, is_better_eca)
    # @show length(status.best_sol)
end
