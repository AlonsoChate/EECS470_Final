# make          <- runs simv (after compiling simv if needed)
# make all      <- runs simv (after compiling simv if needed)
# make simv     <- compile simv if needed (but do not run)
# make syn      <- runs syn_simv (after synthesizing if needed then
#                                 compiling synsimv if needed)
# make clean    <- remove files created during compilations (but not synthesis)
# make nuke     <- remove all files created during compilation and synthesis
#
# To compile additional files, add them to the TESTBENCH or SIMFILES as needed
# Every .vg file will need its own rule and one or more synthesis scripts
# The information contained here (in the rules for those vg files) will be
# similar to the information in those scripts but that seems hard to avoid.
#
#

################################################################################
## FOLDER DEFINITION
################################################################################

#
# code related
#
SOURCE_DIR := verilog
UNIT_TEST_DIR := testbench
TEST_PROG_DIR := test_prog

#
# build related
#
# base build dir
BUILD_DIR := build
# simulator dir
SIM_DIR := $(BUILD_DIR)/sim
# synthesis dir
SYN_DIR := $(BUILD_DIR)/synth
# compiled program dir
COMP_PROG_DIR := $(BUILD_DIR)/prog
# native program tool dir
TOOLCHAIN_SCRIPT_DIR := $(TEST_PROG_DIR)/script
# folder of the pipeline for generating correct writeback and memory
CORRECT_PIPELINE_DIR := example/p3_simv

#
# export necessary variables
#
export SYN_DIR
export SOURCE_DIR

################################################################################
## USEFUL VARIABLE
################################################################################

USER = $(shell whoami)
export ROOT_DIR := $(abspath $(CURDIR))

################################################################################
## RISC-V TOOLCHAIN AND FLAG
################################################################################

# give risc-v toolchain prefix on your system here
# by default, this comes from the shell environment as
# RISC_V_TOOLCHAIN_PREFIX or riscv_toolchain
RISC_V_TOOLCHAIN_PREFIX ?= $(riscv_toolchain)

# check whether we are on a CAEN machine
ifneq ($(shell uname -a | cut -d ' ' -f 2 | grep ".\+\.umich\.edu"),)
	CAEN_MACHINE = 1
endif

# process RISC_V_TOOLCHAIN_PREFIX
ifeq ($(CAEN_MACHINE),1)
	RISC_V_TOOLCHAIN_PREFIX = riscv$(space)
else
	ifeq ($(RISC_V_TOOLCHAIN_PREFIX),)
$(warning Variable RISC_V_TOOLCHAIN_PREFIX is empty, make system may use wrong toolchain!)
	endif
endif

