`ifndef __RETIRE_SVH__
`define __RETIRE_SVH__

interface if_retire;
  logic [`WAY_CNT_LEN-1:0]          instr_num;
  phy_reg_idx_t   [`WAY-1:0]        Told;
  arch_reg_idx_t  [`WAY-1:0]        arch_dest_reg;
  phy_reg_idx_t   [`WAY-1:0]        T;
  logic is_store;
  logic [`WAY-1:0] is_load;
  logic store_accepted;

  modport rob(
    output instr_num,
    output Told,
    output arch_dest_reg,
    output T,
    output is_store,
    input store_accepted
  );

  modport freelist(
    input Told
  );

  modport sq(
    input is_store,
    output store_accepted
  );

  modport lq(
    input is_load
  );
endinterface

`endif // __RETIRE_SVH__
