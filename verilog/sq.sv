/* DESIGN = p fu_mem */
`include "sys_defs.svh"
`include "issue.svh"
`include "execute.svh"
`include "complete.svh"
`include "retire.svh"

`timescale 1ns/100ps

// Conservative Load Scheduling.
//
// Load FU needs to keep the query when the response are invalid.
module sq #(
  C_WIDTH = `WAY,
  D_WIDTH = `WAY,
  E_WIDTH = 1,
  SIZE    = `SQ_SIZE
) (
  input   clock, reset, flush,

  // From D$/CC
  input   logic store_accepted,

  if_retire.sq retire,

  input   complete_packet_t [C_WIDTH-1:0]   complete,
  output  logic             [SIZE-1:0]      store_complete,

  // From FU
  input   store_request_t   [E_WIDTH-1:0]   fu_store,
  input   load_request_t    [E_WIDTH-1:0]   fu_load_query,

  // From dispatch
  // It's assumed that this is less than `dispatch_empty_slots`
  input   [`WAY_CNT_LEN-1:0]                dispatch_valid_count,

  // To dispatch
  // Note that dispatch needs to compute instruction's correct `tail_idx` on its own
  output  sq_idx_t                          head_index,
  output  sq_idx_t                          tail_index,  // Tail index *before* allocating
  output  logic [`WAY_CNT_LEN-1:0]          dispatch_empty_slots,

  // To FU, Load logic
  output  load_result_t     [E_WIDTH-1:0]   fu_load_result,

  // To D$/CC
  output  PC_t                              proc2Dcache_addr_store,
  output  xlen_t                            proc2Dcache_data_store,
  output  logic                             store_en,
  output  logic                             is_32_bit,
  output  logic                             is_16_bit
);

  typedef struct packed {
    fu_mem_write_func_e func;
    PC_t                addr;
    xlen_t              data;
    logic valid;
  } sq_entry_t;

  sq_entry_t  [SIZE-1:0]  sq, sq_next;
  sq_idx_t                head, head_next;
  sq_idx_t                tail, tail_next;
  logic                   empty, empty_next;

  sq_entry_t              temp_sq_entry;
  sq_idx_t                temp_sq_idx;
  load_request_t          temp_load_query;

  logic store_en_prev;
  logic is_32_bit_prev;
  logic is_16_bit_prev;

  assign retire.store_accepted = store_accepted;

  always_comb begin
    sq_next     = sq;
    head_next   = head;
    tail_next   = tail;
    empty_next  = empty;
    
    temp_sq_entry           = 0;
    temp_sq_idx             = 0;
    temp_load_query         = 0;

    fu_load_result          = 0;

    proc2Dcache_addr_store  = 0;
    proc2Dcache_data_store  = 0;
    store_en                = store_en_prev;
    is_32_bit = is_32_bit_prev;
    is_16_bit = is_16_bit_prev;

    if (flush) begin
      sq_next = 0;
      head_next = 0;
      tail_next = 0;
      empty_next = `TRUE;
      store_en = `FALSE;
      is_32_bit = `FALSE;
      is_16_bit = `FALSE;
    end

    // Retire: Advance head pointer
    if (store_en || (!store_en && empty_next == `FALSE && retire.is_store)) begin
      proc2Dcache_addr_store = sq_next[head_next].addr;
      proc2Dcache_data_store = sq_next[head_next].data;
      store_en = `TRUE;
      is_32_bit = `FALSE;
      is_16_bit = `FALSE;
      case (sq_next[head_next].func)
        FU_SB: begin end
        FU_SH: begin
          is_16_bit = `TRUE;
        end
        FU_SW: begin
          is_32_bit = `TRUE;
        end
      endcase
      if (store_accepted) begin
        store_en = `FALSE;
        sq_next[head_next] = 0;
        head_next = (head_next + 1) % SIZE;
        if (head_next == tail_next) begin
          empty_next = `TRUE;
        end
      end
    end

    // Execute: Write in computed store address and data
    for (int i = 0; i < E_WIDTH; i++) begin
      if (fu_store[i].valid) begin
        sq_next[fu_store[i].sq_index].valid     = `TRUE;
        sq_next[fu_store[i].sq_index].func      = fu_store[i].func;
        sq_next[fu_store[i].sq_index].addr      = fu_store[i].addr;
        sq_next[fu_store[i].sq_index].data      = fu_store[i].data;
      end
    end

    for (int i = 0; i < SIZE; i++) begin
      store_complete[i] = sq_next[i].valid;
    end
    head_index = head_next;

    for (int i = 0; i < E_WIDTH; i++) begin
      if (fu_load_query[i].valid) begin
        // For each entry from head to the load idx...
        for (int j = 0; j < SIZE; j++) begin
          temp_sq_idx     = (head_next + j) % SIZE;
          temp_sq_entry   = sq_next[temp_sq_idx];
          temp_load_query = fu_load_query[i];
          if (temp_sq_idx == temp_load_query.sq_index) break;

          if (temp_sq_entry.valid == `TRUE && temp_sq_entry.addr[31:2] == temp_load_query.addr[31:2]) begin
            fu_load_result[i].valid = `TRUE;
            case (temp_sq_entry.func)
              FU_SB: begin
                fu_load_result[i].data[7:0] = temp_sq_entry.data[(temp_sq_entry.addr[1:0] * 8)+:8];
                fu_load_result[i].mask |= 32'h000000FF;
              end
              FU_SH: begin
                fu_load_result[i].data[15:0] = temp_sq_entry.data[(temp_sq_entry.addr[1] * 16)+:16];
                fu_load_result[i].mask |= 32'h0000FFFF;
              end
              FU_SW: begin
                fu_load_result[i].valid = `TRUE;
                fu_load_result[i].data = temp_sq_entry.data;
                fu_load_result[i].mask |= 32'hFFFFFFFF;
              end
            endcase
          end
        end
      end
    end

    // Dispatch: Compute capacity *after* completing
    dispatch_empty_slots = 0;
    if (empty_next) begin
      dispatch_empty_slots = `WAY;
    end else if (tail_next > head_next) begin
      dispatch_empty_slots = SIZE - tail_next + head_next > `WAY ?
        SIZE - tail_next + head_next : 0;
    end else begin
      dispatch_empty_slots = head_next - tail_next > `WAY ?
        head_next - tail_next : 0;
    end
    tail_index = tail_next;

    // Dispatch: Advance tail pointer to allocate
    for (int i = 0; i < D_WIDTH; i++) begin
      if (i < dispatch_valid_count) begin
        sq_next[tail_next] = 0;
        tail_next = (tail_next + 1) % SIZE;
        empty_next = `FALSE;
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      sq    <= `SD 0;
      head  <= `SD 0;
      tail  <= `SD 0;
      empty <= `SD `TRUE;
      store_en_prev   <= `SD `FALSE;
      is_32_bit_prev  <= `SD `FALSE;
      is_16_bit_prev  <= `SD `FALSE;
    end else begin
      sq    <= `SD sq_next;
      head  <= `SD head_next;
      tail  <= `SD tail_next;
      empty <= `SD empty_next;
      store_en_prev   <= `SD store_en;
      is_32_bit_prev  <= `SD is_32_bit;
      is_16_bit_prev  <= `SD is_16_bit;
    end
  end
endmodule
