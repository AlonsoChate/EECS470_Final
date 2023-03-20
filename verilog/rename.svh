`ifndef __RENAME_SVH__
`define __RENAME_SVH__

`include "sys_defs.svh"

interface if_rename;
  logic [`WAY_CNT_LEN-1:0]         num_to_dispatch;
  arch_reg_idx_t [`WAY-1:0]        arch_dest_reg;
  phy_reg_idx_t [`WAY-1:0]         dispatch_free_reg;
  logic [`WAY_CNT_LEN-1:0]         free_reg_valid;

  modport dispatch_stage(
    output num_to_dispatch,
    output arch_dest_reg,
    input dispatch_free_reg,
    input free_reg_valid
  );

  modport freelist(
    input num_to_dispatch,
    input arch_dest_reg,
    output dispatch_free_reg,
    output free_reg_valid
  );
endinterface

`endif // __RENAME_SVH__
