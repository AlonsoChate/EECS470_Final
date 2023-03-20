# Must be run from the Makefile to set environment vars.

# get exported env from Makefile
set root_dir [string trim "[getenv ROOT_DIR]"]
set syn_dir [string trim "$root_dir/[getenv SYN_DIR]/"]
set source_dir [string trim "$root_dir/[getenv SOURCE_DIR]"]

set design_name [string trim [getenv DESIGN_NAME]]
set clock_name [string trim [getenv CLOCK_NET_NAME]]
set reset_name [string trim [getenv RESET_NET_NAME]]
set clock_period [string trim [getenv CLOCK_PERIOD]]
set map_effort [string trim [getenv MAP_EFFORT]]

# change current dir to syn_dir
cd "$syn_dir/$design_name"
pwd

# configure search path
set search_path "/afs/umich.edu/class/eecs470/lib/synopsys/"
set target_library "lec25dscc25_TT.db"

# echo "Loading cached designs..."

# set new_link_libraries [list]
# set dont_touch_designs [list]

# foreach ddc [glob -tails -nocomplain -directory $cache_dir "*.ddc"] {
# 	set cache_design_name [string range $ddc 0 end-4]

# 	if [string equal $cache_design_name $design_name] {
# 		echo "Skipping cached design with identical name $cache_design_name"
# 	} else {
# 		lappend dont_touch_designs $cache_design_name
# 		lappend new_link_libraries "$cache_dir/$ddc"
# 		echo "Loaded cached design $cache_design_name"
# 	}
# }

# set link_library [concat $new_link_libraries $link_library]

set link_library [concat "*" $target_library]

# suppress unnecessary messages
set suppress_errors [concat $suppress_errors "UID-401"]
suppress_message {"VER-130"}

# load source design files
lappend search_path "$source_dir"

# read in related design files
foreach src [list [string trim [getenv DESIGN_SOURCE_LIST]]] {
  echo "Loading design file: $src"
  if { ![analyze -f sverilog "$src"] } {
    echo "Error when loading design file: $src!"
    exit 1
  }
}

if { ![elaborate $design_name] } { exit 1 }

# foreach design $dont_touch_designs {
# 	set_dont_touch $design
# }

#/***********************************************************/
#/* Set some flags for optimisation */

set compile_top_all_paths "true"
set auto_wire_load_selection "false"
set compile_seqmap_synchronous_extraction "true"

# uncomment this and change number appropriately if on multi-core machine
set_host_options -max_cores 4

#/***********************************************************/
#/*  Clk Periods/uncertainty/transition                     */

set CLK_TRANSITION 0.1
set CLK_UNCERTAINTY 0.1
set CLK_LATENCY 0.1

#/* Input/output Delay values */
set AVG_INPUT_DELAY 0.1
set AVG_OUTPUT_DELAY 0.1

#/* Critical Range (ns) */
set CRIT_RANGE 1.0

#/***********************************************************/
#/* Design Constrains: Not all used                         */
set MAX_TRANSITION 1.0
set FAST_TRANSITION 0.1
set MAX_FANOUT 32
set MID_FANOUT 8
set LOW_FANOUT 1
set HIGH_DRIVE 0
set HIGH_LOAD 1.0
set AVG_LOAD 0.1
set AVG_FANOUT_LOAD 10

#/***********************************************************/
#/*BASIC_INPUT = cb18os120_tsmc_max/nd02d1/A1
#BASIC_OUTPUT = cb18os120_tsmc_max/nd02d1/ZN*/

set DRIVING_CELL dffacs1

#/* DONT_USE_LIST = {   } */

#/*************operation cons**************/
#/*OP_WCASE = WCCOM;
#OP_BCASE = BCCOM;*/
set WIRE_LOAD "tsmcwire"
set LOGICLIB lec25dscc25_TT
#/*****************************/

#/* Sourcing the file that sets the Search path and the libraries(target,link) */

set sys_clk $clock_name

set netlist_file [format "%s%s/%s" $syn_dir $design_name "${design_name}.vg"]
set svsim_file [format "%s%s/%s" $syn_dir $design_name "${design_name}_svsim.sv"]
set ddc_file [format "%s%s/%s" $syn_dir $design_name "${design_name}.ddc"]
set rep_file [format "%s%s/%s" $syn_dir $design_name "${design_name}.rep"]
set res_file [format "%s%s/%s" $syn_dir $design_name "${design_name}.res"]
set dc_shell_status [set chk_file [format "%s%s/%s" $syn_dir $design_name "${design_name}.chk"]]

#/* if we didnt find errors at this point, run */
if {  $dc_shell_status != [list] } {
  current_design $design_name
  link
  set_wire_load_model -name $WIRE_LOAD -lib $LOGICLIB $design_name
  set_wire_load_mode top
  set_fix_multiple_port_nets -outputs -buffer_constants
  create_clock -period $clock_period -name $sys_clk [find port $sys_clk]
  set_clock_uncertainty $CLK_UNCERTAINTY $sys_clk
  set_fix_hold $sys_clk
  group_path -from [all_inputs] -name input_grp
  group_path -to [all_outputs] -name output_grp
  set_driving_cell -lib_cell $DRIVING_CELL [all_inputs]
  remove_driving_cell [find port $sys_clk]
  set_fanout_load $AVG_FANOUT_LOAD [all_outputs]
  set_load $AVG_LOAD [all_outputs]
  set_input_delay $AVG_INPUT_DELAY -clock $sys_clk [all_inputs]
  remove_input_delay -clock $sys_clk [find port $sys_clk]
  set_output_delay $AVG_OUTPUT_DELAY -clock $sys_clk [all_outputs]
  set_dont_touch $reset_name
  set_resistance 0 $reset_name
  set_drive 0 $reset_name
  set_critical_range $CRIT_RANGE [current_design]
  set_max_delay $clock_period [all_outputs]
  set MAX_FANOUT $MAX_FANOUT
  set MAX_TRANSITION $MAX_TRANSITION
  uniquify
  ungroup -all -flatten

  redirect $chk_file { check_design }

  #if { ![compile -map_effort $map_effort -area_effort low] } { exit 1 }
  if { ![compile -map_effort $map_effort] } { exit 1 }

  write -hier -format verilog -output $netlist_file $design_name
  write -hier -format ddc -output $ddc_file $design_name
  write -format svsim -output $svsim_file $design_name

  redirect $rep_file { report_design -nosplit }
  redirect -append $rep_file { report_area }
  redirect -append $rep_file { report_timing -max_paths 2 -input_pins -nets -transition_time -nosplit }
  redirect -append $rep_file { report_constraint -max_delay -verbose -nosplit }
  redirect $res_file { report_resources -hier }
  remove_design -all
  read_file -format verilog -netlist $netlist_file
  current_design $design_name
  redirect -append $rep_file { report_reference -nosplit }
  quit
} else {
  quit
}
