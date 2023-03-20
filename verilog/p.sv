/* DESIGN = p */
`include "dispatch.svh"
`include "issue.svh"
`include "complete.svh"
`include "execute.svh"
`include "fetch.svh"

// Core
module p (
  input clock, reset,
  input [3:0] mem2proc_response,
  input [63:0] mem2proc_data,
  input [3:0] mem2proc_tag,
  
  output logic [1:0]  proc2mem_command,
  output xlen_t       proc2mem_addr,
  output logic [63:0] proc2mem_data,
  // output mem_size_e   proc2mem_size,

  /* special I/O for testbench */
  // this is for outputting PCs of dispatched instr.s
  output logic          [`WAY_CNT_LEN-1:0]          dispatch_instr_num,
  output PC_t           [`WAY-1:0]                  dispatch_instr_PC,
  output rob_idx_t      [`WAY-1:0]                  dispatch_instr_rob_idx,

  // this is for outputting data of retired instr.s
  output logic          [`WAY_CNT_LEN-1:0]          retire_instr_num,
  output arch_reg_idx_t [`WAY-1:0]                  retire_arch_reg_idx,
  output xlen_t         [`WAY-1:0]                  retire_arch_reg_data,
  // this is for outputting error code of retired instr.s
  output exception_code_e                           error_status
);
  // F
  fetch_packet_t [`WAY-1:0] direct_fetch;
  fetch_packet_t [`WAY-1:0] buffer_fetch;
  logic fetch_flush;  // high if there is a new PC
  logic [`WAY_CNT_LEN-1:0] dispatch_stage_num_can_fetch;
  logic [`WAY_CNT_LEN-1:0] inst_buff_num_fetched;

  logic [`WAY-1:0] pc_find_valid;
  PC_t [`WAY-1:0] pc_find;

  logic [`WAY-1:0] predict_taken;
  PC_t [`WAY-1:0] predict_pc;

  // D
  if_dispatch it_dispatch ();
  assign dispatch_instr_num = it_dispatch.num_dispatched_inst;
  generate
    for (genvar i = 0; i < `WAY; i++) begin
      assign dispatch_instr_PC[i]  = buffer_fetch[i].PC;
    end
  endgenerate
  assign dispatch_instr_rob_idx = it_dispatch.rob_index;
  dispatch_packet_t [`WAY-1:0] dispatch;

  logic [`WAY_CNT_LEN-1:0] dispatch_empty_slots;

  if_rename rename ();

  if_prepare prepare ();

  // C
  complete_packet_t [`WAY-1:0] complete;
  phy_reg_idx_t [`WAY-1:0] complete_dest_reg_tag;

  generate
    for (genvar i = 0; i < `WAY; i++) begin
      assign complete_dest_reg_tag[i] = complete[i].phy_dest_reg.index;
    end
  endgenerate

  // I
  issue_packet_t [`WAY-1:0] issue;
  logic [`WAY_CNT_LEN-1:0]  issue_empty_slots;

  // E
  execute_packet_t [`NUM_FU_TYPE-1:0][`WAY-1:0] execute;
  logic [`NUM_FU_TYPE-1:0][`WAY_CNT_LEN-1:0]    execute_empty_slots;
  result_packet_t [`NUM_FU_TYPE-1:0][`WAY-1:0] result;
  logic [`NUM_FU_TYPE-1:0][`WAY-1:0] execute_stall;

  // Memory
  logic [`SQ_SIZE-1:0] store_complete;
  sq_idx_t store_head;
  sq_idx_t store_tail;
  logic store_flush;
  logic [`WAY_CNT_LEN-1:0] store_empty_slots;
  logic [`WAY_CNT_LEN-1:0] store_valid_count;
  store_request_t [0:0] store_request;
  load_request_t [0:0] load_request;
  load_result_t [0:0] load_result;

  // Resolve
  if_resolve #(.WIDTH(1)) resolve ();
  if_update #(.WIDTH(3)) update ();

  // R
  if_retire retire ();
  assign retire_instr_num = retire.instr_num;
  assign retire_arch_reg_idx = retire.arch_dest_reg;

  // Rewind
  if_rewind rewind ();
  PC_t rewind_target_PC;

  phy_reg_tag_t [`WAY-1:0][1:0] reg_file_read_tag;
  xlen_t [`WAY-1:0][1:0] reg_file_read_value;

  phy_reg_tag_t [`WAY-1:0] reg_file_write_tag;
  xlen_t [`WAY-1:0] reg_file_write_value;

  regfile #(
    .SIZE(`PHY_REG_SIZE),
    .R_WIDTH(2 * `WAY),
    .W_WIDTH(`WAY)
  ) prf (
    .clock(clock),
    .reset(reset),
    // R
    .read_tag(reg_file_read_tag),
    .read_value(reg_file_read_value),

    // W
    .write_tag(reg_file_write_tag),
    .write_value(reg_file_write_value),

    // Retire
    .retire_read_tag(retire.T),
    .retire_read_value(retire_arch_reg_data)
  );

  branch_predictor pbp(
    .clock(clock),
    .reset(reset),

    .pc_find_valid(pc_find_valid),
    .pc_find(pc_find),

    .resolve(resolve),
    .update(update),

    .predict_result(predict_taken),
    .target_pc_output(predict_pc)
  );

  logic [1:0]  Dcache2Dmem_command;
  PC_t         Dcache2Dmem_addr;
  logic [63:0] Dcache2Dmem_data;
	logic [3:0]  Dmem2Dcache_response;
	logic [63:0] Dmem2Dcache_data;
	logic [3:0]  Dmem2Dcache_tag;

	logic [1:0]  Icache2Imem_command;
	PC_t         Icache2Imem_addr;
	logic [3:0]  Imem2Icache_response;
	logic [63:0] Imem2Icache_data;
	logic [3:0]  Imem2Icache_tag;

  PC_t [`WAY-1:0] proc2Icache_addr;
  inst_t [`WAY-1:0] Icache2proc_inst;
  logic Icache2proc_valid;

  mem_ctrl pmc(
    .clock(clock),
    .reset(reset),

    .mem2ctrl_response(mem2proc_response),
    .mem2ctrl_data(mem2proc_data),
    .mem2ctrl_tag(mem2proc_tag),

    .ctrl2mem_addr(proc2mem_addr),
    .ctrl2mem_data(proc2mem_data),
    .ctrl2mem_command(proc2mem_command),

    .Dcache2Dmem_command(Dcache2Dmem_command),
    .Dcache2Dmem_addr(Dcache2Dmem_addr),
    .Dcache2Dmem_data(Dcache2Dmem_data),
    .Dmem2Dcache_response(Dmem2Dcache_response),
    .Dmem2Dcache_data(Dmem2Dcache_data),
    .Dmem2Dcache_tag(Dmem2Dcache_tag),

    .Icache2Imem_command(Icache2Imem_command),
    .Icache2Imem_addr(Icache2Imem_addr),
    .Imem2Icache_response(Imem2Icache_response),
    .Imem2Icache_data(Imem2Icache_data),
    .Imem2Icache_tag(Imem2Icache_tag)
  );

  icache_bank pic(
    .clock(clock),
    .reset(reset),

    .Imem2Icache_response(Imem2Icache_response),
    .Imem2Icache_data(Imem2Icache_data),
    .Imem2Icache_tag(Imem2Icache_tag),

    .proc2Icache_addr(proc2Icache_addr),

    .Icache2Imem_command(Icache2Imem_command),
    .Icache2Imem_addr(Icache2Imem_addr),

    .Icache_inst_out(Icache2proc_inst),
    .Icache_valid_out(Icache2proc_valid)
  );

  logic [1:0] proc2Dcache_load_en;
  PC_t [1:0] proc2Dcache_addr_load;
  PC_t proc2Dcache_addr_store;
  xlen_t proc2Dcache_data_store;
  logic Dcache_store_en;
  logic Dcache_store_is_32_bit;
  logic Dcache_store_is_16_bit;
  logic [1:0] [63:0] Dcache2proc_data;
  logic [1:0] Dcache2proc_valid;
  logic Dcache2proc_store_accepted;
  logic [1:0] Dcache2proc_load_accepted;

  assign proc2Dcache_addr_load[1] = 0;
  assign proc2Dcache_load_en[1] = 0;

  cache_ctrl pcc(
    .clock(clock),
    .reset(reset),
    .flush(store_flush),

    .Dmem2Dcache_response(Dmem2Dcache_response),
    .Dmem2Dcache_data(Dmem2Dcache_data),
    .Dmem2Dcache_tag(Dmem2Dcache_tag),

    .proc2Dcache_addr_load(proc2Dcache_addr_load),
    .load_en(proc2Dcache_load_en),

    .proc2Dcache_addr_store(proc2Dcache_addr_store),
    .proc2Dcache_data_store(proc2Dcache_data_store),
    .store_en(Dcache_store_en),
    .is_32_bit(Dcache_store_is_32_bit),
    .is_16_bit(Dcache_store_is_16_bit),

    .Dcache2Dmem_command(Dcache2Dmem_command),
    .Dcache2Dmem_addr(Dcache2Dmem_addr),
    .Dcache2Dmem_data(Dcache2Dmem_data),

    .Dcache_data_out(Dcache2proc_data),
    .Dcache_valid_out(Dcache2proc_valid),

    .load_accepted(Dcache2proc_load_accepted),
    .store_accepted(Dcache2proc_store_accepted)
  );

  fetch_stage pfs(
    .clock(clock),
    .reset(reset),

    .fetch_flush(fetch_flush),
    .branch_target_PC(rewind_target_PC),

    .pc_find_valid(pc_find_valid[0]),
    .pc_find(pc_find[0]),

    .predict_result(predict_taken[0]),
    .predict_target_pc(predict_pc[0]),

    .Imem2proc_data(Icache2proc_inst),
    .Imem2proc_valid(Icache2proc_valid),
    .proc2Imem_addr(proc2Icache_addr),

    .fetch_out(direct_fetch),
    .inst_buff_num_fetched(inst_buff_num_fetched)
  );

  inst_buff #(
    .SIZE(12)
  ) pib (
    .clock(clock),
    .reset(reset),
    .fetch_flush(fetch_flush),
    .fetch_in(direct_fetch),
    .inst_buff_out(buffer_fetch),
    .dispatch_stage_num_can_fetch(dispatch_stage_num_can_fetch),
    .store_empty_slots(store_empty_slots),
    .store_valid_count(store_valid_count),
    .inst_buff_num_fetched(inst_buff_num_fetched)
  );

  map_table pmt(
    .clock(clock),
    .reset(reset),

    .prepare(prepare),

    .CDB_tag(complete_dest_reg_tag),

    .rewind(rewind)
  );

  freelist pfl(
    .clock(clock),
    .reset(reset),

    .rename(rename),

    .retire(retire),

    .rewind(rewind)
  );


  dispatch_stage pds (
    .clock(clock),
    .reset(reset),
    //.fetch_stall(fetch_stall),

    .inst_buff_out(buffer_fetch),
    .dispatch_stage_num_can_fetch(dispatch_stage_num_can_fetch),

    .it_dispatch(it_dispatch),

    .dispatch(dispatch),
    .dispatch_empty_slots(dispatch_empty_slots),

    .store_tail_index(store_tail),

    .rename(rename),

    .prepare(prepare)
  );

  rob prob(
    .clock(clock),
    .reset(reset),

    // Dispatch
    .it_dispatch(it_dispatch),

    // Rewind
    .rewind(rewind),

    .rewind_target_PC(rewind_target_PC),
    .fetch_flush(fetch_flush),
    .store_flush(store_flush),

    .complete(complete),

    .resolve(resolve),
    .update(update),

    // retire
    .retire(retire),
    .exception_code(error_status)
  );

  rs #(
    .D_WIDTH(`WAY),
    .C_WIDTH(`WAY),
    .I_WIDTH(`WAY),
    .SIZE(16)
  ) prs (
    .clock(clock),
    .reset(reset),

    .dispatch(dispatch),
    .store_complete(store_complete),
    .store_tail(store_tail),
    .store_head(store_head),
    .dispatch_empty_slots(dispatch_empty_slots),

    .complete(complete),

    .issue(issue),
    .issue_empty_slots(issue_empty_slots),

    .rewind(rewind)
  );

  issue_queue #(
    .I_WIDTH(`WAY),
    .SIZE(6)
  ) piq (
    .clock(clock),
    .reset(reset),
    .flush(store_flush),

    .execute(execute),
    .execute_empty_slots(execute_empty_slots),

    .issue(issue),
    .issue_empty_slots(issue_empty_slots),

    .reg_file_read_tag(reg_file_read_tag),
    .reg_file_read_value(reg_file_read_value)
  );

  // temporarily disable memory FU
  fu_mem pfme (
    .clock(clock),
    .reset(reset),
    .flush(store_flush),

    .execute(execute[FU_MEM][0]),
    .result(result[FU_MEM][0]),
    .execute_empty_slots(execute_empty_slots[FU_MEM]),

    .store_request(store_request),
    .load_request(load_request),
    .load_result(load_result),

    .load_addr(proc2Dcache_addr_load[0]),
    .load_en(proc2Dcache_load_en[0]),
    .load_data(Dcache2proc_data[0]),
    .load_valid(Dcache2proc_valid[0]),
    .load_accepted(Dcache2proc_load_accepted[0])
  );

  fu_mult #(
    .NUM_STAGE(4),
    .I_WIDTH(`WAY),
    .E_WIDTH(`WAY)
  ) pfmu (
    .clock(clock),
    .reset(reset),

    .execute(execute[FU_INT_MULT][`WAY-1:0]),
    .result(result[FU_INT_MULT][`WAY-1:0]),
    .execute_empty_slots(execute_empty_slots[FU_INT_MULT])
  );

  // assign result[FU_INT_MULT][1] = 0;
  // assign result[FU_INT_MULT][2] = 0;

  fu_fast_int #(
    .I_WIDTH(`WAY),
    .E_WIDTH(`WAY)
  ) pffi (
    .clock(clock),
    .reset(reset),
    .flush(store_flush),

    .execute(execute[FU_INT_FAST][`WAY-1:0]),
    .result(result[FU_INT_FAST][`WAY-1:0]),
    .execute_empty_slots(execute_empty_slots[FU_INT_FAST])
  );

  fu_branch #(
    .I_WIDTH(1),
    .E_WIDTH(1)
  ) pfb (
    .clock(clock),
    .reset(reset),

    .execute(execute[FU_BRANCH][0]),
    .result(result[FU_BRANCH][0]),
    .execute_empty_slots(execute_empty_slots[FU_BRANCH][0]), // since there is only one branch FU

    .resolve(resolve)
  );

  assign execute_empty_slots[FU_BRANCH][`WAY_CNT_LEN-1:1] = '0;
  assign result[FU_BRANCH][1] = 0;
  assign result[FU_BRANCH][2] = 0;

  sq psq (
    .clock(clock),
    .reset(reset),
    .flush(store_flush),

    .store_accepted(Dcache2proc_store_accepted),

    .retire(retire),

    .complete(complete),
    .store_complete(store_complete),

    .fu_store(store_request),
    .fu_load_query(load_request),

    .dispatch_valid_count(store_valid_count),
    .head_index(store_head),
    .tail_index(store_tail),
    .dispatch_empty_slots(store_empty_slots),

    .fu_load_result(load_result),

    .proc2Dcache_addr_store(proc2Dcache_addr_store),
    .proc2Dcache_data_store(proc2Dcache_data_store),
    .store_en(Dcache_store_en),
    .is_32_bit(Dcache_store_is_32_bit),
    .is_16_bit(Dcache_store_is_16_bit)
  );

  cq #(
    .C_WIDTH(`WAY),
    .E_WIDTH(`NUM_FU_TYPE * `WAY),
    .SIZE(16)
  ) pcq (
    .clock(clock),
    .reset(reset),
    .flush(store_flush),

    .execute(result),
    .stall(execute_stall),

    .complete(complete),

    .reg_file_write_tag(reg_file_write_tag),
    .reg_file_write_value(reg_file_write_value)
  );
endmodule
