`ifndef __RESOLVE_SVH__
`define __RESOLVE_SVH__

interface if_resolve #(
  parameter WIDTH = 1
);
  logic     [WIDTH-1:0] valid;
  PC_t      [WIDTH-1:0] source_pc;
  PC_t      [WIDTH-1:0] target_pc;
  rob_idx_t [WIDTH-1:0] rob_index;
  logic     [WIDTH-1:0] correct;
  logic     [WIDTH-1:0] taken;

  modport rob(
    input valid,
    input target_pc,
    input rob_index,
    input taken,
    input correct
  );

  modport fu_branch(
    output valid,
    output source_pc,
    output target_pc,
    output rob_index,
    output taken
  );

  modport branch_predictor(
    input valid,
    input taken,
    input source_pc,
    input target_pc,
    output correct
  );
endinterface

`endif // __RESOLVE_SVH__
