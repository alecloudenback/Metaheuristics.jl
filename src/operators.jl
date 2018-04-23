function Selection(Old::xf_indiv, New::xf_indiv, searchType::Symbol=:minimize; leq::Bool=false)
    if searchType == :minimize
        if leq
            return New.f <= Old.f
        end

        return New.f < Old.f
    end
    
    if leq
        return New.f >= Old.f
    end
    
    return New.f > Old.f
end

# Deb rules (selection)
function Selection(Old::xfgh_indiv, New::xfgh_indiv, searchType::Symbol=:minimize; leq::Bool=false)

    old_vio = countViolations(Old.g, Old.h)
    new_vio = countViolations(New.g, New.h)

    if new_vio < old_vio 
        return true
    elseif new_vio > old_vio 
        return false
    end

    if searchType == :minimize
        if leq
            return New.f <= Old.f
        end
        return New.f < Old.f
    end
    
    if leq
        return New.f >= Old.f
    end
    
    return New.f > Old.f
end

# Deb rules (selection)
function Selection(Old::xfg_indiv, New::xfg_indiv, searchType::Symbol=:minimize; leq::Bool=false)
    old_vio = countViolations(Old.g, [])
    new_vio = countViolations(New.g, [])

    if new_vio < old_vio 
        return true
    elseif new_vio > old_vio 
        return false
    end

    if searchType == :minimize
        if leq
            return New.f <= Old.f
        end
        return New.f < Old.f
    end
    if leq
        return New.f >= Old.f
    end
    
    return New.f > Old.f
end

function getBest(Population, searchType::Symbol = :minimize)
    best = Population[1]

    for i = 2:length(Population)
        if Selection(best, Population[i])
            best = Population[i]
        end
    end

    return best
end

function getBestInd(Population, searchType::Symbol = :minimize)
    j = 1

    for i = 2:length(Population)
        if Selection(Population[j], Population[i])
            j = i
        end
    end

    return j
end

function generateChild(x::Vector{Float64}, fResult::Float64)
    return xf_indiv(x, fResult)
end

function generateChild(x::Vector{Float64}, fResult::Tuple{Float64,Array{Float64,1}})
    f, g = fResult
    return xfg_indiv(x, f, g)
end

function generateChild(x::Vector{Float64}, fResult::Tuple{Float64,Array{Float64,1},Array{Float64,1}})
    f, g, h = fResult
    return xfgh_indiv(x, f, g, h)
end

function inferType(fVal::Tuple{Float64})
    return xf_indiv
end

function inferType(fVal::Tuple{Float64,Array{Float64,1}})
    return xfg_indiv
end

function inferType(fVal::Tuple{Float64,Array{Float64,1},Array{Float64,1}})
    return xfgh_indiv
end