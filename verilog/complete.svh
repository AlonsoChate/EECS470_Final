`ifndef __COMPLETE_SVH__
`define __COMPLETE_SVH__

`include "sys_defs.svh"

typedef struct packed {
  // The destination physical register (if any) of the completed instruction.
  phy_reg_tag_t phy_dest_reg;
  // The ROB # of the completed instruction.
  rob_idx_t     rob_index;
  // If this packet is valid.
  logic         valid;
} complete_packet_t;

`endif  // __COMPLETE_SVH__
