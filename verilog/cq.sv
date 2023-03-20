/* DESIGN = p cq */
`include "complete.svh"
`include "execute.svh"

`timescale 1ns/100ps

// Completion Queue.
module cq #(
  parameter C_WIDTH = `WAY,
  parameter E_WIDTH = `NUM_FU_TYPE * `WAY,
  parameter SIZE = 32,
  localparam INDEX_LEN = `CAL_IDX_LEN(SIZE)
) (
  input clock, reset,
  input flush,

  input result_packet_t [E_WIDTH-1:0] execute,
  output logic [E_WIDTH-1:0] stall,

  output complete_packet_t [C_WIDTH-1:0] complete,

  output phy_reg_tag_t [C_WIDTH-1:0] reg_file_write_tag,
  output xlen_t [C_WIDTH-1:0] reg_file_write_value
);
  result_packet_t [SIZE-1:0] queue;
  result_packet_t [SIZE-1:0] queue_next;

  typedef logic [INDEX_LEN-1:0] idx_t;
  idx_t head;
  idx_t head_next;
  idx_t tail;
  idx_t tail_next;
  logic empty;
  logic empty_next;

  always_comb begin
    queue_next = queue;
    head_next = head;
    tail_next = tail;
    empty_next = empty;
    complete = 0;
    stall = {(E_WIDTH){`TRUE}};
    reg_file_write_tag = 0;
    reg_file_write_value = 0;
    if (flush) begin
      queue_next = 0;
      head_next = 0;
      tail_next = 0;
      empty_next = `TRUE;
    end
    for (int i = 0; i < E_WIDTH; i++) begin
      if (empty_next == `TRUE || tail_next != head) begin
        if (execute[i].valid) begin
          queue_next[tail_next] = execute[i];
          tail_next = (tail_next + 1) % SIZE;
          empty_next = `FALSE;
          stall[i] = `FALSE;
        end
      end
    end
    if (empty == `FALSE) begin
      for (int i = 0; i < C_WIDTH; i++) begin
        if (head_next != tail && queue[head_next].valid) begin
          complete[i].phy_dest_reg = queue[head_next].phy_dest_reg;
          complete[i].rob_index = queue[head_next].rob_index;
          complete[i].valid = `TRUE;
          reg_file_write_tag[i] = queue[head_next].phy_dest_reg;
          reg_file_write_value[i] = queue[head_next].result;
          queue_next[head_next] = 0;
          head_next = (head_next + 1) % SIZE;
        end
      end
      if (head_next == tail_next) begin
        empty_next = `TRUE;
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset || flush) begin
      queue <= `SD 0;
      head <= `SD 0;
      tail <= `SD 0;
      empty <= `SD `TRUE;
    end else begin
      queue <= `SD queue_next;
      head <= `SD head_next;
      tail <= `SD tail_next;
      empty <= `SD empty_next;
    end
  end

endmodule
