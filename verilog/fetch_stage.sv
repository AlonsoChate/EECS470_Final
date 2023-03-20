/* DESIGN = p */
`include "fetch.svh"
`include "sys_defs.svh"

module fetch_stage(
  input clock, reset,
  // Resolve
  input fetch_flush,
  input PC_t branch_target_PC,

  // Predict
  output logic pc_find_valid,
  output PC_t pc_find,
  input logic predict_result,
  input PC_t predict_target_pc,

  // Memory (I-Cache)
  input inst_t [`WAY-1:0] Imem2proc_data,
  input logic Imem2proc_valid,
  output PC_t [`WAY-1:0]  proc2Imem_addr,

  // Fetch
  output fetch_packet_t [`WAY-1:0]  fetch_out,
  input  [`WAY_CNT_LEN-1:0]         inst_buff_num_fetched
);
  PC_t pc;
  PC_t pc_next;

  generate
    for (genvar i = 0; i < `WAY; i++) begin
      assign proc2Imem_addr[i] = pc + i * 4;
    end
  endgenerate

  always_comb begin
    pc_find_valid = 0;
    pc_find = 0;
    fetch_out = 0;

    if (Imem2proc_valid) begin
      for (int unsigned i = 0; i < `WAY; i++) begin
        // currently output instruction will always be `TRUE FOR NOW
        // might well be changed after Icache is added
        fetch_out[i].valid = `TRUE;
        fetch_out[i].PC  = pc + i * 4;

        // fetch 3 instruction in one cycle for now
        fetch_out[i].inst = Imem2proc_data[i];

        if (pc_find_valid == `FALSE) begin
          casez (fetch_out[i].inst)
            `RV32_BEQ,
            `RV32_BNE,
            `RV32_BLT,
            `RV32_BGE,
            `RV32_BLTU,
            `RV32_BGEU,
            `RV32_JAL,
            `RV32_JALR: begin
              pc_find_valid = `TRUE;
              pc_find = pc + i * 4;
              fetch_out[i].target_pc = predict_target_pc;
              fetch_out[i].taken = predict_result;
            end
          endcase
        end else begin
          fetch_out[i].valid = `FALSE;
        end
      end
    end

    pc_next = pc + inst_buff_num_fetched * 4;

    if (fetch_flush) begin
      pc_next = branch_target_PC;
    end else if (pc_find_valid) begin
      if (predict_result) begin
        if (pc_find < pc_next) begin
          pc_next = predict_target_pc;
        end
      end else begin
        if (pc_find + 4 < pc_next) begin
          pc_next = pc_find + 4;
        end
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      pc <= `SD PC_t'(0);
    end else begin
      pc <= `SD pc_next;
    end
  end
endmodule
