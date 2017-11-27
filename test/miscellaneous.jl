import Mads
import Base.Test
import Compat

if isdefined(Mads, :runcmd)
end

Mads.restarton()
Mads.restartoff()

if Mads.create_tests
	Mads.create_tests_off()
	Mads.create_tests_on()
else
	Mads.create_tests_on()
	Mads.create_tests_off()
end
if Mads.long_tests
	Mads.long_tests_off()
	Mads.long_tests_on()
else
	Mads.long_tests_on()
	Mads.long_tests_off()
end

Mads.setdebuglevel(1)
Mads.resetmodelruns()

Mads.functions(quiet=true)

Mads.stdouterrcaptureon();

Mads.loadmadsproblem("unknown");
Mads.loadmadsproblem("polynomial");

Mads.printerrormsg("a")

quiet_status = Mads.quiet
Mads.quietoff()

try
	run(pipeline(`julia -h`, stdout=DevNull, stderr=DevNull))
catch
	Mads.madscritical("Julia executable needs to be in the executable search path!")
end

try
	Mads.rmfile("test-create-symbolic-link")
	symlink(Pkg.dir("Mads"), "test-create-symbolic-link")
	rm("test-create-symbolic-link")
catch
	if is_windows()
		Mads.madscritical("Symbolic links cannot be created! Microsoft Windows require to execute julia as administrator.")
	else
		Mads.madscritical("Symbolic links cannot be created!")
	end
end

Mads.madsoutput("a")
Mads.madsdebug("a")
Mads.madsinfo("Testing ...")
Mads.help()
Mads.copyright()
if length(ARGS) < 1
	push!(ARGS, "testing")
else
	ARGS[1] = "testing"
end
include(joinpath("..", "src", "madsjl.jl"))
rm("madsjl.cmdline_hist")
Mads.functions(:ModuleThatDoesNotExist)
Mads.functions("createmadsproblem"; stdout=true)
Mads.functions(r"is.*par"; stdout=true)
Mads.functions(Mads, "loadmadsfile"; stdout=true)
Mads.functions(Mads, r"is.*par"; stdout=true)
Mads.setexecutionwaittime(0.)
if isdefined(Mads, :runcmd)
	if is_windows()
		Mads.runcmd("dir $(Pkg.dir("Mads"))")
		Mads.runcmd("dir $(Pkg.dir("Mads"))"; pipe=true)
		Mads.runcmd("dir $(Pkg.dir("Mads"))"; waittime=10.)
	else
		Mads.runcmd("ls $(Pkg.dir("Mads"))")
		Mads.runcmd("ls $(Pkg.dir("Mads"))"; pipe=true)
		Mads.runcmd("ls $(Pkg.dir("Mads"))"; waittime=10.)
	end
end
Mads.transposevector(["a";"b"])
Mads.transposematrix(["a" "b"])

if !haskey(ENV, "MADS_NO_GADFLY")
	Mads.plotwellSAresults(Dict(), Dict())
	Mads.plotwellSAresults(Dict("W"=>Dict()), Dict(), "w1")
	Mads.plotwellSAresults(Dict("Wells"=>Dict()), Dict(), "w1")

	Mads.plotobsSAresults(Dict(), Dict())
	Mads.setplotfileformat("a.ps", "")
	Mads.setplotfileformat("a", "EPS")
	Mads.setdefaultplotformat("TIFF")
	Mads.setdefaultplotformat("EPS")
	Mads.setdefaultplotformat("SVG")
	Mads.display("mads.png")
end

Mads.addkeyword!(Dict(), "ssdr")
Mads.addkeyword!(Dict("Problem"=>"ssdr"), "ssdr")
Mads.addkeyword!(Dict{String,Any}("Problem"=>"ssdr"), "Problem", "ssdr2")
Mads.addkeyword!(Dict("Problem"=>["ssdr2","paranoid"]), "ssdr")
Mads.addkeyword!(Dict("Problem"=>Dict("ssdr2"=>true)), "ssdr")

Mads.deletekeyword!(Dict(), "ssdr")
Mads.deletekeyword!(Dict("Problem"=>"ssdr"), "ssdr")
Mads.deletekeyword!(Dict{String,Any}("Problem"=>"ssdr"), "Problem", "ssdr")
Mads.deletekeyword!(Dict("Problem"=>["ssdr2","paranoid"]), "ssdr")
Mads.deletekeyword!(Dict("Problem"=>Dict("ssdr2"=>true)), "ssdr")
Mads.deletekeyword!(Dict("Problem"=>Dict("ssdr"=>true)), "Problem", "ssdr")
Mads.deletekeyword!(Dict("Problem"=>["ssdr","paranoid"]), "Problem", "ssdr")

Mads.stdouterrcaptureoff();

Mads.pkgversion("ModuleThatDoesNotExist") # this captures output

Mads.quieton()
if quiet_status
	Mads.quieton()
else
	Mads.quietoff()
end

Mads.setverbositylevel(1)

graph_status = Mads.graphoutput
Mads.graphoff()
Mads.graphon()
if graph_status
	Mads.graphon()
else
	Mads.graphoff()
end

@Base.Test.test Mads.haskeyword(Dict("Problem"=>"ssdr"),"ssdr") == true
@Base.Test.test Mads.haskeyword(Dict("Problem"=>Dict("ssdr"=>true)), "ssdr") == true
@Base.Test.test Mads.haskeyword(Dict("Problem"=>["ssdr","paranoid"]), "ssdr") == true
@Base.Test.test Mads.haskeyword(Dict("Problem"=>0.1), "Problem", "ssdr") == false

@Base.Test.test Mads.getdir("a.mads") == "."
@Base.Test.test Mads.getdir("test/a.mads") == "test"

Mads.createmadsobservations(4, 2; filename="a.inst")
Mads.rmfile("a.inst")

Mads.getsindx(Dict("Problem"=>Dict("sindx"=>"0.001")))
Mads.setsindx!(Dict("Problem"=>Dict("sindx"=>0.001)), 0.1)

if !haskey(ENV, "MADS_TRAVIS")
	Mads.status()
	Mads.set_nprocs_per_task(1)
	Mads.setdir()
	Mads.setprocs()
	Mads.setprocs(1)
	Mads.parsenodenames("wc[096-157,160,175]");
end

if isdefined(:Gadfly) && !haskey(ENV, "MADS_NO_GADFLY")
	Mads.plotseries(rand(4,5), "test.png", combined=false)
	Mads.plotseries(rand(4,5), "test.png")
	if isdefined(Mads, :display)
		Mads.display("test.png")
	end
	Mads.rmfile("test.png")
end

:passed