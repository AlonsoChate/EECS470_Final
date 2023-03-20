/* DESIGN = p fu_fast_int fu_mult fu_mem */
`include "sys_defs.svh"
`include "issue.svh"
`include "execute.svh"
`include "fu_macro.svh"
`include "resolve.svh"
`include "execute.svh"

`timescale 1ns/100ps

module alu_fast_int(
  input clock,
  input reset,

  input start,
	input xlen_t opa,
	input xlen_t opb,

	fu_func_t fu_func,

	output xlen_t result,
  output logic done
);
	wire signed [`XLEN-1:0] signed_opa, signed_opb;
	assign signed_opa = opa;
	assign signed_opb = opb;

  assign done = `TRUE;

	always_comb begin
		priority case (fu_func.int_fast.func)
			FU_ADD:      result = opa + opb;
			FU_SUB:      result = opa - opb;
			FU_SLT:      result = signed_opa < signed_opb;
			FU_SLTU:     result = opa < opb;
			FU_AND:      result = opa & opb;
			FU_OR:       result = opa | opb;
			FU_XOR:      result = opa ^ opb;
			FU_SRL:      result = opa >> opb[4:0];
			FU_SLL:      result = opa << opb[4:0];
			FU_SRA:      result = signed_opa >>> opb[4:0]; // arithmetic form logical shift

			// default:      result = `XLEN'hfacebeec;  // here to prevent latches
		endcase
	end

endmodule // alu_fast_int

