`ifndef __FU_MACRO_SVH__
`define __FU_MACRO_SVH__

`define DEF_FU(NAME, INNER_MODULE)                        \
module fu_``NAME #(                                       \
  parameter I_WIDTH = `WAY,                               \
  parameter E_WIDTH = `WAY,                               \
  localparam I_WIDTH_CNT_LEN = `CAL_CNT_LEN(I_WIDTH)      \
) (                                                       \
  input   clock, reset, flush,                            \
  input   execute_packet_t  [I_WIDTH-1:0]                 execute,              \
  output  result_packet_t   [E_WIDTH-1:0]                 result,               \
  output  logic             [I_WIDTH_CNT_LEN-1:0]         execute_empty_slots   \
);                                                        \
  execute_packet_t  [E_WIDTH-1:0] execute_data;           \
  xlen_t            [E_WIDTH-1:0] alu_result;             \
  logic             [E_WIDTH-1:0] alu_done, alu_start;    \
  wire              [E_WIDTH-1:0] alu_busy;               \
  logic             [E_WIDTH-1:0] slot_empty;             \
  logic             [I_WIDTH-1:0] input_assigned;         \
  execute_packet_t  [E_WIDTH-1:0] next_execute_data;      \
  logic             [E_WIDTH-1:0] next_alu_start;         \
  generate                                                \
    for (genvar i = 0; i < E_WIDTH; ++i) begin            \
      ``INNER_MODULE ``INNER_MODULE``_0 (                 \
        .clock(clock),                                    \
        .reset(reset),                                    \
        .start(alu_start[i]),                             \
        .opa(execute_data[i].opa),                        \
        .opb(execute_data[i].opb),                        \
        .fu_func(execute_data[i].decoded_inst.fu_func),   \
        .result(alu_result[i]),                           \
        .done(alu_done[i])                                \
      );                                                  \
      assign alu_busy[i]  = execute_data[i].valid ?       \
                            ~alu_done[i] : `FALSE;        \
    end                                                   \
  endgenerate                                             \
  always_comb begin                                       \
    slot_empty          = ~alu_busy;                      \
    input_assigned      = 0;                              \
    execute_empty_slots = 0;                              \
    next_execute_data   = execute_data;                   \
    next_alu_start      = 0;                              \
    result              = 0;                              \
    for (int i = 0; i < E_WIDTH; ++i) begin               \
      if (execute_data[i].valid & alu_done[i]) begin      \
        result[i].phy_dest_reg = execute_data[i].phy_dest_reg;  \
        result[i].result = alu_result[i];                       \
        result[i].rob_index = execute_data[i].rob_index;        \
        result[i].valid = `TRUE;                                \
        next_execute_data[i] = 0;                               \
      end                                                 \
    end                                                   \
    for (int i = 0; i < E_WIDTH; ++i)                     \
      if (~alu_busy[i])                                   \
        execute_empty_slots += 1;                         \
    for (int j = 0; j < I_WIDTH; ++j) begin               \
      if (execute[j].valid) begin                         \
        for (int i = 0; i < E_WIDTH; ++i) begin           \
          if (slot_empty[i] & ~input_assigned[j]) begin   \
            next_execute_data[i]  = execute[j];           \
            next_alu_start[i]     = `TRUE;                \
            slot_empty[i]         = `FALSE;               \
            input_assigned[j]     = `TRUE;                \
          end                                             \
        end                                               \
      end                                                 \
    end                                                   \
    if (flush) begin \
      result = 0; \
    end \
  end                                                     \
  always_ff @(posedge clock) begin                        \
    if (reset || flush) begin                             \
      execute_data  <= `SD 0;                             \
      alu_start     <= `SD 0;                             \
    end else begin                                        \
      execute_data  <= `SD next_execute_data;             \
      alu_start     <= `SD next_alu_start;                \
    end                                                   \
  end                                                     \
endmodule

`endif  // __FU_MACRO_SVH__
