if !isdefined(:infogap_jump_polinomial)
	include(joinpath(Pkg.dir("Mads"), "src-new", "MadsInfoGap.jl"))
end

min, max = infogap_jump_polinomial(model=1, horizons=[0.1, 0.2, 0.5], retries=1, maxiter=1000, verbosity=0, seed=2015)