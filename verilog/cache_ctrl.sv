/* DESIGN = p cache_ctrl */

`include "sys_defs.svh"

// store 32 situation
typedef enum logic [1:0] {
    NO_LOAD         = 2'h0,     // load[1] is not used, or STOER's load has not been accepted
    ORIG_LOAD       = 2'h1,     // load[1] is occupied by load from load FU
    PROC_STORE      = 2'h2      // load[1] is used by store 
} LOAD_STATE;

/*
    combine 8/16/32 bits of data to be stored to the loaded 64 bits data
    purely combinational logic
*/
module combine_store(
    input               is_16_bit,
    input               is_32_bit,
    input PC_t          store_addr,
    input [63:0]        loaded_64_data,
    input [31:0]        store_32_data,
    output logic [63:0] combined_64_data
);
    always_comb begin
        if (is_32_bit) begin
            // store 32 bits
            if (store_addr[2] == 1'b0) begin
                combined_64_data = {loaded_64_data[63:32], store_32_data[31:0]};
            end else begin
                combined_64_data = {store_32_data[31:0], loaded_64_data[31:0]};
            end
        end else if (is_16_bit) begin
            // store 16 bits
            if (store_addr[2:1] == 2'b00) begin
                combined_64_data = {loaded_64_data[63:16], store_32_data[15:0]};
            end else if (store_addr[2:1] == 2'b01) begin
                combined_64_data = {loaded_64_data[63:32], store_32_data[15:0], loaded_64_data[15:0]};
            end else if (store_addr[2:1] == 2'b10) begin
                combined_64_data = {loaded_64_data[63:48], store_32_data[15:0], loaded_64_data[31:0]};
            end else if (store_addr[2:1] == 2'b11) begin
                combined_64_data = {store_32_data[15:0], loaded_64_data[47:0]};
            end
        end else begin
            // store 8 bits
            if (store_addr[2:0] == 3'b000) begin
                combined_64_data = {loaded_64_data[63:8], store_32_data[7:0]};
            end else if (store_addr[2:0] == 3'b001) begin
                combined_64_data = {loaded_64_data[63:16], store_32_data[7:0], loaded_64_data[7:0]};
            end else if (store_addr[2:0] == 3'b010) begin
                combined_64_data = {loaded_64_data[63:24], store_32_data[7:0], loaded_64_data[15:0]};
            end else if (store_addr[2:0] == 3'b011) begin
                combined_64_data = {loaded_64_data[63:32], store_32_data[7:0], loaded_64_data[23:0]};
            end else if (store_addr[2:0] == 3'b100) begin
                combined_64_data = {loaded_64_data[63:40], store_32_data[7:0], loaded_64_data[31:0]};
            end else if (store_addr[2:0] == 3'b101) begin
                combined_64_data = {loaded_64_data[63:48], store_32_data[7:0], loaded_64_data[39:0]};
            end else if (store_addr[2:0] == 3'b110) begin
                combined_64_data = {loaded_64_data[63:56], store_32_data[7:0], loaded_64_data[47:0]};
            end else if (store_addr[2:0] == 3'b111) begin
                combined_64_data = {store_32_data[7:0], loaded_64_data[55:0]};
            end
        end
    end
endmodule

/*
    when there's store instruction, store will occupy load[1] to read data, load[0] function normally
    load[1] is freed only when store is accepted, i.e., store is completed

    **NOTE** : accepted signal only lasts half cycle, from negedge to posedge
*/

module cache_ctrl(
    input                       clock, reset,

    // from memory
    input [3:0]                 Dmem2Dcache_response,
    input [63:0]                Dmem2Dcache_data,
    input [3:0]                 Dmem2Dcache_tag,          

    // from Load FU
    input PC_t [1:0]            proc2Dcache_addr_load,
    input [1:0]                 load_en,                  // load_en should be reset when load_accepted

    // from store queue
    input PC_t                  proc2Dcache_addr_store,
    input [31:0]                proc2Dcache_data_store,
    input                       store_en,                 // store_en should be reset when store_accepted
    input                       is_32_bit,                // set high when the store is 32 bit 
    input                       is_16_bit,                // set high when store is 16 bit

    input                       flush,                    // clear pending loads/stores

    // to memory
    output logic [1:0]          Dcache2Dmem_command,
    output PC_t                 Dcache2Dmem_addr,
    output logic [63:0]         Dcache2Dmem_data,

    // to Load FU
    output logic [1:0] [63:0]   Dcache_data_out,
    output logic [1:0]          Dcache_valid_out,
    output logic [1:0]          load_accepted,

    // to store queue
    output logic                store_accepted              // store may be blocked by too many pending loads/stores
);
    PC_t [1:0]      proc2Dcache_addr_load_ctrl;     // load addr to cache
    logic [63:0]    proc2Dcache_data_store_ctrl;    // real data stored to cache
    logic [1:0]     load_en_ctrl;	
    logic           store_en_ctrl;
    logic [1:0]     Dcache_valid_out_ctrl;  // before output to Load FU
    logic [2:0]     load_store_accepted;    // before output to load/store

    LOAD_STATE      state, state_next;      // state of load[1]
    PC_t            proc2Dcache_addr_store_ctrl;
    assign proc2Dcache_addr_store_ctrl = {proc2Dcache_addr_store[31:3], 3'b0};

    dcache dcache_inst(
        .clock(clock), .reset(reset),
        // from memory
        .Dmem2Dcache_response(Dmem2Dcache_response),
        .Dmem2Dcache_data(Dmem2Dcache_data),
        .Dmem2Dcache_tag(Dmem2Dcache_tag),
        // from Load FU
        .proc2Dcache_addr_load(proc2Dcache_addr_load_ctrl),
        .load_en(load_en_ctrl),
        // from store queue
        .proc2Dcache_addr_store(proc2Dcache_addr_store_ctrl),
        .proc2Dcache_data_store(proc2Dcache_data_store_ctrl),
        .store_en(store_en_ctrl),
        // flush
        .flush(flush),
        // to memory
        .Dcache2Dmem_command(Dcache2Dmem_command),
        .Dcache2Dmem_addr(Dcache2Dmem_addr),
        .Dcache2Dmem_data(Dcache2Dmem_data),
        // to Load FU
        .Dcache_data_out(Dcache_data_out),
        .Dcache_valid_out(Dcache_valid_out_ctrl),
        // to store queue
        .load_store_accepted(load_store_accepted)
    );

    combine_store combine0(
        .is_16_bit(is_16_bit),
        .is_32_bit(is_32_bit),
        .store_addr(proc2Dcache_addr_store),
        .loaded_64_data(Dcache_data_out[1]),    // use load[1] to load data before store
        .store_32_data(proc2Dcache_data_store),
        // output
        .combined_64_data(proc2Dcache_data_store_ctrl) // real data to be stored in dcache
    );

    always_ff @(posedge clock) begin
        if (reset || flush) begin
            state      <= `SD NO_LOAD;
        end else begin
            state      <= `SD state_next;
        end
    end

    assign proc2Dcache_addr_load_ctrl[0] = {proc2Dcache_addr_load[0][31:3], 3'b0};
    logic relevant_load_store;
    always_comb begin
        state_next = state;

        // load[0] is usually not affected
        load_en_ctrl[0] = load_en[0];
        Dcache_valid_out[0] = Dcache_valid_out_ctrl[0];
        load_accepted[0] = load_store_accepted[0];

        // load[1] connections
        load_en_ctrl[1] = load_en[1];
        proc2Dcache_addr_load_ctrl[1] = {proc2Dcache_addr_load[1][31:3], 3'b0};
        Dcache_valid_out[1] = Dcache_valid_out_ctrl[1];
        load_accepted[1] = load_store_accepted[1];

        // store connections
        store_en_ctrl = store_en;
        store_accepted = load_store_accepted[2];

        // speciall case when load[0] to and store from same address
        relevant_load_store = load_en[0] && (store_en || state == PROC_STORE) 
            && (proc2Dcache_addr_load[0] == proc2Dcache_addr_store_ctrl);

        case(state)
            // there's no load in load[1], or load[1] request has not been
            // accepted when processing store
            NO_LOAD: begin
                // if load_en and store_en both occur, store has higher priority
                if(store_en)begin
                    // start load for store ahead of clock edge
                    load_en_ctrl[1] = 1;
                    proc2Dcache_addr_load_ctrl[1] = proc2Dcache_addr_store_ctrl;
                    // pause load FU if any
                    Dcache_valid_out[1] = 0;
                    load_accepted[1] = 0;
                    // pause store for now
                    store_en_ctrl = 0;
                    store_accepted = 0;
                    // switch state until load command is accepted or load is a hit
                    // make sure load_en signal to D$ is reset after accepted
                    if(load_store_accepted[1] || Dcache_valid_out_ctrl[1])begin
                        load_en_ctrl[1] = 0;
                        state_next = PROC_STORE;
                    end

                    if(relevant_load_store)begin
                        // when store A and load[0] A come together, or load[0] A come when store A is processing, stall load[0] until store finish
                        load_en_ctrl[0] = 0;
                        Dcache_valid_out[0] = 0;
                        load_accepted[0] = 0;
                    end
                end else if(load_en[1] && !Dcache_valid_out_ctrl[1])begin
                    // load connections unchanged to start load ahead of clock edge
                    state_next = ORIG_LOAD;
                end
            end

            ORIG_LOAD: begin
                // load connections unchanged
                // pause store if any
                store_en_ctrl = 0; 
                store_accepted = 0;

                // give one cycle to let load result enter cq
                if (Dcache_valid_out_ctrl[1]) begin
                    state_next = NO_LOAD;
                end
            end

            PROC_STORE: begin
                // load connections
                load_en_ctrl[1] = 0;        // load has been accepted
                // still need to maintain address to keep the data read until store is complete
                proc2Dcache_addr_load_ctrl[1] = proc2Dcache_addr_store_ctrl;
                Dcache_valid_out[1] = 0;    // stall FU load if any
                load_accepted[1] = 0;
                // store connections
                store_en_ctrl = 0;
                store_accepted = 0;

                if(relevant_load_store)begin
                    // when store A and load[0] A come together, or load[0] A come when store A is processing, stall load[0] until store finish
                    load_en_ctrl[0] = 0;
                    Dcache_valid_out[0] = 0;
                    load_accepted[0] = 0;
                end

                // wait for store data to be correct
                if (Dcache_valid_out_ctrl[1]) begin
                    // when load complete, start store
                    store_en_ctrl = store_en; 
                    store_accepted = load_store_accepted[2];
                    if(store_accepted)begin
                        state_next = NO_LOAD;
                    end
                end
            end
        endcase
    end
endmodule