# toolchain program commands
GCC = $(RISC_V_TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(RISC_V_TOOLCHAIN_PREFIX)objcopy
OBJDUMP = $(RISC_V_TOOLCHAIN_PREFIX)objdump
AS = $(RISC_V_TOOLCHAIN_PREFIX)as

ifeq ($(CAEN_MACHINE),1)
	ELF2HEX = $(RISC_V_TOOLCHAIN_PREFIX)elf2hex
else
	ELF2HEX = elf2hex
endif

# other scripts
CRT := $(TOOLCHAIN_SCRIPT_DIR)/crt.s
LINKER := $(TOOLCHAIN_SCRIPT_DIR)/linker.lds
ASLINKER := $(TOOLCHAIN_SCRIPT_DIR)/aslinker.lds

# flags
DEBUG_FLAG = -g
CFLAGS = -mno-relax \
				 -march=rv32im \
				 -mabi=ilp32 \
				 -nostartfiles \
				 -std=gnu11 \
				 -mstrict-align \
				 -mno-div
OFLAGS = -O0
ASFLAGS = -mno-relax \
					-march=rv32im \
					-mabi=ilp32 \
					-nostartfiles \
					-Wno-main \
					-mstrict-align
OBJFLAGS = -SD -M no-aliases
OBJCFLAGS = --set-section-flags .bss=contents,alloc,readonly
OBJDFLAGS = -SD -M numeric,no-aliases

################################################################################
## SYNOPSYS TOOL, FLAG, AND LIB
################################################################################

# synopsys tool program commands
VCS = SW_VCS=2020.12-SP2-1 vcs

# synopsys tool program flags
VCS_FLAGS = +v2k \
						-V \
						-sverilog \
						+vc \
						-Mupdate \
						-line \
						-full64 \
						+vcs+vcdpluson \
						-kdb \
						-lca \
						-debug_access+all

VCS_COV_FLAGS = -cm line+cond+fsm+tgl+branch+assert
VERDI_COV_FLAGS = -cov -covdir simv_$*.vdb

# standard component library
LIB = /afs/umich.edu/class/eecs470/lib/verilog/lec25dscc25.v

################################################################################
## SOURCE FILE AND UNIT TEST
################################################################################

HEADER_LIST = $(wildcard $(SOURCE_DIR)/*.svh)
SOURCE_LIST = $(wildcard $(SOURCE_DIR)/*.sv)
UNIT_TEST_LIST = \
	$(foreach UNIT_TEST, $(wildcard $(UNIT_TEST_DIR)/*.sv), \
						$(if $(shell grep '^\s*/\*\s\+SOURCE\s\+=\s\+.*\s\+\*/\s*$$' "$(UNIT_TEST)"), \
								 $(UNIT_TEST),))
TEST_PROG_C_LIST = $(wildcard $(TEST_PROG_DIR)/*.c)
TEST_PROG_S_LIST = $(wildcard $(TEST_PROG_DIR)/*.s)
TEST_PROG_LIST = $(TEST_PROG_C_LIST) $(TEST_PROG_S_LIST)

PIPELINE_TESTBENCH = testbench
PIPELINE_SYN_DESIGN = p

################################################################################
## CONFIGURATION
################################################################################

export CLOCK_NET_NAME := clock
export RESET_NET_NAME := reset
export CLOCK_PERIOD   := 16
export MAP_EFFORT 		:= high

################################################################################
## PARSE AND GENERATE TARGET NAME
################################################################################

# Function: gen_target
#     Generate a list of targets
#
# $(1): The list of files to process
# $(2): The prefix to add in the target
# $(3): The file extension to remove from file names
gen_target = $(foreach FILE, $(1), $(2)$(subst $(3),,$(notdir $(FILE))))

SIM_TARGETS = $(call gen_target,$(UNIT_TEST_LIST),sim_,.sv)
SIM_COV_TARGETS = $(call gen_target,$(UNIT_TEST_LIST),sim_cov_,.sv)
VERDI_TARGETS = $(call gen_target,$(UNIT_TEST_LIST),verdi_,.sv)
VERDI_COV_TARGETS = $(call gen_target,$(UNIT_TEST_LIST),verdi_cov_,.sv)

TEST_PROG_C_TARGETS = $(call gen_target,$(TEST_PROG_C_LIST),test_,.c)
TEST_PROG_S_TARGETS = $(call gen_target,$(TEST_PROG_S_LIST),test_,.s)
TEST_PROG_TARGETS = $(TEST_PROG_C_TARGETS) $(TEST_PROG_S_TARGETS)
TEST_PROG_SYN_C_TARGETS = $(call gen_target,$(TEST_PROG_C_LIST),test_syn_,.c)
TEST_PROG_SYN_S_TARGETS = $(call gen_target,$(TEST_PROG_S_LIST),test_syn_,.s)
TEST_PROG_SYN_TARGETS = $(TEST_PROG_SYN_C_TARGETS) $(TEST_PROG_SYN_S_TARGETS)

# parse out all possible unit tests in testbench folder
# format to specify needed source file in SOURCE_DIR:
# /* SOURCE = source1.sv source2.sv ... */
get_sim_source = \
	$(addprefix $(SOURCE_DIR)/, \
							$(sort $(shell grep '^\s*/\*\s\+SOURCE\s\+=\s\+.*\s\+\*/\s*$$' "$(1)" | \
								 						 sed 's/^\s*\/\*\s\+SOURCE\s\+=\s\+\(.*\)\s\+\*\/\s*$$/\1/g')))

# parse out all possible designs in source file
# format: /* DESIGN = design1 design2 ... */
POSSIBLE_DESIGNS = \
	$(sort $(foreach SOURCE, $(SOURCE_LIST), \
									 $(shell grep '^\s*/\*\s\+DESIGN\s\+=\s\+.*\s\+\*/\s*$$' "$(SOURCE)" | \
									 				 sed 's/^\s*\/\*\s\+DESIGN\s\+=\s\+\(.*\)\s\+\*\/\s*$$/\1/g')))

SYN_TARGETS = $(foreach DESIGN, $(POSSIBLE_DESIGNS), syn_$(DESIGN))

# The file extensions generated by synthesis.
SYN_CIRCUIT_EXTS = .ddc .vg _svsim.sv
SYN_REPORT_EXTS = .chk .rep .res
SYN_ALL_EXTS = $(SYN_CIRCUIT_EXTS) $(SYN_REPORT_EXTS)

TEST_PROG_EXE_EXTS = .elf .debug.elf
TEST_PROG_MEM_EXT = .mem
TEST_PROG_DUMP_EXTS = .dump .debug.dump
TEST_PROG_OUTPUT_EXTS = .wb.out .mem.out
TEST_PROG_TEST_EXTS = $(TEST_PROG_MEM_EXT) $(TEST_PROG_DUMP_EXTS) $(TEST_PROG_OUTPUT_EXTS)

# Function: gen_output
#     Generate a list of output files.
#
# $(1): The output directory (typically $(SYN_DIR) or $(COMP_PROG_DIR))
# $(2): The real name (stem) to be processed.
# $(3): List of file extensions for to be added at the end
gen_output = $(addprefix $(1)/$(2)/$(2), $(3))

SYN_ALL_PATTERN = $(addprefix %,$(SYN_ALL_EXTS))

get_syn_design_src = \
	$(sort $(foreach SOURCE, $(SOURCE_LIST), \
									 $(if $(shell grep '^\s*/\*\s\+DESIGN\s\+=.*\s\+$(1)\s\+.*\*/\s*$$' "$(SOURCE)"), \
									 			$(SOURCE),)))

################################################################################
## RULES
################################################################################

# Enable second expansion for makefile targets.
.SECONDEXPANSION:

#
# Default targets
#
all: test_all test_syn_all
.PHONY: all

# Target for teaching group
simv syn_simv: VCS_FLAGS += +define+NDEBUG+NCLOCK_LIMIT
simv: $(SIM_DIR)/$(PIPELINE_TESTBENCH)/simv_$(PIPELINE_TESTBENCH)
	ln -sf $< ./$@
	ln -sf $<.daidir ./$@.daidir

syn_simv: $(SIM_DIR)/$(PIPELINE_TESTBENCH)/simv_syn_$(PIPELINE_TESTBENCH)
	ln -sf $< ./$@
	ln -sf $<.daidir ./$@.daidir

#
# Simulation
#
$(SIM_COV_TARGETS):	VCS_FLAGS += $(VCS_COV_FLAGS)
$(SIM_COV_TARGETS):	SIMV_FLAGS += $(VCS_COV_FLAGS)
$(SIM_TARGETS) $(SIM_COV_TARGETS): sim_% : $(SIM_DIR)/$$(call rm_prefix,cov_,$$*)/simv_$$*
	cd $(SIM_DIR)/$(call rm_prefix,cov_,$*)/ && ./simv_$* $(SIMV_FLAGS) | tee $@.out
.PHONY: $(SIM_TARGETS) $(SIM_COV_TARGETS)

# Generate actual simv_*/simv_cov_* file
simv_%: $$(call get_sim_source,$(UNIT_TEST_DIR)/$$(call rm_prefix,cov_,$$(notdir $$*)).sv) $(UNIT_TEST_DIR)/$$(call rm_prefix,cov_,$$(notdir $$*)).sv | $$(dir %)/.
	cd $(SIM_DIR)/$(notdir $*)/ && \
		$(VCS) $(VCS_FLAGS) +incdir+$(ROOT_DIR)/$(SOURCE_DIR) $(abspath $^) -o $(ROOT_DIR)/$@

# special target for pipeline testbench with synthesized pipeline
$(SIM_DIR)/$(PIPELINE_TESTBENCH)/simv_syn_$(PIPELINE_TESTBENCH): $(UNIT_TEST_DIR)/$(PIPELINE_TESTBENCH).sv $(SYN_DIR)/$(PIPELINE_SYN_DESIGN)/$(PIPELINE_SYN_DESIGN)_svsim.sv $(SYN_DIR)/$(PIPELINE_SYN_DESIGN)/$(PIPELINE_SYN_DESIGN).vg $(SOURCE_DIR)/mem.sv $(LIB) | $(SIM_DIR)/testbench/.
	cd $(SIM_DIR)/$(PIPELINE_TESTBENCH)/ && \
		$(VCS) $(VCS_FLAGS) +incdir+$(ROOT_DIR)/$(SOURCE_DIR) +define+SYNTH_TEST+NDEBUG $(abspath $^) -o $(ROOT_DIR)/$@

#
# Programs
#
test_all: $(TEST_PROG_TARGETS); @:
test_syn_all: $(TEST_PROG_SYN_TARGETS); @:
.PHONY: test_all test_syn_all

$(TEST_PROG_TARGETS): test_% : $(SIM_DIR)/$(PIPELINE_TESTBENCH)/simv_$(PIPELINE_TESTBENCH) $$(call gen_output,$(COMP_PROG_DIR),$$*,$(TEST_PROG_TEST_EXTS))
	-rm $(SIM_DIR)/$(PIPELINE_TESTBENCH)/program.mem
	cp $(COMP_PROG_DIR)/$*/$*.mem $(SIM_DIR)/$(PIPELINE_TESTBENCH)/program.mem
	cd $(SIM_DIR)/$(PIPELINE_TESTBENCH)/ && \
		./simv_$(PIPELINE_TESTBENCH) $(SIMV_FLAGS) > $*.out
	@echo "Checking program.out for $*!"
	-grep "^@@@" $(SIM_DIR)/$(PIPELINE_TESTBENCH)/$*.out | diff - $(COMP_PROG_DIR)/$*/$*.mem.out
	@echo "Checking writeback.out for $*!"
	-diff $(SIM_DIR)/$(PIPELINE_TESTBENCH)/writeback.out $(COMP_PROG_DIR)/$*/$*.wb.out

$(TEST_PROG_SYN_TARGETS): test_syn_% : $(SIM_DIR)/$(PIPELINE_TESTBENCH)/simv_syn_$(PIPELINE_TESTBENCH) $$(call gen_output,$(COMP_PROG_DIR),$$*,$(TEST_PROG_TEST_EXTS))
	-rm $(SIM_DIR)/$(PIPELINE_TESTBENCH)/program.mem
	cp $(COMP_PROG_DIR)/$*/$*.mem $(SIM_DIR)/$(PIPELINE_TESTBENCH)/program.mem
	cd $(SIM_DIR)/$(PIPELINE_TESTBENCH)/ && \
		./simv_syn_$(PIPELINE_TESTBENCH) $(SIMV_FLAGS) > syn_$*.out
	@echo "Checking program.out for $*!"
	-grep "^@@@" $(SIM_DIR)/$(PIPELINE_TESTBENCH)/syn_$*.out | diff - $(COMP_PROG_DIR)/$*/$*.mem.out
	@echo "Checking writeback.out for $*!"
	-diff $(SIM_DIR)/$(PIPELINE_TESTBENCH)/writeback.out $(COMP_PROG_DIR)/$*/$*.wb.out
.PHONY: $(TEST_PROG_TARGETS) $(TEST_PROG_SYN_TARGETS)

# rule for compile .c test programs
%.elf %.debug.elf: $(CRT) $(LINKER) $(TEST_PROG_DIR)/$$(notdir $$*).c | $$(dir %)/.
	$(GCC) $(CFLAGS) $(OFLAGS) $(CRT) $(TEST_PROG_DIR)/$(notdir $*).c -T $(LINKER) -o $*.elf
	$(GCC) $(CFLAGS) $(DEBUG_FLAG) $(CRT) $(TEST_PROG_DIR)/$(notdir $*).c -T $(LINKER) -o $*.debug.elf

# rule for compile .s test programs
%.elf %.debug.elf: $(ASLINKER) $(TEST_PROG_DIR)/$$(notdir $$*).s | $$(dir %)/.
	$(GCC) $(ASFLAGS) $(TEST_PROG_DIR)/$(notdir $*).s -T $(ASLINKER) -o $*.elf
	cp $*.elf $*.debug.elf

%.dump %.debug.dump: %.debug.elf
	$(OBJCOPY) $(OBJCFLAGS) $<
	$(OBJDUMP) $(OBJFLAGS) $< > $*.dump
	$(OBJDUMP) $(OBJDFLAGS) $< > $*.debug.dump

%.mem: %.elf
	$(ELF2HEX) 8 8192 $< > $@

%.wb.out %.mem.out: $(CORRECT_PIPELINE_DIR)/simv %.mem
	-rm $(CORRECT_PIPELINE_DIR)/program.mem
	cp $*.mem $(CORRECT_PIPELINE_DIR)/program.mem
	cd $(CORRECT_PIPELINE_DIR) && ./simv | grep "^@@@" > $(ROOT_DIR)/$*.mem.out
	-rm $*.wb.out
	cp $(CORRECT_PIPELINE_DIR)/writeback.out $*.wb.out

#
# Synthesis
#
$(SYN_TARGETS): syn_% : $$(call gen_output,$(SYN_DIR),$$*,$(SYN_CIRCUIT_EXTS))
.PHONY: $(SYN_TARGETS)

.PRECIOUS: $(SYN_ALL_PATTERN)
$(SYN_ALL_PATTERN): $$(call get_syn_design_src,$$(notdir $$*)) | $$(dir %)/.
	@echo "Synthesizing design: $(notdir $*)"
	@echo "Source files: $^"
	cd $(dir $*) && \
		env 'DESIGN_NAME=$(notdir $*)' \
		'DESIGN_SOURCE_LIST=$(strip $(foreach SOURCE, $(filter %.sv, $^), $(notdir $(SOURCE))))' \
		dc_shell-t -f '$(ROOT_DIR)/$(SYN_DIR)/default.tcl' | tee $(shell date +"%y-%m-%d-%T")-$(notdir $*).log

#
# Debugging with verdi
#
$(VERDI_COV_TARGETS): VERDI_FLAGS += $(VERDI_COV_FLAGS)
# this target only need simv_* file
$(VERDI_TARGETS): verdi_% : $(SIM_DIR)/$$*/simv_$$* $(SIM_DIR)/$$*/novas.rc | /tmp/$(USER)/470/.
	cd $(SIM_DIR)/$*/ && ./simv_$* -gui=verdi $(VERDI_FLAGS)

# this target needs to run simv_cov_* file for coverage data
$(VERDI_COV_TARGETS): verdi_cov_% : sim_cov_% $(SIM_DIR)/$$*/novas.rc | /tmp/$(USER)/470/.
	cd $(SIM_DIR)/$*/ && ./simv_cov_$* -gui=verdi $(VERDI_FLAGS)

$(SIM_DIR)/%/novas.rc: $(SIM_DIR)/novas.rc_template
	sed s/UNIQNAME/$(USER)/ $< > $@

#
# Cleaning
#
clean:
	rm -rf *simv *simv.daidir csrc vcs.key program.out *.key
	rm -rf vis_simv vis_simv.daidir
	rm -rf dve* inter.vpd DVEfiles
	rm -rf syn_simv syn_simv.daidir syn_program.out
	rm -rf synsimv synsimv.daidir csrc vcdplus.vpd vcs.key synprog.out pipeline.out writeback.out vc_hdrs.h
	rm -f *.elf *.dump *.mem debug_bin
	rm -rf verdi* novas* *fsdb*
	rm -f Synopsys_stack_trace_* crte_*.txt
	rm -f *-verilog.pvl *-verilog.syn
	rm -f *.mr
	rm -f filenames*.log

nuke:	clean
	rm -rf synth/*.vg synth/*.rep synth/*.ddc synth/*.chk synth/*.log synth/*.syn
	rm -rf synth/*.out command.log synth/*.db synth/*.svf synth/*.mr synth/*.pvl

################################################################################
## MISC
################################################################################

blank :=
space := $(blank) $(blank)
percent := %

rm_prefix = $(patsubst $(1)%,%,$(2))

# Depend on directory/. (preferably order-only) to create it if needed.
.PRECIOUS: %/.
%/.:
	if [[ ! -d "$(dir $@)" ]]; then mkdir -p "$(dir $@)"; fi
