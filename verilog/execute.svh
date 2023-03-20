`ifndef __EXECUTE_SVH__
`define __EXECUTE_SVH__

`include "sys_defs.svh"

typedef union packed {
  xlen_t [1:0] branch;
  struct packed {
    xlen_t store_data;
    sq_idx_t sq_index;
    logic [29:0] _;
  } mem;
} exa_t;

typedef struct packed {
  PC_t           pc;
  decoded_inst_t decoded_inst;
  phy_reg_tag_t  phy_dest_reg;
  xlen_t         opa;
  xlen_t         opb;
  rob_idx_t      rob_index;
  exa_t          exa;
  logic          valid;
} execute_packet_t;

typedef struct packed {
  phy_reg_tag_t phy_dest_reg;
  xlen_t        result;
  rob_idx_t     rob_index;
  logic         valid;
} result_packet_t;

typedef struct packed {
  PC_t          addr;
  mem_t         data;
  fu_mem_write_func_e func;
  lq_idx_t      lq_index;
  sq_idx_t      sq_index;
  logic         valid;
} store_request_t;

typedef struct packed {
  PC_t          addr;
  sq_idx_t      sq_index;
  lq_idx_t      lq_index;
  rob_idx_t     rob_index;
  logic         valid;
} load_request_t;

typedef struct packed {
  logic valid;
  xlen_t data;
  xlen_t mask;
  fu_mem_write_func_e func;
} load_result_t;

`endif  // __EXECUTE_SVH__
