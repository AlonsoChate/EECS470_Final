`ifndef FETCH_SVH
`define FETCH_SVH

`include "sys_defs.svh"

typedef struct packed {
    arch_reg_idx_t [1:0] arch_src_reg;
    arch_reg_idx_t arch_dest_reg;
} map_table_input_t;

typedef struct packed {
    phy_reg_tag_t [1:0] phy_src_reg;
    phy_reg_tag_t phy_dest_reg;
    logic [1:0] ready;
} map_table_output_t;

typedef struct packed {
    logic valid;
    inst_t inst;
    PC_t PC;
    PC_t target_pc;
    logic taken;
} fetch_packet_t;

`endif
