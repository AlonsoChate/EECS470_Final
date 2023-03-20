/* DESIGN = p regfile */
`include "sys_defs.svh"

`timescale 1ns/100ps

module regfile #(
  parameter SIZE = `PHY_REG_SIZE,
  parameter R_WIDTH = 6, // read width
  parameter W_WIDTH = 3  // write width
) (
  input clock, reset,

  input phy_reg_tag_t [R_WIDTH-1:0] read_tag,
  output xlen_t [R_WIDTH-1:0] read_value,

  input phy_reg_tag_t [W_WIDTH-1:0] write_tag,
  input xlen_t [W_WIDTH-1:0] write_value,

  input phy_reg_idx_t [`WAY-1:0] retire_read_tag,
  output xlen_t [`WAY-1:0] retire_read_value
);
  xlen_t [SIZE-1:0] registers;
  xlen_t [SIZE-1:0] registers_next;

  // read values for retired instr.s
  generate
    for (genvar i = 0; i < `WAY; i++) begin
      assign retire_read_value[i] = registers[retire_read_tag[i]];
    end
  endgenerate

  always_comb begin
    registers_next = registers;
    for (int i = 0; i < R_WIDTH; i++) begin
      read_value[i] = 0;
      if (read_tag[i].valid && read_tag[i].index != 0) begin
        read_value[i] = registers[read_tag[i].index];
      end
    end
    for (int i = 0; i < W_WIDTH; i++) begin
      if (write_tag[i].valid) begin
        registers_next[write_tag[i].index] = write_value[i];
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset)
      registers <= `SD 0;
    else
      registers <= `SD registers_next;
  end
endmodule // regfile
