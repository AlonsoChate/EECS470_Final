`ifndef __DISPATCH_SVH__
`define __DISPATCH_SVH__

`include "sys_defs.svh"

typedef struct packed {
  PC_t pc;
  decoded_inst_t decoded_inst;

  phy_reg_tag_t [1:0] phy_src_reg;
  logic [1:0] ready;

  phy_reg_tag_t phy_dest_reg;
  logic valid;

  sq_idx_t sq_index;

  rob_idx_t rob_index;
} dispatch_packet_t;

interface if_dispatch;
  logic          [`WAY_CNT_LEN-1:0] num_dispatched_inst;
  logic          [`WAY_CNT_LEN-1:0] num_can_dispatch_inst;

  fu_type_e [`WAY-1:0] fu_type;
  fu_func_t [`WAY-1:0] fu_func;
  arch_reg_idx_t [`WAY-1:0] arch_dest_reg;
  phy_reg_idx_t  [`WAY-1:0] Told_in;
  phy_reg_idx_t  [`WAY-1:0] T_in;
  logic          [`WAY-1:0] halt;
  logic          [`WAY-1:0] illegal;
  rob_idx_t      [`WAY-1:0] rob_index;
  PC_t           [`WAY-1:0] pc;
  PC_t           [`WAY-1:0] target_pc;
  logic          [`WAY-1:0] taken;

  modport rob(
    input fu_type,
    input fu_func,
    input num_dispatched_inst,
    input arch_dest_reg,
    input Told_in,
    input T_in,
    input halt,
    input illegal,
    input pc,
    input target_pc,
    input taken,
    output rob_index,
    output num_can_dispatch_inst
  );

  modport dispatch_stage(
    output fu_type,
    output fu_func,
    output num_dispatched_inst,
    output arch_dest_reg,
    output Told_in,
    output T_in,
    output halt,
    output illegal,
    output pc,
    output target_pc,
    output taken,
    input rob_index,
    input num_can_dispatch_inst
  );
endinterface

`endif // __DISPATCH_SVH__
