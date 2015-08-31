module Mads

import DataStructures # import is needed for parallel calls
import Distributions
import Gadfly
import Compose
using Optim
using Lora
using Distributions
using Logging
import JSON
using NLopt
using HDF5 # HDF5 installation is problematic on some machines
using PyCall
@pyimport yaml # PyYAML installation is problematic on some machines
using YAML # use YAML if PyYAML is not available

if VERSION < v"0.4.0-dev"
	using Docile # default for v > 0.4
	using Lexicon
	using Dates
end
if !in(dirname(Base.source_path()), LOAD_PATH)
	push!(LOAD_PATH, dirname(Base.source_path())) # add MADS path if not already there
end
include("MadsYAML.jl")
include("MadsASCII.jl")
include("MadsJSON.jl")
include("MadsIO.jl")
include("MadsTestFunctions.jl")
include("MadsMisc.jl")
include("MadsSA.jl")
include("MadsMC.jl")
include("MadsLM.jl")
include("MadsAnasol.jl")
include("MadsBIG.jl")
include("MadsLog.jl") # messages higher than specified level are printed
# Logging.configure(level=OFF) # OFF
# Logging.configure(level=CRITICAL) # ONLY CRITICAL
Logging.configure(level=DEBUG)
verbositylevel = 1
debuglevel = 1
const madsdir = join(split(Base.source_path(), '/')[1:end - 1], '/')

# @document
@docstrings

@doc "Set MADS debug level" ->
function setdebuglevel(level::Int)
	global debuglevel = level
end

@doc "Set MADS verbosity level" ->
function setverbositylevel(level::Int)
	global verbositylevel = level
end

@doc "Save calibration results" ->
function savecalibrationresults(madsdata, results)
	#TODO map estimated parameters on a new madsdata structure
	#TODO save madsdata in yaml file using dumpyamlmadsfile
	#TODO save residuals, predictions, observations (yaml?)
end

@doc "Calibrate with random initial guesses" ->
function calibraterandom(madsdata, numberofsamples; tolX=1e-3, tolG=1e-6, maxIter=100, lambda=100.0, lambda_mu=10.0, np_lambda=10, show_trace=false, usenaive=false)
	paramkeys = Mads.getparamkeys(madsdata)
	paramdict = OrderedDict(zip(paramkeys, Mads.getparamsinit(madsdata)))
	paramsoptdict = paramdict
	paramoptvalues = Mads.parametersample(madsdata, numberofsamples)
	bestresult = Any()
	bestphi = Inf
	for i in 1:numberofsamples
		for paramkey in keys(paramoptvalues)
			paramsoptdict[paramkey] = paramoptvalues[paramkey][i]
		end
		Mads.setparamsinit!(madsdata, paramsoptdict)
		result = Mads.calibrate(madsdata; quiet=true, tolX=tolX, tolG=tolG, maxIter=maxIter, lambda=lambda, lambda_mu=lambda_mu, np_lambda=np_lambda, show_trace=show_trace, usenaive=usenaive)

	end
	Mads.setparamsinit!(madsdata, paramdict)
end

@doc "Calibrate " ->
function calibrate(madsdata; quiet=false, tolX=1e-3, tolG=1e-6, maxIter=100, lambda=100.0, lambda_mu=10.0, np_lambda=10, show_trace=false, usenaive=false)
	rootname = getmadsrootname(madsdata)
	f_lm, g_lm = makelmfunctions(madsdata)
	optparamkeys = getoptparamkeys(madsdata)
	initparams = getparamsinit(madsdata, optparamkeys)
	lowerbounds = getparamsmin(madsdata, optparamkeys)
	upperbounds = getparamsmax(madsdata, optparamkeys)
	f_lm_sin = sinetransformfunction(f_lm, lowerbounds, upperbounds)
	g_lm_sin = sinetransformgradient(g_lm, lowerbounds, upperbounds)
	function calibratecallback(x_best)
		outfile = open("$rootname.iterationresults", "a+")
		write(outfile, string("OF: ", sse(f_lm_sin(x_best)), "\n"))
		write(outfile, string(Dict(optparamkeys, sinetransform(x_best, lowerbounds, upperbounds)), "\n"))
		close(outfile)
	end
	if usenaive
		results = Mads.naive_levenberg_marquardt(f_lm_sin, g_lm_sin, asinetransform(initparams, lowerbounds, upperbounds); maxIter=maxIter, lambda=lambda, lambda_mu=lambda_mu, np_lambda=np_lambda)
	else
		results = Mads.levenberg_marquardt(f_lm_sin, g_lm_sin, asinetransform(initparams, lowerbounds, upperbounds); quiet=true, root=rootname, tolX=tolX, tolG=tolG, maxIter=maxIter, lambda=lambda, lambda_mu=lambda_mu, np_lambda=np_lambda, show_trace=show_trace, callback=calibratecallback)
	end
	minimum = sinetransform(results.minimum, lowerbounds, upperbounds)
	nonoptparamkeys = getnonoptparamkeys(madsdata)
	minimumdict = Dict(getparamkeys(madsdata), getparamsinit(madsdata))
	for i = 1:length(optparamkeys)
		minimumdict[optparamkeys[i]] = minimum[i]
	end
	return minimumdict, results
