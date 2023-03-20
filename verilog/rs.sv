/* DESIGN = p rs */
`include "dispatch.svh"
`include "complete.svh"
`include "issue.svh"

// Reservation Station.
//
// Arguments:
// The input `dispatch` should contain all the information RS needed, including
// the ready bit for each source register tags.
module rs #(
  parameter D_WIDTH = 3,
  parameter C_WIDTH = 3,
  parameter I_WIDTH = 3,
  parameter SIZE = 32,
  localparam D_WIDTH_CNT_LEN = `CAL_CNT_LEN(D_WIDTH),
  localparam I_WIDTH_CNT_LEN = `CAL_CNT_LEN(I_WIDTH),
  localparam INDEX_LEN = `CAL_IDX_LEN(SIZE)
) (
  input clock, reset,

  // Dispatch
  input dispatch_packet_t [D_WIDTH-1:0] dispatch,
  // Routed to ROB for ROB to select instructions.
  output logic [D_WIDTH_CNT_LEN-1:0] dispatch_empty_slots,

  input [`SQ_SIZE-1:0] store_complete,
  input sq_idx_t store_head,
  input sq_idx_t store_tail,

  // Complete
  input complete_packet_t [C_WIDTH-1:0] complete,

  // Issue
  output issue_packet_t [I_WIDTH-1:0] issue,
  input [I_WIDTH_CNT_LEN-1:0] issue_empty_slots,

  // Rewind
  if_rewind.rs rewind
);

  // Internal representation of a RS entry. Might change in the future.
  typedef struct packed {
    dispatch_packet_t packet;
    logic load_ready;
    logic busy;
  } entry_t;

  entry_t [SIZE-1:0] data;
  entry_t [SIZE-1:0] data_next;

  // If a entry is ready *before* handling completed register.
  logic [SIZE-1:0] ready_source;
  // If a entry is ready *after* handling completed register.
  logic [SIZE-1:0] ready;

  generate
    for (genvar i = 0; i < SIZE; i++) begin
      assign ready_source[i] = data[i].packet.ready[0] & data[i].packet.ready[1] & data[i].load_ready;
    end
  endgenerate

  // Select entries to be issued.
  logic [I_WIDTH-1:0][INDEX_LEN-1:0] issue_select;
  logic [I_WIDTH-1:0] issue_select_valid;
  selector #(SIZE, I_WIDTH) issue_selector (
    .request(ready_source),
    .select(issue_select),
    .valid(issue_select_valid)
  );

  // If an entry is occupied *before* issuing.
  logic [SIZE-1:0] busy_source;

  generate
    for (genvar i = 0; i < SIZE; i++) begin
      assign busy_source[i] = data[i].busy;
    end
  endgenerate

  // Select entries as destinations of dispatched instructions.
  logic [D_WIDTH-1:0][INDEX_LEN-1:0] busy_select;
  logic [D_WIDTH-1:0] busy_select_valid;
  selector #(SIZE, D_WIDTH) busy_selector (
    .request(~busy_source),
    .select(busy_select),
    .valid(busy_select_valid)
  );

  logic [SIZE-1:0][1:0] source_completed;

  // Data path:
  // data -+-(C)-> ready -> I_sel -(I)-> busy -(D)-+
  //       |  |                                    |
  //       +--+------------------------------------+-> data_next
  //
  // This combinational logic will not form a circular circuit. C is processed
  // before I since this would makes more instructions ready so is less likely
  // to stall when issuing instructions. Similarily D is processed after I since
  // I would create more empty slots so that D is less likely to stall.
  always_comb begin
    // Set default states.
    data_next = data;
    ready = ready_source;
    dispatch_empty_slots = 0;
    source_completed = 0;
    // issue_rob_index = 0;
    // Remove any unexecuted instruction with matching ROB index.
    if (rewind.num) begin
      for (int i = 0; i < SIZE; i++) begin
        for (int j = 0; j < `WAY; j++) begin
          if (j < rewind.num && data[i].packet.rob_index == rewind.rob_index[j]) begin
            data_next[i] = 0;
          end
        end
      end
    end
    // Handle completed registers.
    for (int i = 0; i < SIZE; i++) begin
      // Update `ready` and `data_next`.
      source_completed[i][0] = data[i].packet.ready[0];
      source_completed[i][1] = data[i].packet.ready[1];
      for (int k = 0; k < C_WIDTH; k++) begin
        if (complete[k].phy_dest_reg.valid) begin
          // If any of the completed tag change a entry to be ready, the set
          // corresponding bit in `ready`.
          if (data_next[i].packet.phy_src_reg[0] == complete[k].phy_dest_reg) begin
            data_next[i].packet.ready[0] = `TRUE;
            source_completed[i][0] = `TRUE;
          end
          if (data_next[i].packet.phy_src_reg[1] == complete[k].phy_dest_reg) begin
            data_next[i].packet.ready[1] = `TRUE;
            source_completed[i][1] = `TRUE;
          end
        end
      end
      if (source_completed[i][0] && source_completed[i][1]) begin
        ready[i] = `TRUE;
      end
    end
    // Select and issue instructions.
    for (int k = 0; k < I_WIDTH; k++) begin
      issue[k] = 0;
      if (issue_select_valid[k] && k < issue_empty_slots) begin
        issue[k].decoded_inst = data[issue_select[k]].packet.decoded_inst;
        issue[k].phy_src_reg = data[issue_select[k]].packet.phy_src_reg;
        issue[k].phy_dest_reg = data[issue_select[k]].packet.phy_dest_reg;
        issue[k].valid = `TRUE;
        issue[k].rob_index = data[issue_select[k]].packet.rob_index;
        issue[k].pc = data[issue_select[k]].packet.pc;
        issue[k].sq_index = data[issue_select[k]].packet.sq_index;
        data_next[issue_select[k]] = 0;
      end
    end
    // Count number of empty slots and notify ROB to dispatch instructions.
    for (int k = 0; k < D_WIDTH; k++) begin
      if (busy_select_valid[k]) begin
        dispatch_empty_slots++;
      end
    end
    // Select empty slots and put instructions in them.
    for (int k = 0; k < D_WIDTH; k++) begin
      if (dispatch[k].valid && busy_select_valid[k]) begin
        data_next[busy_select[k]].packet = dispatch[k];
        data_next[busy_select[k]].busy = `TRUE;
        data_next[busy_select[k]].load_ready = `TRUE;
      end
    end
    for (int i = 0; i < SIZE; i++) begin
      if (data_next[i].packet.decoded_inst.fu_type == FU_MEM
          && data_next[i].packet.decoded_inst.fu_func.mem.rw == FU_MEM_READ) begin
        data_next[i].load_ready = `TRUE;
        for (int j = 0; j < `SQ_SIZE; j++) begin
          if ((store_head + j) % `SQ_SIZE == data_next[i].packet.sq_index) begin
            break;
          end
          if (store_complete[(store_head + j) % `SQ_SIZE] == `FALSE) begin
            data_next[i].load_ready = `FALSE;
          end
        end
      end
    end
  end

  // synopsys sync_set_reset "reset"
  always_ff @(posedge clock) begin
    if (reset)
      data <= `SD 0;
    else
      data <= `SD data_next;
  end
endmodule
