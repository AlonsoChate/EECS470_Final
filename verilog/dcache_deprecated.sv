`include "sys_defs.svh"

/*
    dcache version 3.0
*/

// 32 bit PC, 3 bit offset -> 29 bit for index and tag
typedef struct packed {
	logic [63:0]						data;
	logic [28 - `DCACHE_IDX_LEN:0]		tags;
	logic								valids;
} DCACHE_PACKET;

// Miss status handling registers
typedef struct packed {
    PC_t            miss_addr;
	logic [3:0]     mem_tag;    // mem_tag == 0 indicates entry is invalid
} MSHR_PACKET;

typedef enum logic [1:0] {
	NO_MISS         = 2'h0,
	LOAD_MISS       = 2'h1,
	STORE_MISS      = 2'h2
} MISS_STATE;

/*
    control logic used when there's miss (load or store), trigger one load/store at a time. until it's accepted (not necessarily finished4
    special case:
        Load A -> Load A accepted (get response) -> Store A -> Store A blocked by pending Load A and is not accepted,
        in this case cannot lauch another Load until Store A is accepted
        
*/
module dcache_miss_control(
    input clock, reset,

    // from memory
    input [3:0]         Dmem2Dcache_response,
    input [3:0]         Dmem2Dcache_tag,

    // addr for store or load
    input PC_t          Dcache2Dcache_ctrl_addr,
    input MISS_STATE    miss_command,               // control command for dcache, should be given before posedge clock

    // to dcache
    output logic [2:0]  data_write_enable,          // whether load/store data can be written to dcache
    output logic        accepted,                   // whether load/store is accepted (not finished) (raised at negedge clock)
                                                    // *accepted* is only meaning full when there's miss_command

    // to memory, also used for store in dcache
    output logic [1:0]  Dcache2Dmem_command,
    output PC_t         Dcache2Dmem_addr
);
    MSHR_PACKET [2:0] MSHR_table;   // 2 loads

    logic relevant_to_pendig_miss;
    assign relevant_to_pendig_miss =    (MSHR_table[0].mem_tag != 0 && Dcache2Dcache_ctrl_addr == MSHR_table[0].miss_addr) ||
                                        (MSHR_table[1].mem_tag != 0 && Dcache2Dcache_ctrl_addr == MSHR_table[1].miss_addr);

    /***************************************************************************************************/
    // logic for correct accepted signal, last only half cycle
    PC_t prev_ctrl_addr;
    MISS_STATE prev_command;
    logic changed_addr, changed_command, new_request;
    assign changed_addr = prev_ctrl_addr != Dcache2Dcache_ctrl_addr;
    assign changed_command = prev_command != miss_command;
    assign new_request = miss_command != NO_MISS && (changed_command || changed_addr);
    logic unanswered_miss, miss_outstanding;
    assign unanswered_miss = new_request || (miss_outstanding && Dmem2Dcache_response != 0);

    assign accepted = !unanswered_miss || (miss_command == LOAD_MISS && relevant_to_pendig_miss);
    /***************************************************************************************************/                          

    // whether load data from mem is retrieved
    assign data_write_enable[0] = (MSHR_table[0].mem_tag != 0) && (MSHR_table[0].mem_tag == Dmem2Dcache_tag);
    assign data_write_enable[1] = (MSHR_table[1].mem_tag != 0) && (MSHR_table[1].mem_tag == Dmem2Dcache_tag);

    // if write to pending miss, wait until pending miss complete
    logic blocked_store;
    assign blocked_store = miss_command == STORE_MISS && relevant_to_pendig_miss;

    logic update_MSHR_enable;
    assign update_MSHR_enable = miss_command == LOAD_MISS && !relevant_to_pendig_miss;

    assign Dcache2Dmem_addr = {Dcache2Dcache_ctrl_addr[31:3], 3'b0};

    logic [1:0]  Dcache2Dmem_command_next;

    always_comb begin
        Dcache2Dmem_command_next = BUS_NONE;
        data_write_enable[2] = 0;

		if(miss_command == STORE_MISS && !relevant_to_pendig_miss)begin
            data_write_enable[2] = 1;
            Dcache2Dmem_command_next = BUS_STORE;
        end

        // start load and backed up in MSHR
        if(miss_command == LOAD_MISS && !relevant_to_pendig_miss)begin
            Dcache2Dmem_command_next = BUS_LOAD;
        end

        // load or store is accepted
        if(accepted)begin
            Dcache2Dmem_command_next = BUS_NONE;
        end

        // when load finishes, check if there's store blocked by load
        // if there's a store blocked by load, no need to worry another load following 
        // the store since store is not accepted yet
        if((data_write_enable[0] | data_write_enable[1]) && blocked_store)begin
            Dcache2Dmem_command_next = BUS_STORE;
            data_write_enable[2] = 1;
        end
	end

    always_ff @(posedge clock) begin
        if(reset)begin
            MSHR_table              <= `SD 0;
        end else begin
            Dcache2Dmem_command     <= `SD Dcache2Dmem_command_next;
            prev_ctrl_addr          <= `SD Dcache2Dcache_ctrl_addr;
            prev_command            <= `SD miss_command;
            miss_outstanding        <= `SD unanswered_miss;
            if(update_MSHR_enable)begin
                // at most 2 load pending, find an available table
                if(MSHR_table[0].mem_tag == 0)begin
                    MSHR_table[0].mem_tag   <= `SD Dmem2Dcache_response;
                    MSHR_table[0].miss_addr <= `SD Dcache2Dcache_ctrl_addr;
                end else begin 
                    MSHR_table[1].mem_tag   <= `SD Dmem2Dcache_response;
                    MSHR_table[1].miss_addr <= `SD Dcache2Dcache_ctrl_addr;
                end
            end

            for(int i=0; i<2; i++)begin
                // clear miss table when load finishes
                if(data_write_enable[i])begin
                    MSHR_table[i].mem_tag   <= `SD 0;
                    MSHR_table[i].miss_addr <= `SD 0;
                end
            end
        end
    end
endmodule

/*
	supports 2 Load and 1 store query at the same time
    store must be issued when last store is accepted
    store_acccept means store has finished
    load_accepted means load signal is received, load is finished when Dcache_valid_out is high
*/

module dcache(
	input                       clock, reset,

	// from memory
	input [3:0]                 Dmem2Dcache_response,
	input [63:0]                Dmem2Dcache_data,
	input [3:0]                 Dmem2Dcache_tag,            // when tag == response != 0, then load finishes; no response for store finish

	// from Load process
	input PC_t [1:0]            proc2Dcache_addr_load,
	input [1:0]                 load_en,					// load_en should be reset when load_accepted

	// from store
	input PC_t                  proc2Dcache_addr_store,
	input [63:0]                proc2Dcache_data_store,
	input                       store_en,                   // store_en should be reset when store_accepted

	// to memory
	output logic [1:0]          Dcache2Dmem_command,
	output PC_t                 Dcache2Dmem_addr,
	output logic [63:0]         Dcache2Dmem_data,

	// to Load process
	output logic [1:0] [63:0]   Dcache_data_out,
	output logic [1:0]          Dcache_valid_out,

    // to load/store process
    output logic [2:0]          load_store_accepted         // whether store/load is accepted. 0 and 1 for load, 2 for store
                                                            // store may be blocked by too many pending loads/stores
);
	DCACHE_PACKET [`DCACHE_SIZE-1:0] dcache_data;

	logic [2:0] [`DCACHE_IDX_LEN - 1:0] index;
	logic [2:0] [28 - `DCACHE_IDX_LEN:0] tag;

	assign {tag[0], index[0]} = proc2Dcache_addr_load[0][31:3];
	assign {tag[1], index[1]} = proc2Dcache_addr_load[1][31:3];
    // for store, we use the data/addr that is send from miss_control to mem
    assign {tag[2], index[2]} = Dcache2Dmem_addr[31:3]; 
    
	// load output
	assign Dcache_data_out[0] = dcache_data[index[0]].data;
	assign Dcache_data_out[1] = dcache_data[index[1]].data;
	assign Dcache_valid_out[0] = dcache_data[index[0]].valids && (dcache_data[index[0]].tags == tag[0]);
	assign Dcache_valid_out[1] = dcache_data[index[1]].valids && (dcache_data[index[1]].tags == tag[1]);

    MISS_STATE miss_command;
    logic [2:0] data_write_enable;  // signal to update load/store data in cache
    logic accepted;          
    PC_t Dcache2Dcache_ctrl_addr;
    dcache_miss_control dcache_miss(
        .clock(clock), .reset(reset),
        // from memory
        .Dmem2Dcache_response(Dmem2Dcache_response),
        .Dmem2Dcache_tag(Dmem2Dcache_tag),
        // addr for store or load
        .Dcache2Dcache_ctrl_addr(Dcache2Dcache_ctrl_addr),
        .miss_command(miss_command),
        // to dcache
        .data_write_enable(data_write_enable),
        .accepted(accepted),
        // to memory
        .Dcache2Dmem_command(Dcache2Dmem_command),
        .Dcache2Dmem_addr(Dcache2Dmem_addr)
    );

    // whether current operation is waiting for response from mem,
	// also means whether the operation is blocked by other operation
	logic [2:0] waiting_for_response;

    // whether current operation starts (command is BUS_LOAD or BUS_STORE)
	logic [3:0] operation_start;
	logic [3:0] operation_start_next;
	 
	// whether there's operation on bus for next cycle
	logic bus_filled;
	assign bus_filled = operation_start_next[0] | operation_start_next[1] | operation_start_next[2];

    assign miss_command = operation_start_next[2] ? STORE_MISS :
                            operation_start_next[0] | operation_start_next[1] ? LOAD_MISS : NO_MISS;
    assign Dcache2Dcache_ctrl_addr = operation_start_next[2] ? proc2Dcache_addr_store :
                            operation_start_next[0] ? proc2Dcache_addr_load[0] :
                            operation_start_next[1] ? proc2Dcache_addr_load[1] : 64'b0;
    assign Dcache2Dmem_data = proc2Dcache_data_store;

    assign waiting_for_response[0] = load_en[0] && !Dcache_valid_out[0];
    assign waiting_for_response[1] = load_en[1] && !Dcache_valid_out[1];
    assign waiting_for_response[2] = store_en;


    always_comb begin
        operation_start_next = operation_start;
        load_store_accepted = 0;

        // if store and load starts in same cycle, store has higher priority
        for (int i=2; i>=0; i--)begin
            if(waiting_for_response[i] && !bus_filled)
                operation_start_next[i] = 1;
        end

        // when there's response, clear 
        for(int i=0; i<3; i++)begin
            if(accepted && operation_start[i])begin
                operation_start_next[i] = 0;
                // when store signal is accepted, we can assume store is completed
                load_store_accepted[i] = 1;
            end
        end	
    end

    always_ff @(posedge clock) begin
        if(reset)begin
            dcache_data             <= `SD 0;
            operation_start         <= `SD 0;
        end else begin
            operation_start         <= `SD operation_start_next;
            
            // update data
            for (int i=0; i<3; i++)begin
                if(data_write_enable[i])begin
                    dcache_data[index[i]].data     <= `SD (i!=2 ? Dmem2Dcache_data : Dcache2Dmem_data);
                    dcache_data[index[i]].tags     <= `SD tag[i];
                    dcache_data[index[i]].valids   <= `SD 1;
                end
            end
        end
    end
endmodule
