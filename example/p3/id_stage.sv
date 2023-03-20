/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  id_stage.v                                          //
//                                                                     //
//  Description :  instruction decode (ID) stage of the pipeline;      // 
//                 decode the instruction fetch register operands, and // 
//                 compute immediate operand (if applicable)           // 
//                                                                     //
/////////////////////////////////////////////////////////////////////////


`timescale 1ns/100ps

`include "decoder.sv"

module id_stage(         
	input         clock,              // system clock
	input         reset,              // system reset
	input         wb_reg_wr_en_out,    // Reg write enable from WB Stage
	input  [4:0] wb_reg_wr_idx_out,  // Reg write index from WB Stage
	input  [`XLEN-1:0] wb_reg_wr_data_out,  // Reg write data from WB Stage
	input  IF_ID_PACKET if_id_packet_in,
	
	output ID_EX_PACKET id_packet_out
);

    assign id_packet_out.inst = if_id_packet_in.inst;
    assign id_packet_out.NPC  = if_id_packet_in.NPC;
    assign id_packet_out.PC   = if_id_packet_in.PC;
	DEST_REG_SEL dest_reg_select; 

	// Instantiate the register file used by this pipeline
	regfile regf_0 (
		.rda_idx(if_id_packet_in.inst.r.rs1),
		.rda_out(id_packet_out.rs1_value), 

		.rdb_idx(if_id_packet_in.inst.r.rs2),
		.rdb_out(id_packet_out.rs2_value),

		.wr_clk(clock),
		.wr_en(wb_reg_wr_en_out),
		.wr_idx(wb_reg_wr_idx_out),
		.wr_data(wb_reg_wr_data_out)
	);

	// instantiate the instruction decoder
	decoder decoder_0 (
		.if_packet(if_id_packet_in),	 
		// Outputs
		.opa_select(id_packet_out.opa_select),
		.opb_select(id_packet_out.opb_select),
		.alu_func(id_packet_out.alu_func),
		.dest_reg(dest_reg_select),
		.rd_mem(id_packet_out.rd_mem),
		.wr_mem(id_packet_out.wr_mem),
		.cond_branch(id_packet_out.cond_branch),
		.uncond_branch(id_packet_out.uncond_branch),
		.csr_op(id_packet_out.csr_op),
		.halt(id_packet_out.halt),
		.illegal(id_packet_out.illegal),
		.valid_inst(id_packet_out.valid)
	);

	// mux to generate dest_reg_idx based on
	// the dest_reg_select output from decoder
	always_comb begin
		case (dest_reg_select)
			DEST_RD:    id_packet_out.dest_reg_idx = if_id_packet_in.inst.r.rd;
			DEST_NONE:  id_packet_out.dest_reg_idx = `ZERO_REG;
			default:    id_packet_out.dest_reg_idx = `ZERO_REG; 
		endcase
	end
   
endmodule // module id_stage
