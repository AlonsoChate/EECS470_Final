/////////////////////////////////////////////////////////////////////////
//                                                                     //
//                                                                     //
//   Modulename :  testbench.v                                         //
//                                                                     //
//  Description :  Testbench module for the verisimple pipeline;       //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////
/* SOURCE = p.sv branch_predictor.sv twobc.sv selector.sv rs.sv rob.sv freelist.sv map_table.sv dispatch_stage.sv cq.sv decoder.sv fetch_stage.sv fu.sv inst_buff.sv issue_queue.sv mult.sv regfile.sv bank_icache.sv mem_ctrl.sv dcache.sv mem.sv cache_ctrl.sv sq.sv */

`timescale 1ns/100ps

`include "sys_defs.svh"

module testbench;

	// variables used in the testbench
	logic        clock;
	logic        reset;
	logic [31:0] clock_count;
	logic [31:0] instr_count;
	int          wb_fileno;

	logic [1:0]  proc2mem_command;
	logic [`XLEN-1:0] proc2mem_addr;
	logic [63:0] proc2mem_data;
	logic [3:0] mem2proc_response;
	logic [63:0] mem2proc_data;
	logic [3:0] mem2proc_tag;
`ifndef CACHE_MODE
	MEM_SIZE     proc2mem_size;
`endif
  // variables for storing PCs of dispatched instr.s
  logic          [`CAL_IDX_LEN(`WAY+1)-1:0]   pipeline_dispatch_instr_num;
  PC_t           [`WAY-1:0]                   pipeline_dispatch_instr_PC;
  rob_idx_t      [`WAY-1:0]                   pipeline_dispatch_instr_rob_idx;

  logic          [`CAL_IDX_LEN(`WAY+1)-1:0]   pipeline_retire_instr_num;
  arch_reg_idx_t [`WAY-1:0]                   pipeline_retire_arch_reg_idx;
  xlen_t         [`WAY-1:0]                   pipeline_retire_arch_reg_data;
	exception_code_e                            pipeline_error_status;

  real rob_occupancy;
  int rob_stat_count;

  int resolve_correct_count;
  int resolve_total_count;

	// Instantiate the Pipeline
	`DUT(p) core(
		// Inputs
		.clock             (clock),
		.reset             (reset),
		.mem2proc_response (mem2proc_response),
		.mem2proc_data     (mem2proc_data),
		.mem2proc_tag      (mem2proc_tag),

		// Outputs
		.proc2mem_command  (proc2mem_command),
		.proc2mem_addr     (proc2mem_addr),
		.proc2mem_data     (proc2mem_data),
		// .proc2mem_size     (proc2mem_size),

    .dispatch_instr_num(pipeline_dispatch_instr_num),
    .dispatch_instr_PC(pipeline_dispatch_instr_PC),
    .dispatch_instr_rob_idx(pipeline_dispatch_instr_rob_idx),

		.retire_instr_num(pipeline_retire_instr_num),
    .retire_arch_reg_idx(pipeline_retire_arch_reg_idx),
    .retire_arch_reg_data(pipeline_retire_arch_reg_data),
		.error_status(pipeline_error_status)
	);

	// Instantiate the Data Memory
	mem memory (
		// Inputs
		.clk               (clock),
		.proc2mem_command  (proc2mem_command),
		.proc2mem_addr     (proc2mem_addr),
		.proc2mem_data     (proc2mem_data),
`ifndef CACHE_MODE
		.proc2mem_size     (proc2mem_size),
`endif

		// Outputs
		.mem2proc_response (mem2proc_response),
		.mem2proc_data     (mem2proc_data),
		.mem2proc_tag      (mem2proc_tag)
	);

	// Generate System Clock
	always begin
		#(`VERILOG_CLOCK_PERIOD/2.0);
		clock = ~clock;
	end

  task show_rob_occupancy;
    begin
      $display("@@ Average ROB occupancy: %4.2f", rob_occupancy * 100.00);
    end
  endtask

  task show_bp_accuracy;
    begin
      $display("@@ Branch preduction accuracy: %4.2f", real'(resolve_correct_count) / resolve_total_count * 100.00);
    end
  endtask

	// Task to display # of elapsed clock edges
	task show_clk_count;
		real cpi;

		begin
			cpi = (clock_count + 1.0) / instr_count;
			$display("@@  %0d cycles / %0d instrs = %f CPI\n@@",
			          clock_count+1, instr_count, cpi);
			$display("@@  %4.2f ns total time to execute\n@@\n",
			          clock_count*`VERILOG_CLOCK_PERIOD);
		end
	endtask  // task show_clk_count

	// Show contents of a range of Unified Memory, in both hex and decimal
	task show_mem_with_decimal;
		input [31:0] start_addr;
		input [31:0] end_addr;
		int showing_data;
		begin
			$display("@@@");
			showing_data=0;
			for(int k=start_addr;k<=end_addr; k=k+1)
				if (memory.unified_memory[k] != 0) begin
					$display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
				                                           memory.unified_memory[k]);
					showing_data=1;
				end else if(showing_data!=0) begin
					$display("@@@");
					showing_data=0;
				end
			$display("@@@");
		end
	endtask  // task show_mem_with_decimal

	initial begin
		clock = 1'b0;
		reset = `FALSE;

		// Pulse the reset signal
		$display("@@\n@@\n@@  %t  Asserting System reset......", $realtime);
		reset = `TRUE;
		@(posedge clock);
		@(posedge clock);

		$readmemh("program.mem", memory.unified_memory);

		@(posedge clock);
		@(posedge clock);
		`SD;
		// This reset is at an odd time to avoid the pos & neg clock edges

		reset = `FALSE;
		$display("@@  %t  Deasserting System reset......\n@@\n@@", $realtime);

		wb_fileno = $fopen("writeback.out");
	end

`ifndef NDEBUG
  always @(posedge clock) begin
    $display("@@  clock: %d, instruction: %d", clock_count, instr_count);
    $display("MEM: req: %h, addr: %h, data: %h",
      core.proc2mem_command,
      core.proc2mem_addr,
      core.proc2mem_data);
    $display("MEM: res: %h, addr: %h, data: %h",
      core.mem2proc_response,
      core.mem2proc_data,
      core.mem2proc_tag);
    $display("I$: req: %h, addr: %h",
      core.pic.Icache2Imem_command,
      core.pic.Icache2Imem_addr);
    $display("I$: res: %h, inst: %h",
      core.pic.Icache_valid_out,
      core.pic.Icache_inst_out);
    $display("FS: flush: %d, numF: %d, mem_valid: %h", core.pfs.fetch_flush, core.pfs.inst_buff_num_fetched, core.pfs.Imem2proc_valid);
    $display("BP: predict: valid: %h, source: %h, taken: %h, target: %h",
      core.pfs.pc_find_valid,
      core.pfs.pc_find,
      core.pfs.predict_result,
      core.pfs.predict_target_pc);
    for (int i = 0; i < core.pbp.resolve.WIDTH; i++) begin
      $display("BP: resolve[%d]: valid: %h, source: %h, target: %h, taken: %h, correct: %h", i,
        core.pbp.resolve.valid[i],
        core.pbp.resolve.source_pc[i],
        core.pbp.resolve.target_pc[i],
        core.pbp.resolve.taken[i],
        core.pbp.resolve.correct[i]);
    end
    for (int i = 0; i < core.pbp.update.WIDTH; i++) begin
      $display("BP: update[%d]: valid: %h, source: %h, target: %h, taken: %h", i,
        core.pbp.update.valid[i],
        core.pbp.update.source_pc[i],
        core.pbp.update.target_pc[i],
        core.pbp.update.taken[i]);
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("F[%d]: valid: %h PC: %h nPC: %h: %h", i,
        core.pfs.fetch_out[i].valid,
        core.pfs.pc + i * 4,
        core.pfs.pc_next + i * 4,
        core.pfs.fetch_out[i].inst);
    end
  end

  always @(posedge clock) begin
    $display("IB: head: %d, tail: %d, is_empty: %d", core.pib.head, core.pib.tail, core.pib.is_empty);
    $display("IB: dispatch_stage_num_can_fetch: %d", core.pib.dispatch_stage_num_can_fetch);
    for (int i = 0; i < 12; i++) begin
      $display("IB[%d]: valid: %d, PC: %h", i,
        core.pib.queue[i].valid,
        core.pib.queue[i].PC);
    end
    $display("IB: store_empty_slots: %d, store_valid_count: %d",
      core.pib.store_empty_slots,
      core.pib.store_valid_count);
    $display("IB: rob: %d, rs: %d, fl: %d",
      core.pds.it_dispatch.num_can_dispatch_inst,
      core.pds.dispatch_empty_slots,
      core.pds.rename.free_reg_valid);
    for (int i = 0; i < `WAY; i++) begin
      $display("IB: decode[%d]: valid: %h, inst: %h, pc: %h", i,
        core.pib.inst_buff_out[i].valid,
        core.pib.inst_buff_out[i].inst,
        core.pib.inst_buff_out[i].PC);
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("IB: dispatch[%d]: valid: %h, fu_type: %s, fu_func: %h, sq_idx: %d", i,
        core.pds.dispatch[i].valid,
        core.pds.dispatch[i].decoded_inst.fu_type.name,
        core.pds.dispatch[i].decoded_inst.fu_func,
        core.pds.dispatch[i].sq_index);
    end
    $display("IB: store_tail_index: %d", core.pds.store_tail_index);
  end

  // always @(posedge clock) begin
  //   $display("FL: free_reg_valid: %d", core.pfl.rename.free_reg_valid);
  //   $display("FL: num_rewind: %d", core.pfl.rewind.num);
  //   for (int i = 0; i < `WAY; i++) begin
  //     $display("FL: arch_dest_reg[%d]: %d", i, core.pfl.rename.arch_dest_reg[i]);
  //     $display("FL: dispatch_free_reg[%d]: %d", i, core.pfl.rename.dispatch_free_reg[i]);
  //     $display("MT: free_tag[%d]: %d", i, core.pmt.prepare.free_tag[i]);
  //     $display("MT: arch_dest_reg[%d]: %d", i, core.pmt.prepare.dispatch_input[i].arch_dest_reg);
  //   end

  //   for (int i = 0; i < `WAY; i++) begin
  //     $display("MT: out[%d]: ps: (%d, %d), ready: (%h, %h)", i,
  //       core.pmt.prepare.dispatch_output[i].phy_src_reg[0].index,
  //       core.pmt.prepare.dispatch_output[i].phy_src_reg[1].index,
  //       core.pmt.prepare.dispatch_output[i].ready[0],
  //       core.pmt.prepare.dispatch_output[i].ready[1]);
  //   end
  // end

  always @(posedge clock) begin
    // basic information
    $display("ROB: head: %d, tail: %d", core.prob.head, core.prob.tail);
    // dispatch I/O
    $display("ROB: occupied: %d", core.prob.occupied_spot_number);
    $display("ROB: occupancy: %4.2f", real'(core.prob.occupied_spot_number) / `ROB_SIZE * 100);
    rob_occupancy = (rob_occupancy * rob_stat_count + real'(core.prob.occupied_spot_number) / `ROB_SIZE) / (rob_stat_count + 1);
    rob_stat_count++;
    $display("ROB: num_can_dispatch_inst: %d, num_dispatched_inst: %d",
      core.prob.it_dispatch.num_can_dispatch_inst,
      core.prob.it_dispatch.num_dispatched_inst);
    for (int i = 0; i < `ROB_SIZE; i++) begin
      if (core.prob.rob_mem[i].valid) begin
        $display("ROB[%d]: pc: %h, C: %h, !: %h, t: %s, f: %h, tpc: %h, taken: %h", i,
          core.prob.rob_mem[i].pc,
          core.prob.rob_mem[i].complete,
          core.prob.rob_mem[i].exception,
          core.prob.rob_mem[i].fu_type.name,
          core.prob.rob_mem[i].fu_func,
          core.prob.rob_mem[i].target_pc,
          core.prob.rob_mem[i].taken);
      end
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("ROB: dispatch[%d]: rob_idx: %d, T_in: %d, Told_in: %d, halt: %d, illegal: %d",i,
                core.prob.it_dispatch.rob_index[i],
                core.prob.it_dispatch.T_in[i],
                core.prob.it_dispatch.Told_in[i],
                core.prob.it_dispatch.halt[i],
                core.prob.it_dispatch.illegal[i]);
    end
    // exception information
    $display("ROB: has_rewind: %d, in_rewind: %d, in_retire: %d",
      core.prob.has_rewind,
      core.prob.in_rewind,
      core.prob.in_retire);
    for (int i = 0; i < core.prob.resolve.WIDTH; i++) begin
      $display("ROB: resolve[%d]: valid: %h, correct: %h, taken: %h, target_pc: %h, rob_idx: %d", i,
        core.prob.resolve.valid[i],
        core.prob.resolve.correct[i],
        core.prob.resolve.taken[i],
        core.prob.resolve.target_pc[i],
        core.prob.resolve.rob_index[i]);
    end
    $display("ROB: has_rewind_next: %d, in_rewind_next: %d",
      core.prob.has_rewind_next,
      core.prob.in_rewind_next);
    $display("ROB: exception_code: %s", core.prob.exception_code.name);
  end

  always @(posedge clock) begin
    $display("RS: issue_empty_slots: %d", core.prs.issue_empty_slots);
    $display("RS: dispatch_empty_slots: %d", core.prs.dispatch_empty_slots);
    for (int i = 0; i < `WAY; i++) begin
      $display("RS: dispatch[%d]: valid: %h, pd: %d, ps: (%d, %d), ready: (%d, %d) rob_idx: %d, sq_idx: %d", i,
        core.prs.dispatch[i].valid,
        core.prs.dispatch[i].phy_dest_reg.index,
        core.prs.dispatch[i].phy_src_reg[0].index,
        core.prs.dispatch[i].phy_src_reg[1].index,
        core.prs.dispatch[i].ready[0],
        core.prs.dispatch[i].ready[1],
        core.prs.dispatch[i].rob_index,
        core.prs.dispatch[i].sq_index);
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("RS: issue[%d]: valid: %h, pd: %d, rob_idx: %d, fu_type: %s", i,
        core.prs.issue[i].valid,
        core.prs.issue[i].phy_dest_reg.index,
        core.prs.issue[i].rob_index,
        core.prs.issue[i].decoded_inst.fu_type.name);
    end
    for (int i = 0; i < 16; i++) begin
      $display("RS[%d]: busy: %h, ready: %h, pc: %h, pd: %d, ps: (%d, %d), psready: (%h, %h), rob_idx: %d, fu_type: %s, sq_idx: %d0", i,
        core.prs.data[i].busy,
        core.prs.ready[i],
        core.prs.data[i].packet.pc,
        core.prs.data[i].packet.phy_dest_reg.index,
        core.prs.data[i].packet.phy_src_reg[0].index,
        core.prs.data[i].packet.phy_src_reg[1].index,
        core.prs.data[i].packet.ready[0],
        core.prs.data[i].packet.ready[1],
        core.prs.data[i].packet.rob_index,
        core.prs.data[i].packet.decoded_inst.fu_type.name,
        core.prs.data[i].packet.sq_index);
    end
  end

  always @(posedge clock) begin
    for (int i = 0; i < 6; i++) begin
      $display("IQ: queue[%d]: valid: %h, pd: %d, rob_idx: %d, fu_type: %s", i,
        core.piq.queue[i].valid,
        core.piq.queue[i].phy_dest_reg.index,
        core.piq.queue[i].rob_index,
        core.piq.queue[i].decoded_inst.fu_type.name);
    end
  end

  always @(posedge clock) begin
    $display("IQ: execute_empty_slots[0]: %d ", core.piq.execute_empty_slots[0]);
    $display("IQ: execute_empty_slots[1]: %d ", core.piq.execute_empty_slots[1]);
    $display("IQ: execute_empty_slots[2]: %d ", core.piq.execute_empty_slots[2]);
    $display("IQ: execute_empty_slots[3]: %d ", core.piq.execute_empty_slots[3]);
  end

  always @(posedge clock) begin
    for (int t = 0; t < `NUM_FU_TYPE; t++) begin
      $display("IQ: execute_cnt[%d]: %d", t, core.piq.execute_cnt[t]);
      $display("IQ: execute_empty_slots[%d]: %d", t, core.piq.execute_empty_slots[t]);
      for (int i = 0; i < `WAY; i++) begin
        if (core.piq.execute[t][i].valid) begin
          $display("IQ: execute[%d][%d]: valid: %h, pd: %d, opa: %h, opb: %h, rob_idx: %d, sq_idx: %d", t, i,
            core.piq.execute[t][i].valid,
            core.piq.execute[t][i].phy_dest_reg.index,
            core.piq.execute[t][i].opa,
            core.piq.execute[t][i].opb,
            core.piq.execute[t][i].rob_index,
            core.piq.execute[t][i].exa.mem.sq_index);
        end
      end
    end

    $display("CC: MEM IO:");
    $display("CC: input: addr: %h, data: %h, command: %d", core.pcc.Dcache2Dmem_addr, core.pcc.Dcache2Dmem_data, core.pcc.Dcache2Dmem_command);
    $display("CC: output: response: %d, data: %h, tag: %d", core.pcc.Dmem2Dcache_response, core.pcc.Dmem2Dcache_data, core.pcc.Dmem2Dcache_tag);

    for (int i = 0; i < 3; i++) begin
      $display("CC: operation[%d]: curr: %h, next: %h", i,
        core.pcc.dcache_inst.operation[i],
        core.pcc.dcache_inst.operation_next[i]);
    end

    $display("CC: D$ IO:");
    for (int i = 0; i < 2; i++) begin
        $display("CC[%d]: load_en_ctrl: %d, load_accepted_ctrl: %d", i, core.pcc.load_en_ctrl[i], core.pcc.load_store_accepted[i]);
        $display("CC[%d]: load_addr: %h", i, core.pcc.proc2Dcache_addr_load_ctrl[i]);
        $display("CC[%d]: Dcache_valid_out_ctrl: %d", i, core.pcc.Dcache_valid_out_ctrl[i]);
    end
    $display("CC: store_en_ctrl: %d, store_accepted_ctrl: %d", core.pcc.store_en_ctrl, core.pcc.load_store_accepted[2]);
    $display("CC: store_addr: %h", core.pcc.proc2Dcache_addr_store);
    $display("CC: store_data_ctrl: %h", core.pcc.proc2Dcache_data_store_ctrl);

    $display("CC: data:");
    for (int i = 0; i < 2; i++) begin
      $display("CC[%d]: load_en: %d", i , core.pcc.load_en[i]);
      $display("CC[%d]: load_accepted: %d", i, core.pcc.load_accepted[i]);
    end
    $display("CC: store_en: %d", core.pcc.store_en);
    $display("CC: store_accepted: %d", core.pcc.store_accepted);
    $display("CC: relevant_load_store: %d", core.pcc.relevant_load_store);
    $display("CC: state: %d, state_next: %d", core.pcc.state, core.pcc.state_next);

    $display("FU MEM: empty_slots: %d",
      core.pfme.execute_empty_slots);
    for (int i = 0; i < 1; i++) begin
      $display("FU MEM[%d]: execute: valid: %h, pd: %d, opa: %h, opb: %h, rob_idx: %d, sq_idx: %d", i,
        core.pfme.execute[i].valid,
        core.pfme.execute[i].phy_dest_reg.index,
        core.pfme.execute[i].opa,
        core.pfme.execute[i].opb,
        core.pfme.execute[i].rob_index,
        core.pfme.execute[i].exa.mem.sq_index);
      $display("FU MEM[%d]: start: %h, result: %h, done: %h", i,
        core.pfme.alu_start[i],
        core.pfme.alu_result[i],
        core.pfme.alu_done[i]);
      $display("FU MEM[%d]: store_request: valid: %h, addr: %h, data: %h", i,
        core.pfme.store_request[i].valid,
        core.pfme.store_request[i].addr,
        core.pfme.store_request[i].data);
      $display("FU MEM[%d]: load_request: valid: %h, addr: %h", i,
        core.pfme.load_request[i].valid,
        core.pfme.load_request[i].addr);
      $display("FU MEM[%d]: load_result: valid: %h, data: %h, mask: %h", i,
        core.pfme.load_result[i].valid,
        core.pfme.load_result[i].data,
        core.pfme.load_result[i].mask);
      $display("FU MEM[%d]: load_en: %h, load_addr: %h, load_state: %h", i,
        core.pfme.load_en[i],
        core.pfme.load_addr[i],
        core.pfme.alu_load_state[i]);
      $display("FU MEM[%d]: load_valid: %h, load_accepted: %h, load_data: %h", i,
        core.pfme.load_valid[i],
        core.pfme.load_accepted[i],
        core.pfme.load_data[i]);
    end

    $display("SQ: head: %d, tail: %d, flush %h",
      core.psq.head, core.psq.tail, core.psq.flush);
    $display("SQ: is_store: %h, store_en: %h, store_accepted: %h",
      core.psq.retire.is_store,
      core.psq.store_en,
      core.psq.retire.store_accepted);
    for (int i = 0; i < core.psq.SIZE; i++) begin
      $display("SQ[%d]: valid: %h, func: %h, addr: %h, data: %h", i,
        core.psq.sq[i].valid,
        core.psq.sq[i].func,
        core.psq.sq[i].addr,
        core.psq.sq[i].data);
    end

    for (int j = 0; j <= 4; j++) begin
      for (int i = 0; i < `WAY; i++) begin
        $display("FU MULT: execute_data[%d][%d]: valid: %h, pd: %d, opa: %h, opb: %h, rob_idx: %d", i, j,
          core.pfmu.execute_data[j][i].valid,
          core.pfmu.execute_data[j][i].phy_dest_reg.index,
          core.pfmu.execute_data[j][i].opa,
          core.pfmu.execute_data[j][i].opb,
          core.pfmu.execute_data[j][i].rob_index);
      end
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("FU MULT: busy[%d]: %d", i, core.pfmu.alu_busy[i]);
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("FU MULT: start[%d]: %d", i, core.pfmu.alu_start[i]);
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("FU MULT: done[%d]: %d", i, core.pfmu.alu_done[i]);
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("FU MULT: result[%d]: %h", i, core.pfmu.alu_result[i]);
    end

    $display("FU BRANCH: %h ? %h",
      core.pfb.branch_operand[0][0],
      core.pfb.branch_operand[0][1]);
    $display("FU BRANCH: valid: %h", core.pfb.resolve.valid[0]);
    $display("FU BRANCH: spc: %h", core.pfb.resolve.source_pc[0]);
    $display("FU BRANCH: tpc: %h", core.pfb.resolve.target_pc[0]);
    $display("FU BRANCH: rob_idx: %d", core.pfb.resolve.rob_index[0]);
    $display("FU BRANCH: taken: %h", core.pfb.resolve.taken[0]);
    for (int i = 0; i < core.prob.update.WIDTH; i++) begin
      if (core.prob.update.valid[i]) begin
        if (core.prob.update.correct[i]) begin
          resolve_correct_count++;
        end
        resolve_total_count++;
      end
    end

    for (int t = 0; t < `NUM_FU_TYPE; t++) begin
      for (int i = 0; i < `WAY; i++) begin
        $display("FU: result[%d][%d]: valid: %h, pd: %d, rob_idx: %d, value: %h", t, i,
          core.result[t][i].valid,
          core.result[t][i].phy_dest_reg.index,
          core.result[t][i].rob_index,
          core.result[t][i].result);
      end
    end
  end

  always @(posedge clock) begin
    for (int i = 0; i < `NUM_FU_TYPE * `WAY; i++) begin
      if (core.pcq.execute[i].valid) begin
        $display("CQ: execute[%d]: pd: %d, rob_idx: %d", i,
          core.pcq.execute[i].phy_dest_reg.index,
          core.pcq.execute[i].rob_index);
      end
    end
    for (int i = 0; i < `WAY; i++) begin
      $display("CQ: complete[%d]: valid: %h, pd: %d, rob_idx: %d", i,
        core.pcq.complete[i].valid,
        core.pcq.complete[i].phy_dest_reg.valid ? core.pcq.complete[i].phy_dest_reg.index : 0,
        core.pcq.complete[i].rob_index);
    end
  end

  always @(posedge clock) begin
    $display("CQ: head: %d, tail: %d, flush: %d", core.pcq.head, core.pcq.tail, core.pcq.flush);
    for (int i = 0; i < 16; i++) begin
      if (core.pcq.queue[i].valid) begin
        if (core.pcq.head == i) begin
          $display("CQ[%d]: head", i);
        end
        if (core.pcq.tail == i) begin
          $display("CQ[%d]: tail", i);
        end
        $display("CQ[%d]: pd: %d, rob_idx: %d", i,
          core.pcq.queue[i].phy_dest_reg.index,
          core.pcq.queue[i].rob_index);
      end
    end
  end

  // always @(posedge clock) begin
  //   for (int i = 0; i < `PHY_REG_SIZE; i++) begin
  //     if (core.prf.registers[i]) begin
  //       $display("REG[%d]: 0x%h", i, core.prf.registers[i]);
  //     end
  //   end
  // end

  // always @(posedge clock) begin
  //   for (int i = 0; i < `ARCH_REG_SIZE; i++) begin
  //     // $display("MT[%d]: %d", i, core.pmt.map[i].index);
  //   end
  // end

   always @(posedge clock) begin
     for (int i = 0; i < `ARCH_REG_SIZE; i++) begin
       $display("REG[%d]: 0x%h", i, core.prf.registers[core.pmt.map[i]]);
     end
   end

   always @(posedge clock)
    $display("");

`endif
	// Count the number of posedges and number of instructions completed
	// till simulation ends
	always @(posedge clock) begin
		if(reset) begin
			clock_count <= `SD 0;
			instr_count <= `SD 0;
		end else begin
			clock_count <= `SD (clock_count + 1);
			instr_count <= `SD (instr_count + pipeline_retire_instr_num);
		end
	end

  PC_t       [`ROB_SIZE-1:0]  pipeline_ROB_instr_PC;
  PC_t       [`ROB_SIZE-1:0]  pipeline_ROB_instr_PC_next;
  rob_idx_t                   pipeline_ROB_instr_PC_head;
  rob_idx_t                   pipeline_ROB_instr_PC_head_next;

	always @(posedge clock) begin
    if (reset) begin
      pipeline_ROB_instr_PC <= `SD '0;
      pipeline_ROB_instr_PC_head <= `SD '0;
    end else begin
      pipeline_ROB_instr_PC <= `SD pipeline_ROB_instr_PC_next;
      pipeline_ROB_instr_PC_head <= `SD pipeline_ROB_instr_PC_head_next;
    end

    // print the writeback information to writeback.out
    for (int i = 0; i < pipeline_retire_instr_num; i++) begin
      if(pipeline_retire_arch_reg_idx[i] == 0)begin
        $fdisplay(wb_fileno, "PC=%x, ---",
          pipeline_ROB_instr_PC[(pipeline_ROB_instr_PC_head+i) % `ROB_SIZE]);
      end else begin
        $fdisplay(wb_fileno, "PC=%x, REG[%d]=%x",
          pipeline_ROB_instr_PC[(pipeline_ROB_instr_PC_head+i) % `ROB_SIZE],
          pipeline_retire_arch_reg_idx[i],
          pipeline_retire_arch_reg_data[i]);
      end
    end

   /* $display("ROB_PC: head: %d", pipeline_ROB_instr_PC_head); */
   /* $display("ROB_PC: head_next: %d", pipeline_ROB_instr_PC_head_next); */
   /* $display("ROB_PC: retire_instr_num: %d", pipeline_retire_instr_num); */
   /* for (int i = 0; i < `ROB_SIZE; i++) begin */
   /*   $display("ROB_PC[%d]: 0x%h", i, pipeline_ROB_instr_PC[i]); */
   /* end */
  end

  always_comb begin
    // save PC information of dispatched instr.s for writeback use
    pipeline_ROB_instr_PC_next = pipeline_ROB_instr_PC;
    for (int i = 0; i < pipeline_dispatch_instr_num; i++) begin
      pipeline_ROB_instr_PC_next[pipeline_dispatch_instr_rob_idx[i]] =
        pipeline_dispatch_instr_PC[i];
    end
    pipeline_ROB_instr_PC_head_next =
      ( pipeline_ROB_instr_PC_head + pipeline_retire_instr_num ) % `ROB_SIZE;
  end

  always @(posedge clock) begin
    if (reset) begin
      rob_occupancy <= 0;
      rob_stat_count <= 0;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      resolve_correct_count <= 0;
      resolve_total_count <= 0;
    end
  end

  // counter used for when pipeline infinite loops, forces termination
  int unsigned inf_loop_counter;
  parameter inf_loop_counter_max = 1000000;
  // counter used for when pipeline stuck on retiring one instr., forces termination
  int unsigned retire_stuck_counter;
  parameter retire_stuck_counter_max = 100;

	always @(posedge clock) begin
    if(reset) begin
      $display("@@\n@@  %t : System STILL at reset, can't show anything\n@@",
             $realtime);
      inf_loop_counter      <= 0;
      retire_stuck_counter  <= 0;
    end else begin
      inf_loop_counter <= inf_loop_counter + 1;
      // increase the retire_stuck_counter only if there is no instr.s to retire
      // reset the counter every time instr.s are retired
      if (pipeline_retire_instr_num > 0)
        retire_stuck_counter <= 0;
      else
        retire_stuck_counter <= retire_stuck_counter + 1;

      `SD;
      `SD;

      // deal with any halting conditions
      if (retire_stuck_counter > retire_stuck_counter_max) begin
        $display("@@ No instruction is retired in the last %d cycles, force to halt the system!", retire_stuck_counter_max);
        halt;
      end

      if (inf_loop_counter > inf_loop_counter_max) begin
        $display("@@ Clock cycle exceeds maximum limit (%d cycles), force to halt the system!", inf_loop_counter_max);
        halt;
      end

      if (pipeline_error_status != NO_ERROR) begin
        halt;
      end
		end  // if(reset)
	end

  task halt;
    $display("@@@ Unified Memory contents hex on left, decimal on right: ");
    // 8Bytes per line, 16kB total
    show_mem_with_decimal(0,`MEM_64BIT_LINES - 1);

    $display("@@  %t : System halted\n@@", $realtime);

    case(pipeline_error_status)
      LOAD_ACCESS_FAULT:
        $display("@@@ System halted on memory error");
      HALTED_ON_WFI:
        $display("@@@ System halted on WFI instruction");
      ILLEGAL_INST:
        $display("@@@ System halted on illegal instruction");
      default:
        $display("@@@ System halted on unknown error code %x",
          pipeline_error_status);
    endcase
    $display("@@@\n@@");

    show_clk_count;
    show_rob_occupancy;
    show_bp_accuracy;

    $fclose(wb_fileno);

    $finish;
  endtask
endmodule  // module testbench
