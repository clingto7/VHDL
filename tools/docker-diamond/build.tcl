# Headless Diamond build for exp2 breathing LED.
# Consumes /work/project/exp2.ldf, produces impl1/<top>_impl1.jed.
prj_project open /work/project/exp2.ldf
prj_run Synthesis -impl impl1
prj_run Map -impl impl1
prj_run PAR -impl impl1
prj_run Export -impl impl1 -task Bitgen
prj_project save
prj_project close
