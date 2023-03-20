`ifndef __UPDATE_SVH__
`define __UPDATE_SVH__

interface if_update #(
  parameter WIDTH = 3
);
  logic [WIDTH-1:0] valid;
  PC_t  [WIDTH-1:0] source_pc;
  PC_t  [WIDTH-1:0] target_pc;
  logic [WIDTH-1:0] taken;
  logic [WIDTH-1:0] correct;

  modport rob(
    output valid,
    output source_pc,
    output target_pc,
    output taken,
    output correct
  );

  modport branch_predictor(
    input valid,
    input source_pc,
    input target_pc,
    input taken
  );
endinterface

`endif // __UPDATE_SVH__
