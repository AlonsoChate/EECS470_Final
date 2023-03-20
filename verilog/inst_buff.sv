/* DESIGN = p */
`include "fetch.svh"

module inst_buff #(
  parameter SIZE = 12,
  localparam INDEX_LEN = `CAL_IDX_LEN(SIZE)
) (
  input   clock, reset,
  input   fetch_flush,  // flush current buffer, from ROB
  input   fetch_packet_t  [`WAY-1:0]          fetch_in,  // From fetch stage
  output  fetch_packet_t  [`WAY-1:0]          inst_buff_out,  // To dispatch stage
  // From dispatch stage, max number of instr.s can be fetched
  input                   [`WAY_CNT_LEN-1:0]  dispatch_stage_num_can_fetch,
  input                   [`WAY_CNT_LEN-1:0]  store_empty_slots,
  output  logic           [`WAY_CNT_LEN-1:0]  store_valid_count,
  // To fetch stage, number of instr.s put into instr. buffer
  output  logic           [`WAY_CNT_LEN-1:0]  inst_buff_num_fetched
);

  fetch_packet_t  [SIZE-1:0]                  queue, queue_next;
  // head is the oldest instr.s to give out to dispatch stage
  logic           [INDEX_LEN-1:0]    head, head_next;
  // tail is the youngest instr.s received from fetch stage
  logic           [INDEX_LEN-1:0]    tail, tail_next;
  logic                                       is_empty, is_empty_next;

  always_comb begin
    // default value
    inst_buff_out         = '0;
    inst_buff_num_fetched = '0;

    queue_next            = queue;
    head_next             = head;
    tail_next             = tail;
    is_empty_next         = is_empty;

    store_valid_count = '0;

    // assign outputs to dispatch stage
    for (int unsigned i = 0; i < `WAY; i++) begin
      if (i < dispatch_stage_num_can_fetch &&  // dispatch stage can receive
          !is_empty_next) begin // instr. buffer has instr.
        // give out an instr.

        casez (queue[head_next].inst)
          `RV32_SB, `RV32_SH, `RV32_SW:
            if ((store_valid_count + 1) > store_empty_slots) begin
              break;
            end else begin
              store_valid_count++;
            end
        endcase

        inst_buff_out[i]  = queue[head_next];
        // invalidate queue entry
        queue_next[head_next] = '0;
        // check whether queue is empty
        if (head_next == tail)
          is_empty_next = `TRUE;
        // move head forward
        head_next     = (head_next + 1) % SIZE;
      end
    end

    // read in inputs from fetch stage
    for (int unsigned i = 0; i < `WAY; i++) begin
      if (fetch_in[i].valid &&  // packet from fetch stage is valid
          ((tail_next + 1) % SIZE != head_next || is_empty_next)) begin  // there is space
        // move tail forward
        tail_next             = (tail_next + 1) % SIZE;
        // put in an instr.
        queue_next[tail_next] = fetch_in[i];
        // increment feedback to fetch stage
        inst_buff_num_fetched++;
        // the queue cannot be empty now
        is_empty_next = `FALSE;
      end
    end
  end
  
  always_ff @(posedge clock) begin
    if (reset || fetch_flush) begin
      queue     <= `SD '0;
      head      <= `SD '0;
      tail      <= `SD INDEX_LEN'(SIZE - 1);
      is_empty  <= `SD `TRUE;
    end else begin
      queue     <= `SD queue_next;
      head      <= `SD head_next;
      tail      <= `SD tail_next;
      is_empty  <= `SD is_empty_next;
    end
  end

endmodule