end

@doc "Do a forward run using the init values of the parameters " ->
function forward(madsdata)
	initparams = Dict(Mads.getparamkeys(madsdata), Mads.getparamsinit(madsdata))
	f = Mads.makemadscommandfunction(madsdata)
	return f(initparams)
end

# NLopt is too much of a pain to install at this point
@doc "Do a calibration using NLopt " -> # TODO switch to a mathprogbase approach
function calibratenlopt(madsdata; algorithm=:LD_LBFGS)
	const paramkeys = getparamkeys(madsdata)
	const obskeys = getobskeys(madsdata)
	parammins = Array(Float64, length(paramkeys))
	parammaxs = Array(Float64, length(paramkeys))
	paraminits = Array(Float64, length(paramkeys))
	for i = 1:length(paramkeys)
		parammins[i] = madsdata["Parameters"][paramkeys[i]]["min"]
		parammaxs[i] = madsdata["Parameters"][paramkeys[i]]["max"]
		paraminits[i] = madsdata["Parameters"][paramkeys[i]]["init"]
	end
	obs = Array(Float64, length(obskeys))
	weights = ones(Float64, length(obskeys))
	for i = 1:length(obskeys)
		obs[i] = madsdata["Observations"][obskeys[i]]["target"]
		if haskey(madsdata["Observations"][obskeys[i]], "weight")
			weights[i] = madsdata["Observations"][obskeys[i]]["weight"]
		end
	end
	fg = makemadscommandfunctionandgradient(madsdata)
	function fg_nlopt(arrayparameters::Vector, grad::Vector)
		parameters = Dict(paramkeys, arrayparameters)
		resultdict, gradientdict = fg(parameters)
		residuals = Array(Float64, length(madsdata["Observations"]))
		ssr = 0
		i = 1
		for obskey in obskeys
			residuals[i] = resultdict[obskey] - obs[i]
			ssr += residuals[i] * residuals[i] * weights[i] * weights[i]
			i += 1
		end
		if length(grad) > 0
			i = 1
			for paramkey in paramkeys
				grad[i] = 0.
				j = 1
				for obskey in obskeys
					grad[i] += 2 * residuals[j] * gradientdict[obskey][paramkey]
					j += 1
				end
				i += 1
			end
		end
		return ssr
	end
	opt = NLopt.Opt(algorithm, length(paramkeys))
	NLopt.lower_bounds!(opt, parammins)
	NLopt.upper_bounds!(opt, parammaxs)
	NLopt.min_objective!(opt, fg_nlopt)
	NLopt.maxeval!(opt, int(1e3))
	minf, minx, ret = NLopt.optimize(opt, paraminits)
	return minf, minx, ret
end

@doc "Make a version of the mads file where the targets are given by the model predictions" ->
function maketruth(infilename::String, outfilename::String)
	md = loadyamlmadsfile(infilename)
	f = makemadscommandfunction(md)
	result = f(Dict(getparamkeys(md), getparamsinit(md)))
	outyaml = loadyamlfile(infilename)
	if haskey(outyaml, "Observations")
		for fullobs in outyaml["Observations"]
			obskey = collect(keys(fullobs))[1]
			obs = fullobs[obskey]
			obs["target"] = result[obskey]
		end
	end
	if haskey(outyaml, "Wells")
		for fullwell in outyaml["Wells"]
			wellname = collect(keys(fullwell))[1]
			for fullobs in fullwell[wellname]["obs"]
				obskey = collect(keys(fullobs))[1]
				obs = fullobs[obskey]
				obs["target"] = result[string(wellname, "_", obs["t"])]
			end
		end
	end
	dumpyamlfile(outfilename, outyaml)
end

end # Module end
