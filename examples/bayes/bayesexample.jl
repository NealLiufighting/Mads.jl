import Mads
import Lora

problemdir = string((dirname(Base.source_path())))*"/"
Mads.madsinfo("""Problem directory: $(problemdir)""")

md = Mads.loadyamlmadsfile(problemdir*"w01.mads")
chain = Mads.bayessampling(md; nsteps=int(1e5), burnin=int(1e4), thinning=100)
Lora.describe(chain)
rootname = Mads.getmadsrootname(md)
Mads.scatterplotsamples(chain.samples, Mads.getoptparamkeys(md), rootname*"-bayes-results.svg")