module alu_mult #(
  parameter NUM_STAGE = 4
) (
  input clock,
  input reset,

  input start,
	input xlen_t opa,
	input xlen_t opb,

	fu_func_t fu_func_start,
  fu_func_t fu_func_done,

	output xlen_t result,
  output logic done
);

  logic [(2*`XLEN)-1:0] product;
  logic [1:0]           mult_sign;
  logic mult_done;

  assign done = mult_done;

  mult #(.XLEN(`XLEN), .NUM_STAGE(NUM_STAGE)) mult_0 (
    .clock(clock),
    .reset(reset),
    .start(start),
    .sign(mult_sign),
    .mcand(opa),
    .mplier(opb),
    .product(product),
    .done(mult_done)
  );

	always_comb begin
		priority case (fu_func_done.int_mult.func)
      FU_MUL:      result = product[`XLEN-1:0];
      FU_MULH,
      FU_MULHSU,
			FU_MULHU:    result = product[2*`XLEN-1:`XLEN];

			default:     result = `XLEN'hfacebeec;  // here to prevent latches
		endcase

    priority case(fu_func_start.int_mult.func)
      FU_MUL:      mult_sign = 2'b11;
      FU_MULH:     mult_sign = 2'b11;
      FU_MULHSU:   mult_sign = 2'b10;
      FU_MULHU:    mult_sign = 2'b00;

      default:     mult_sign = 2'b00;
    endcase
	end

endmodule // alu_mult

module alu_branch(
  input clock,
  input reset,

  input start,
  input xlen_t opa,
  input xlen_t opb,

  input xlen_t [1:0] cop,

  input fu_func_t fu_func,

  output xlen_t result,
  output logic done,

  output logic taken,
  output PC_t new_PC
);

  logic signed [1:0][`XLEN-1:0] signed_cop;
  assign signed_cop = cop;

  assign done = `TRUE;

  always_comb begin
    taken = `FALSE;
    case (fu_func.branch.ty)
      FU_BRANCH_COND: begin
        priority case (fu_func.branch.func)
          FU_BEQ: taken = (signed'(cop[0]) == signed'(cop[1]));
          FU_BNE: taken = (signed'(cop[0]) != signed'(cop[1]));
          FU_BLT: taken = (signed'(cop[0]) <  signed'(cop[1]));
          FU_BGE: taken = (signed'(cop[0]) >= signed'(cop[1]));
          FU_BLTU: taken = (cop[0] < cop[1]);
          FU_BGEU: taken = (cop[0] >= cop[1]);
        endcase
        result = 0;
      end
      FU_BRANCH_UNCOND: begin
        taken = `TRUE;
        result = cop[0] + 4;
      end
    endcase
    if (taken) begin
      new_PC = opa + opb;
    end else begin
      new_PC = opa + 4;
    end
  end
endmodule

typedef enum logic [1:0] {
  LOAD_STATE_IDLE   = 2'h0,
  LOAD_STATE_QUEUE  = 2'h1,
  LOAD_STATE_WAIT   = 2'h2
} load_state_t;

module alu_mem (
  input   clock, reset,
  input   flush,
  input   start,
  input   xlen_t  opa,
  input   xlen_t  opb,
  output  xlen_t  result,
  output  logic   done,

  input   fu_func_t fu_func,
  input   rob_idx_t rob_index,
  input   xlen_t    store_data,
  input   sq_idx_t  sq_index,

  // To/From SQ
  output  store_request_t store_request,
  output  load_request_t  load_request,
  input   load_result_t   load_result,

  // To/From CC
  output  PC_t          load_addr_aligned,
  output  logic         load_en,
  output  load_state_t  load_state,
  input   [63:0]        load_data,
  input                 load_valid,
  input                 load_accepted
);
  logic signed [`XLEN-1:0] signed_opa, signed_opb;
  assign signed_opa = opa;
  assign signed_opb = opb;

  logic   [2:0] bo;
  load_state_t  load_state_next;
  load_result_t internal_load_result, internal_load_result_next;

  PC_t load_addr;

  assign load_en            = flush ? `FALSE : (load_state == LOAD_STATE_QUEUE) && ~load_accepted;
  assign load_addr          = opa + signed_opb;
  assign load_addr_aligned  = {load_addr[`XLEN-1:3], 3'b000};
  assign done               = flush ? `TRUE : (load_state_next == LOAD_STATE_IDLE);

  always_comb begin
    load_request    = 0;
    store_request   = 0;
    bo              = 0;
    result          = 0;

    load_state_next           = load_state;
    internal_load_result_next = internal_load_result;

    if (!flush) begin
      if (start) begin
        if (fu_func.mem.rw == FU_MEM_READ) begin
          load_state_next           = LOAD_STATE_QUEUE;

          // Send load request to SQ
          load_request.valid        = `TRUE;
          load_request.addr         = load_addr;
          load_request.rob_index    = rob_index;
          load_request.sq_index     = sq_index;

          internal_load_result_next = load_result;

        end else begin
          // Send store request to SQ
          store_request.valid     = `TRUE;
          store_request.data      = store_data;
          store_request.func      = fu_func.mem.func.write;
          store_request.addr      = load_addr;
          store_request.sq_index  = sq_index;

          load_state_next         = LOAD_STATE_IDLE;
        end
      end

      // This fu is currently in the loading state
      if (load_state != LOAD_STATE_IDLE) begin
        // Merge results
        // 1. Retreive CC results
        bo = load_addr[2:0] * 8;
        case (fu_func.mem.func.read)
          FU_LB: begin
            if (load_addr[2]) begin
              if (load_addr[1]) begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[63:56];
                end else begin
                  result[7:0] = load_data[55:48];
                end
              end else begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[47:40];
                end else begin
                  result[7:0] = load_data[39:32];
                end
              end
            end else begin
              if (load_addr[1]) begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[31:24];
                end else begin
                  result[7:0] = load_data[23:16];
                end
              end else begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[15:8];
                end else begin
                  result[7:0] = load_data[7:0];
                end
              end
            end
            result[31:8]  = {24{result[7]}};
          end
          FU_LH: begin
            if (load_addr[2]) begin
              if (load_addr[1]) begin
                result[15:0] = load_data[63:48];
              end else begin
                result[15:0] = load_data[47:32];
              end
            end else begin
              if (load_addr[1]) begin
                result[15:0] = load_data[31:16];
              end else begin
                result[15:0] = load_data[15:0];
              end
            end
            result[31:16] = {16{result[15]}};
          end
          FU_LW: begin
            // result[31:0] = load_data[bo+:32];
            if (load_addr[2]) begin
              result[31:0] = load_data[63:32];
            end else begin
              result[31:0] = load_data[31:0];
            end
          end
          FU_LBU: begin
            if (load_addr[2]) begin
              if (load_addr[1]) begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[63:56];
                end else begin
                  result[7:0] = load_data[55:48];
                end
              end else begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[47:40];
                end else begin
                  result[7:0] = load_data[39:32];
                end
              end
            end else begin
              if (load_addr[1]) begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[31:24];
                end else begin
                  result[7:0] = load_data[23:16];
                end
              end else begin
                if (load_addr[0]) begin
                  result[7:0] = load_data[15:8];
                end else begin
                  result[7:0] = load_data[7:0];
                end
              end
            end
          end
          FU_LHU: begin
            if (load_addr[2]) begin
              if (load_addr[1]) begin
                result[15:0] = load_data[63:48];
              end else begin
                result[15:0] = load_data[47:32];
              end
            end else begin
              if (load_addr[1]) begin
                result[15:0] = load_data[31:16];
              end else begin
                result[15:0] = load_data[15:0];
              end
            end
          end
        endcase

        // 2. Retreive and merge SQ results
        if (internal_load_result_next.valid) begin
          result = (result & ~internal_load_result_next.mask) | (internal_load_result_next.data & internal_load_result_next.mask);
        end
      end

      if (load_state == LOAD_STATE_QUEUE)
        load_state_next = load_valid ? LOAD_STATE_IDLE :
                          (load_accepted ? LOAD_STATE_WAIT : LOAD_STATE_QUEUE);
      else if (load_state == LOAD_STATE_WAIT)
        load_state_next = load_valid ? LOAD_STATE_IDLE : LOAD_STATE_WAIT;

      if (load_state_next == LOAD_STATE_IDLE)
        internal_load_result_next = 0;
    end
  end

  always_ff @(posedge clock) begin
    if (reset || flush) begin
      load_state            <= `SD LOAD_STATE_IDLE;
      internal_load_result  <= `SD 0;
    end
    else begin
      load_state            <= `SD load_state_next;
      internal_load_result  <= `SD internal_load_result_next;
    end
  end
endmodule

module fu_mem #(
  WIDTH = 1
) (
  input   clock, reset,
  input   execute_packet_t  [WIDTH-1:0]                 execute,
  output  result_packet_t   [WIDTH-1:0]                 result,
  output  logic             [`WAY_CNT_LEN-1:0]          execute_empty_slots,
  input                                                 flush,

  // TO/From SQ
  output  store_request_t   [WIDTH-1:0]                 store_request,
  output  load_request_t    [WIDTH-1:0]                 load_request,
  input   load_result_t     [WIDTH-1:0]                 load_result,

  // TO/From CC
  output  PC_t              [WIDTH-1:0]                 load_addr,
  output  logic             [WIDTH-1:0]                 load_en,
  input                     [WIDTH-1:0][63:0]           load_data,
  input                     [WIDTH-1:0]                 load_valid,
  input                     [WIDTH-1:0]                 load_accepted
);
  execute_packet_t  [WIDTH-1:0] execute_data, execute_data_next;
  load_state_t      [WIDTH-1:0] alu_load_state;
  xlen_t  [WIDTH-1:0] alu_result;
  logic   [WIDTH-1:0] alu_start, alu_start_next;
  logic   [WIDTH-1:0] alu_done;
  logic   [WIDTH-1:0] alu_busy;
  logic   [WIDTH-1:0] slot_empty;
  logic   [WIDTH-1:0] input_assigned;
  xlen_t  [WIDTH-1:0] store_data;
  sq_idx_t  [WIDTH-1:0] sq_index;

  generate
    for (genvar i = 0; i < WIDTH; i++) begin
      assign store_data[i] = execute_data[i].exa.mem.store_data;
      assign sq_index[i] = execute_data[i].exa.mem.sq_index;
      alu_mem alu_0(
        .clock(clock),
        .reset(reset),
        .flush(flush),
        .start(alu_start[i]),
        .opa(execute_data[i].opa),
        .opb(execute_data[i].opb),
        .result(alu_result[i]),
        .done(alu_done[i]),

        .fu_func(execute_data[i].decoded_inst.fu_func),
        .rob_index(execute_data[i].rob_index),
        .store_data(store_data[i]),
        .sq_index(sq_index[i]),

        .store_request(store_request[i]),
        .load_request(load_request[i]),
        .load_result(load_result[i]),

        .load_addr_aligned(load_addr[i]),
        .load_en(load_en[i]),
        .load_state(alu_load_state[i]),
        .load_data(load_data[i]),
        .load_valid(load_valid[i]),
        .load_accepted(load_accepted[i])
      );
      assign alu_busy[i] = execute_data[i].valid ? ~alu_done[i] : `FALSE;
    end
  endgenerate

  always_comb begin
    slot_empty = ~alu_busy;
    input_assigned = 0;
    execute_empty_slots = 0;
    execute_data_next = execute_data;
    alu_start_next = 0;
    result = 0;
    for (int i = 0; i < WIDTH; i++) begin
      if (execute_data[i].valid & alu_done[i]) begin
        result[i] = {
          execute_data[i].phy_dest_reg,
          alu_result[i],
          execute_data[i].rob_index,
          `TRUE
        };
        execute_data_next[i] = 0;
      end
    end
    for (int i = 0; i < WIDTH; i++)
      if (~alu_busy[i])
        execute_empty_slots += 1;
    for (int i = 0; i < WIDTH; i++) begin
      if (execute[i].valid) begin
        for (int j = 0; j < WIDTH; j++) begin
          if (slot_empty[j] & ~input_assigned[i]) begin
            execute_data_next[j] = execute[i];
            alu_start_next[j] = `TRUE;
            slot_empty[j] = `FALSE;
            input_assigned[i] = `TRUE;
          end
        end
      end
    end
    if (flush) begin
      result = 0;
    end
  end

  always_ff @(posedge clock) begin
    if (reset || flush) begin
      execute_data <= `SD 0;
      alu_start <= `SD 0;
    end else begin
      execute_data <= `SD execute_data_next;
      alu_start <= `SD alu_start_next;
    end
  end
endmodule

module fu_branch #(
  parameter I_WIDTH = 1,
  parameter E_WIDTH = 1,
  localparam E_WIDTH_CNT_LEN = `CAL_CNT_LEN(E_WIDTH)
) (
  input  clock, reset,
  input  execute_packet_t [I_WIDTH-1:0]                 execute,
  output result_packet_t  [I_WIDTH-1:0]                 result,
  output logic            [E_WIDTH_CNT_LEN-1:0]         execute_empty_slots,
  if_resolve.fu_branch                                  resolve
);
  execute_packet_t  [E_WIDTH-1:0] execute_data;
  xlen_t            [E_WIDTH-1:0] alu_result;
  logic             [E_WIDTH-1:0] alu_done, alu_start;
  logic             [E_WIDTH-1:0] alu_busy;
  logic             [I_WIDTH-1:0] alu_taken;
  PC_t              [I_WIDTH-1:0] alu_new_PC;
  logic             [E_WIDTH-1:0] slot_empty;
  logic             [I_WIDTH-1:0] input_assigned;
  execute_packet_t  [E_WIDTH-1:0] next_execute_data;
  logic             [E_WIDTH-1:0] next_alu_start;
  xlen_t            [I_WIDTH-1:0] [1:0] branch_operand;
  generate
    for (genvar i = 0; i < E_WIDTH; ++i) begin
      assign branch_operand[i] = execute_data[i].exa.branch;
      alu_branch _0(
        .clock(clock),
        .reset(reset),
        .start(alu_start[i]),
        .opa(execute_data[i].opa),
        .opb(execute_data[i].opb),
        .cop(branch_operand[i]),
        .fu_func(execute_data[i].decoded_inst.fu_func),
        .result(alu_result[i]),
        .done(alu_done[i]),
        .taken(alu_taken[i]),
        .new_PC(alu_new_PC[i])
      );
      assign alu_busy[i]  = execute_data[i].valid ?
                            ~alu_done[i] : `FALSE;
    end
  endgenerate
  always_comb begin
    slot_empty          = ~alu_busy;
    input_assigned      = 0;
    execute_empty_slots = 0;
    next_execute_data   = execute_data;
    next_alu_start      = 0;
    result              = 0;
    resolve.valid = 0;
    resolve.source_pc = 0;
    resolve.target_pc = 0;
    resolve.rob_index = 0;
    resolve.taken = 0;
    for (int i = 0; i < E_WIDTH; ++i) begin
      if (execute_data[i].valid & alu_done[i]) begin
        result[i] = {
          execute_data[i].phy_dest_reg,
          alu_result[i],
          execute_data[i].rob_index,
          `TRUE
        };
        resolve.valid[i] = `TRUE;
        case (execute_data[i].decoded_inst.fu_func.branch.ty)
          FU_BRANCH_COND:
            resolve.source_pc[i] = execute_data[i].opa;
          FU_BRANCH_UNCOND:
            resolve.source_pc[i] = branch_operand[i][0];
        endcase
        resolve.target_pc[i] = alu_new_PC[i];
        resolve.rob_index[i] = execute_data[i].rob_index;
        resolve.taken[i] = alu_taken[i];
        next_execute_data[i] = 0;
      end
    end
    for (int i = 0; i < E_WIDTH; ++i)
      if (~alu_busy[i])
        execute_empty_slots += 1;
    for (int j = 0; j < I_WIDTH; ++j) begin
      if (execute[j].valid) begin
        for (int i = 0; i < E_WIDTH; ++i) begin
          if (slot_empty[i] & ~input_assigned[j]) begin
            next_execute_data[i]  = execute[j];
            next_alu_start[i]     = `TRUE;
            slot_empty[i]         = `FALSE;
            input_assigned[j]     = `TRUE;
          end
        end
      end
    end
  end
  always_ff @(posedge clock) begin
    if (reset) begin
      execute_data  <= `SD 0;
      alu_start     <= `SD 0;
    end else begin
      execute_data  <= `SD next_execute_data;
      alu_start     <= `SD next_alu_start;
    end
  end
endmodule

module fu_mult #(
  parameter NUM_STAGE = 4,
  parameter I_WIDTH = `WAY,
  parameter E_WIDTH = `WAY,
  localparam I_WIDTH_CNT_LEN = `CAL_CNT_LEN(I_WIDTH)
) (
  input   clock, reset,
  input   execute_packet_t  [I_WIDTH-1:0]                 execute,
  output  result_packet_t   [E_WIDTH-1:0]                 result,
  output  logic             [I_WIDTH_CNT_LEN-1:0]         execute_empty_slots
);
  execute_packet_t  [NUM_STAGE:0][E_WIDTH-1:0]    execute_data;
  xlen_t            [E_WIDTH-1:0]                 alu_result;
  logic             [E_WIDTH-1:0]                 alu_done, alu_start;
  wire              [E_WIDTH-1:0]                 alu_busy;
  logic             [E_WIDTH-1:0]                 slot_empty;
  logic             [I_WIDTH-1:0]                 input_assigned;
  execute_packet_t  [E_WIDTH-1:0]                 next_execute_data;
  logic             [E_WIDTH-1:0]                 next_alu_start;
  generate
    for (genvar i = 0; i < E_WIDTH; ++i) begin
      alu_mult #(.NUM_STAGE(NUM_STAGE)) _0 (
        .clock(clock),
        .reset(reset),
        .start(alu_start[i]),
        .opa(execute_data[0][i].opa),
        .opb(execute_data[0][i].opb),
        .fu_func_start(execute_data[0][i].decoded_inst.fu_func),
        .fu_func_done(execute_data[NUM_STAGE][i].decoded_inst.fu_func),
        .result(alu_result[i]),
        .done(alu_done[i])
      );
      assign alu_busy[i]  = execute_data[0][i].valid ?
                            ~alu_done[i] : `FALSE;
    end
  endgenerate
  always_comb begin
    slot_empty          = ~alu_busy;
    input_assigned      = 0;
    execute_empty_slots = 0;
    next_execute_data   = 0;
    next_alu_start      = 0;
    result              = 0;
    for (int i = 0; i < E_WIDTH; ++i) begin
      if (execute_data[NUM_STAGE][i].valid & alu_done[i]) begin
        result[i].phy_dest_reg  = execute_data[NUM_STAGE][i].phy_dest_reg;
        result[i].result        = alu_result[i];
        result[i].rob_index     = execute_data[NUM_STAGE][i].rob_index;
        result[i].valid         = `TRUE;
      end
    end
    for (int i = 0; i < E_WIDTH; ++i)
      if (~alu_busy[i])
        execute_empty_slots += 1;
    for (int j = 0; j < I_WIDTH; ++j) begin
      if (execute[j].valid) begin
        for (int i = 0; i < E_WIDTH; ++i) begin
          if (slot_empty[i] & ~input_assigned[j]) begin
            next_execute_data[i]  = execute[j];
            next_alu_start[i]     = `TRUE;
            slot_empty[i]         = `FALSE;
            input_assigned[j]     = `TRUE;
          end
        end
      end
    end
  end
  always_ff @(posedge clock) begin
    if (reset) begin
      execute_data  <= `SD 0;
      alu_start     <= `SD 0;
    end else begin
      execute_data[NUM_STAGE:1] <= `SD execute_data[NUM_STAGE-1:0];
      execute_data[0]             <= `SD next_execute_data;
      alu_start                   <= `SD next_alu_start;
    end
  end
endmodule

`include "fu_macro.svh"

`DEF_FU(fast_int, alu_fast_int)
