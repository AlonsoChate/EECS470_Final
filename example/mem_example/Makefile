# make          <- runs simv (after compiling simv if needed)
# make simv     <- compiles simv without running
# make dve      <- runs GUI debugger (after compiling it if needed)
# make syn      <- runs syn_simv (after synthesizing if needed then 
#                                 compiling syn_simv if needed)
# make clean    <- remove files created during compilations (but not synthesis)
# make nuke     <- remove all files created during compilation and synthesis
#
# To compile additional files, add them to the TESTBENCH or SIMFILES as needed
# Every .vg file will need its own rule and one or more synthesis scripts
# The information contained here (in the rules for those vg files) will be 
# similar to the information in those scripts but that seems hard to avoid.
#

VCS = SW_VCS=2017.12-SP2-1 vcs -sverilog +vc -Mupdate -line -full64 +define+CACHE_MODE +lint=TFIPC-L -debug_access+all
LIB = /afs/umich.edu/class/eecs470/lib/verilog/lec25dscc25.v

##### 
# Modify starting here
#####

memtb:
	export TESTBENCH="memtb.sv" && \
	export SIMFILES="ISA.svh sys_defs.svh mem.sv" && \
	$(MAKE) simv

cachetb:
	export TESTBENCH="cachetb.sv" && \
	export SIMFILES="ISA.svh sys_defs.svh mem.sv icache.sv cachemem.sv" && \
	$(MAKE) simv

#####
# Should be no need to modify after here
#####
simv:	$(SIMFILES) $(TESTBENCH)
	$(VCS) $^ -o simv

clean:
	rm -rvf simv *.daidir csrc vcs.key program.out \
	syn_simv syn_simv.daidir syn_program.out \
	dve *.vpd *.vcd *.dump ucli.key 