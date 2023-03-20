/* DESIGN = p dcache */

`include "sys_defs.svh"

/*
    dcache version 4.0
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

    input                       flush,

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
    MSHR_PACKET [1:0] MSHR_table;   // store 2 loads correspondingly

	logic [2:0] [`DCACHE_IDX_LEN - 1:0] index;
	logic [2:0] [28 - `DCACHE_IDX_LEN:0] tag;
    PC_t [2:0] prev_addr;
	assign {tag[0], index[0]} = proc2Dcache_addr_load[0][31:3];
	assign {tag[1], index[1]} = proc2Dcache_addr_load[1][31:3];
    assign {tag[2], index[2]} = proc2Dcache_addr_store[31:3]; 
    
	// load output
	assign Dcache_data_out[0] = dcache_data[index[0]].data;
	assign Dcache_data_out[1] = dcache_data[index[1]].data;
	assign Dcache_valid_out[0] = dcache_data[index[0]].valids && (dcache_data[index[0]].tags == tag[0]);
	assign Dcache_valid_out[1] = dcache_data[index[1]].valids && (dcache_data[index[1]].tags == tag[1]);

    // whether load/store is relevant to pending load (accepted yet data not loaded)
    logic [2:0] relevant_to_pendig_miss;
    assign relevant_to_pendig_miss[0] = MSHR_table[1].mem_tag != 0 && proc2Dcache_addr_load[0] == MSHR_table[1].miss_addr;
    assign relevant_to_pendig_miss[1] = MSHR_table[0].mem_tag != 0 && proc2Dcache_addr_load[1] == MSHR_table[0].miss_addr;
    assign relevant_to_pendig_miss[2] = (MSHR_table[0].mem_tag != 0 && proc2Dcache_addr_store == MSHR_table[0].miss_addr) ||
                                        (MSHR_table[1].mem_tag != 0 && proc2Dcache_addr_store == MSHR_table[1].miss_addr);

    // whether load/store request is waiting to be accepted, triggered by outside enable signal
    logic [2:0] waiting_for_response;
    assign waiting_for_response[0] = load_en[0] && !Dcache_valid_out[0] && !relevant_to_pendig_miss[0];
    assign waiting_for_response[1] = load_en[1] && !Dcache_valid_out[1] && !relevant_to_pendig_miss[1];
    assign waiting_for_response[2] = store_en && !relevant_to_pendig_miss[2];

    /***************************************************************************************************/

    // whether current operation starts (command is BUS_LOAD, BUS_STORE, or BUS_NONE)
	logic [3:0] operation;
	logic [3:0] operation_next;

    /***************************************************************************************************/     

    logic changed_addr;
    assign changed_addr = operation_next[0] ? prev_addr[0] != proc2Dcache_addr_load[0] :
                            operation_next[1] ? prev_addr[1] != proc2Dcache_addr_load[1] :
                            operation_next[2] ? prev_addr[2] != proc2Dcache_addr_store : 0;
    logic new_request;
    assign new_request = operation_next != 0 && (operation_next != operation || changed_addr); // operation_next = 000 means no operation
    logic unanswered_miss, miss_outstanding, current_miss;
    assign current_miss = miss_outstanding && Dmem2Dcache_response == 0;
    assign unanswered_miss = new_request || current_miss;

    assign load_store_accepted[0] = (!current_miss && operation[0]) || relevant_to_pendig_miss[0];
    assign load_store_accepted[1] = (!current_miss && operation[1]) || relevant_to_pendig_miss[1];
    assign load_store_accepted[2] = !current_miss && operation[2];

    /****************************************************************************************************/
    // update MSHR or clear the entry

    logic [2:0] data_write_enable;  // signal to update load/store data in cache
    assign data_write_enable[0] = (MSHR_table[0].mem_tag != 0) && (MSHR_table[0].mem_tag == Dmem2Dcache_tag);
    assign data_write_enable[1] = (MSHR_table[1].mem_tag != 0) && (MSHR_table[1].mem_tag == Dmem2Dcache_tag);
    assign data_write_enable[2] = operation_next[2];

    logic [1:0] update_MSHR_enable; // update MSHR when there's response(accepted)
    assign update_MSHR_enable[0] = (!current_miss && operation[0]) && !relevant_to_pendig_miss[0];
    assign update_MSHR_enable[1] = (!current_miss && operation[1]) && !relevant_to_pendig_miss[1];

    /*****************************************************************************************************/
    // output to memory
    // assign Dcache2Dmem_addr = operation_next[2] ? proc2Dcache_addr_store :
    //                         operation_next[0] ? proc2Dcache_addr_load[0] :
    //                         operation_next[1] ? proc2Dcache_addr_load[1] : 64'b0;
    // assign Dcache2Dmem_data = proc2Dcache_data_store;
    // assign Dcache2Dmem_command = operation[2] ? BUS_STORE :
    //                             (operation[0] | operation[1]) ? BUS_LOAD : BUS_NONE;

    logic bus_filled;
    always_comb begin
        operation_next = operation;
        bus_filled = operation_next[0] | operation_next[1] | operation_next[2];
        Dcache2Dmem_addr = operation_next[2] ? proc2Dcache_addr_store :
                         operation_next[0] ? proc2Dcache_addr_load[0] :
                         operation_next[1] ? proc2Dcache_addr_load[1] : 64'b0;
        Dcache2Dmem_data = proc2Dcache_data_store;
        Dcache2Dmem_command = operation_next[2] ? BUS_STORE :
                                (operation_next[0] | operation_next[1]) ? BUS_LOAD : BUS_NONE;

        // if store and load starts in same cycle, store has higher priority
        // when relevant to pending miss
        // if load after load, the second load is accepted directly
        // if store after load, store is blocked until pending miss is completed
        for (int i=2; i>=0; i--)begin
            if(waiting_for_response[i] && !bus_filled)begin
                operation_next[i] = 1;
                bus_filled = 1;
            end

            // when there's response, clear
            if(load_store_accepted[i] && operation[i])begin
                operation_next[i] = 0;
                // when store signal is accepted, we can assume store is completed
            end
        end
    end

    always_ff @(posedge clock) begin
        if(reset)begin
            dcache_data             <= `SD 0;
            MSHR_table              <= `SD 0;
            operation               <= `SD 0;
            prev_addr               <= `SD 0;
        end else if (flush)begin
            // clear all pending loads/stores
            MSHR_table              <= `SD 0;
            operation               <= `SD 0;
            prev_addr               <= `SD 0;
        end else begin
            operation               <= `SD operation_next;
            miss_outstanding        <= `SD unanswered_miss;
            prev_addr[2]            <= `SD proc2Dcache_addr_store;

            for(int i=0; i<2; i++)begin
                prev_addr[i]        <= `SD proc2Dcache_addr_load[i];

                if(update_MSHR_enable[i])begin
                    MSHR_table[i].mem_tag   <= `SD Dmem2Dcache_response;
                    MSHR_table[i].miss_addr <= `SD proc2Dcache_addr_load[i];
                end else if(data_write_enable[i])begin
                    // clear miss table when load finishes
                    MSHR_table[i].mem_tag   <= `SD 0;
                    MSHR_table[i].miss_addr <= `SD 0;
                end
            end
            
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
