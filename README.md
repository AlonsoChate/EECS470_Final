# EECS 470 Project 4 Group 1: R10K RISC-V Processor

## Project Folder Structure

```
.
|-- build\ -------------------- build files
|   |-- prog\ ----------------- compiled programs (each program in one subfolder)
|   |-- sim\ ------------------ simulators (each test simulator in one subfolder)
|   |   `-- novas.rc_template - config template for Verdi
|   `-- synth\ ---------------- synthesis output files (each design in one subfolder)
|       |-- cache.tcl --------- synthesize script for cache
|       |-- default.tcl ------- synthesize script for all designs
|       `-- pipeline.tcl ------ synthesize script for pipeline (not used currently)
|-- doc\ ---------------------- documents
|-- example\ ------------------ examples from course website
|-- testbench\ ---------------- test simulators
|-- test_prog\ ---------------- test cases (C program/RISC-V assembly)
|-- verilog\ ------------------ source code
|-- Makefile ------------------ build system entry
|-- README.md
`-- TODO.md ------------------- TODO list
```

## How-to: Synthesize

Currently, our build system adapts a "per-design" synthesis target scheme, namely, `make` targets related to synthesis is based on all the synthesizable top-designs in the source `verilog` folder. As usual, a top design name **must be** the name of its top level module.

### Setup

To allow one design comprises of multiple modules, which possibly locate in different source `.sv` files, our build system relies on a special hint present in each source file. A hint is no more than a SystemVerilog comment with following format:

```systemverilog
/* DESIGN = [design1 design2 ...] */
```

where `[design1 design2 ...]` is a list (could be empty, without square brackets) of designs that will need this source file.

For example, if the design `rs` needs `rs.sv` and `selector.sv`, there will be a hint in each file as follows:

```systemverilog
/* DESIGN = rs [design2 ...] */
```

We suggest put the hint at/near the beginning of source file.

Note:

1. each source file could have multiple hints, but we recommend to list all dependent designs in one comment line(hint)
2. each source file could have duplicate dependent design written in one or multiple hints
3. there is no need to write hints in header `.svh` files, and the build system will not look for hints in those files

### Synthesize

Simply run `make` with the target `syn_DESIGN`, where `DESIGN` is one design name which is in the hint(s) of one or more source files.

## Credits

Group 1 Members:

- Yiteng Cai (alonsoch@umich.edu)
- Haoxiang Fei (fettes@umich.edu)
- Yukun Lou (louyukun@umich.edu)
- Walter Wang (walwan@umich.edu)
- Zhenyuan Zhang (cryscan@umich.edu)

Special thanks to the teaching group!
