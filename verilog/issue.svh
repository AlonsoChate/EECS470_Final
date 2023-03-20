`ifndef __ISSUE_SVH__
`define __ISSUE_SVH__

`include "sys_defs.svh"

typedef struct packed {
  PC_t pc;
  decoded_inst_t decoded_inst;
  phy_reg_tag_t [1:0] phy_src_reg;
  phy_reg_tag_t phy_dest_reg;
  rob_idx_t rob_index;
  sq_idx_t sq_index;
  logic valid;
} issue_packet_t;

`endif // __ISSUE_SVH__
