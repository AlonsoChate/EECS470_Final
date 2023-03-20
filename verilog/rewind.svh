`ifndef __REWIND_SVH__
`define __REWIND_SVH__

`include "sys_defs.svh"

interface if_rewind;
  phy_reg_idx_t          [`WAY-1:0]   reg_T;
  phy_reg_idx_t          [`WAY-1:0]   reg_Told;
  rob_idx_t              [`WAY-1:0]   rob_index;       // to RS
  logic  [`WAY_CNT_LEN-1:0]           num;

  modport rob(
    output reg_T,
    output reg_Told,
    output rob_index,
    output num
  );

  modport rs(
    input num,
    input rob_index
  );

  modport map_table(
    input num,
    input reg_T,
    input reg_Told
  );

  modport freelist(
    input num,
    input reg_T
  );
endinterface

`endif // __REWIND_SVH__
