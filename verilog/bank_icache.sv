/* DESIGN = p bank_icache */
`include "sys_defs.svh"

`define ICACHE_SIZE 16
`define ICACHE_IDX_LEN $clog2(`ICACHE_SIZE)


typedef struct packed {
	logic [63:0]                     data;
	logic [27 - `ICACHE_IDX_LEN:0]   tags;  // 32bits pc, 4 bits block offset -> 28 bits used for tag and index
	logic                            valids;
} ICACHE_PACKET;

/*
	if miss, get one tag from mem and wait until read from it
*/
module icache(
	input 				clock,reset,

	// from memory
	input [3:0]  		Imem2Icache_response,
	input [63:0] 		Imem2Icache_data,
	input [3:0]  		Imem2Icache_tag,

	// from fetch stage
	input PC_t 			proc2Icache_addr,

	// to memory
	output logic [1:0] 	Icache2Imem_command,
	output PC_t 		Icache2Imem_addr,

	// to fetch stage
	output logic [63:0]	Icache_data_out, // value is memory[proc2Icache_addr]
	output logic 		Icache_valid_out        // when this is high
);

	ICACHE_PACKET [`ICACHE_SIZE-1:0] icache_data;

	logic [`ICACHE_IDX_LEN - 1:0] current_index, last_index;
	logic [27 - `ICACHE_IDX_LEN:0] current_tag, last_tag;
  logic [3:0] current_mem_tag;

	assign {current_tag, current_index} = proc2Icache_addr[31:4];

	logic miss_outstanding;

	logic data_write_enable;
	assign data_write_enable = (current_mem_tag == Imem2Icache_tag) && (current_mem_tag != 0);

	logic changed_addr;
	assign changed_addr = (current_index != last_index) || (current_tag != last_tag);

	logic update_mem_tag;
	assign update_mem_tag = changed_addr || miss_outstanding || data_write_enable;

	logic unanswered_miss;
	assign unanswered_miss = changed_addr ? !Icache_valid_out :
											miss_outstanding && (Imem2Icache_response == 0);

	assign Icache2Imem_addr    = {proc2Icache_addr[31:3],3'b0};
	assign Icache2Imem_command = (miss_outstanding && !changed_addr) ?  BUS_LOAD : BUS_NONE;

	assign Icache_data_out = icache_data[current_index].data;
	assign Icache_valid_out = icache_data[current_index].valids && (icache_data[current_index].tags == current_tag);

	// synopsys sync_set_reset "reset"
	always_ff @(posedge clock) begin
		if(reset) begin
			last_index       <= `SD -1;   // These are -1 to get ball rolling when
			last_tag         <= `SD -1;   // reset goes low because addr "changes"
			current_mem_tag  <= `SD 0;
			miss_outstanding <= `SD 0;
			icache_data      <= `SD 0;  
		end else begin
			last_index              <= `SD current_index;
			last_tag                <= `SD current_tag;
			miss_outstanding        <= `SD unanswered_miss;

			if(update_mem_tag) begin
				current_mem_tag     <= `SD Imem2Icache_response;
			end

			if(!changed_addr && data_write_enable) begin // If data came from memory, meaning tag matches
				icache_data[current_index].data     <= `SD Imem2Icache_data;
				icache_data[current_index].tags     <= `SD current_tag;
				icache_data[current_index].valids   <= `SD 1;
			end
		end
	end
endmodule

/*
	only for 3-way design
	If both hit, then read 3 inst in one cycle (purely combinational logic)
	If miss, then at least take 2 cycles to issue read from mem
		first cycle let cache0 load, second cycle let cache1 load
		Icache_valid_out will be high when both load finish

	cache0 reads PC[3] == 0
	cache1 reads PC[3] == 1
*/

module icache_bank(
	input clock,
	input reset,

	// from memory
	input [3:0]  Imem2Icache_response,
	input [63:0] Imem2Icache_data,
	input [3:0]  Imem2Icache_tag,

	// from fetch stage
	input PC_t [2:0] proc2Icache_addr, // 3-way

	// to memory
	output logic [1:0] Icache2Imem_command,
	output PC_t Icache2Imem_addr,

	// to fetch stage
	output inst_t [2:0] Icache_inst_out, 
	output logic Icache_valid_out 
);  
	/*******************************************/
	/*                                         */
	/*             cache 0 module              */
	/*                                         */
	/*******************************************/
	// from memory
	logic [3:0]  mem2cache0_response;
	// from bank
	PC_t cache0_addr;
	// to memory
	logic [1:0] cache02mem_command;
	PC_t cache02mem_addr;
	// data out
	logic [63:0] cache0_data_out;
	logic cache0_valid_out;
	icache icache0(
		.clock(clock), .reset(reset),
		.Imem2Icache_response(mem2cache0_response),
		.Imem2Icache_data(Imem2Icache_data),
		.Imem2Icache_tag(Imem2Icache_tag),
		.proc2Icache_addr(cache0_addr),
		.Icache2Imem_command(cache02mem_command),
		.Icache2Imem_addr(cache02mem_addr),
		.Icache_data_out(cache0_data_out),
		.Icache_valid_out(cache0_valid_out) 
	);

	/*******************************************/
	/*                                         */
	/*             cache 1 module              */
	/*                                         */
	/*******************************************/

	// from memory
	logic [3:0]  mem2cache1_response;
	// from bank
	PC_t cache1_addr;
	// to memory
	logic [1:0] cache12mem_command;
	PC_t cache12mem_addr;
	// data out
	logic [63:0] cache1_data_out;
	logic cache1_valid_out;
	icache icache1(
		.clock(clock), .reset(reset),
		.Imem2Icache_response(mem2cache1_response),
		.Imem2Icache_data(Imem2Icache_data),
		.Imem2Icache_tag(Imem2Icache_tag),
		.proc2Icache_addr(cache1_addr),
		.Icache2Imem_command(cache12mem_command),
		.Icache2Imem_addr(cache12mem_addr),
		.Icache_data_out(cache1_data_out),
		.Icache_valid_out(cache1_valid_out) 
	);

	/*******************************************/
	/*                                         */
	/*         cache 0/1 with mem bus          */
	/*                                         */
	/*******************************************/

	logic cache_on_bus; // cache0 / cache1 occupies memory bus, assume cache0 has higher priority
	assign cache_on_bus = cache02mem_command == BUS_LOAD ? 0 : 1;

	// from memory: response == 0 will stall the cache to let the other cache go
	assign mem2cache0_response = !cache_on_bus ? Imem2Icache_response : 0;
	assign mem2cache1_response = cache_on_bus ? Imem2Icache_response : 0;

	// to memory
	assign Icache2Imem_command = cache_on_bus ? cache12mem_command : cache02mem_command;
	assign Icache2Imem_addr = cache_on_bus ? cache12mem_addr : cache02mem_addr;

	// PC[3] == 0 ? cache0 : cache1
	assign cache0_addr = proc2Icache_addr[0][3] ? 
							{proc2Icache_addr[2][31:3], 3'b0} : {proc2Icache_addr[0][31:3], 3'b0};
	assign cache1_addr = proc2Icache_addr[0][3] ? 
							{proc2Icache_addr[0][31:3], 3'b0} : {proc2Icache_addr[2][31:3], 3'b0};
							
	assign Icache_valid_out = cache0_valid_out & cache1_valid_out;
	// output logic for cache data, 4 conditions:
	/*********************************************/
	//  cache0: [31:16] inst2   [15:0] inst1
	//  cache1:                 [15:0] inst3
	/*********************************************/
	//  cache0: [31:16] inst1   
	//  cache1: [31:16] inst3   [15:0] inst2
	/*********************************************/
	//  cache0:                 [15:0] inst3
	//  cache1: [31:16] inst2   [15:0] inst1
	/*********************************************/
	//  cache0: [31:16] inst3   [15:0] inst2
	//  cache1: [31:16] inst1
	/*********************************************/
	always_comb begin
		Icache_inst_out = 0;
		case(proc2Icache_addr[0][3:2])
			2'b00: begin
				{Icache_inst_out[1], Icache_inst_out[0]} = cache0_data_out;
				Icache_inst_out[2] = cache1_data_out[31:0];
			end
			2'b01: begin
				Icache_inst_out[0] = cache0_data_out[63:32];
				{Icache_inst_out[2], Icache_inst_out[1]} = cache1_data_out;
			end
			2'b10: begin
				Icache_inst_out[2] = cache0_data_out[31:0];
				{Icache_inst_out[1], Icache_inst_out[0]} = cache1_data_out;
			end
			2'b11: begin
				{Icache_inst_out[2], Icache_inst_out[1]} = cache0_data_out;
				Icache_inst_out[0] = cache1_data_out[63:32];
			end
		endcase
	end
endmodule
