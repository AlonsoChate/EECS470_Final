`timescale 1ns/100ps
/* SOURCE = cache_ctrl.sv mem.sv dcache.sv */

`include "sys_defs.svh"

module cctb;

`define CACHE_MODE

logic clock, reset;
// mem signals
logic [`XLEN-1:0] proc2mem_addr;
logic [3:0] mem2proc_tag, mem2proc_response;
logic [1:0] proc2mem_command;
logic [63:0] proc2mem_data, mem2proc_data;

mem memory (
    .clk(clock),
    .proc2mem_addr(proc2mem_addr),
    .proc2mem_data(proc2mem_data),
    .proc2mem_command(proc2mem_command),
    // output
    .mem2proc_response(mem2proc_response),
    .mem2proc_data(mem2proc_data),
    .mem2proc_tag(mem2proc_tag)
); // the system memory

// cc load
logic [1:0][63:0] Dcache_data_out;
logic [1:0] Dcache_valid_out;
logic [1:0] load_accepted;

logic [1:0][`XLEN-1:0] load_addr;
logic [1:0] load_en;
// cc store
logic [`XLEN-1:0] store_addr;
logic [31:0] store_data;
logic store_en, is_32_bit, is_16_bit, store_accepted;

cache_ctrl cc(
    .clock(clock), .reset(reset),
    // from memory
    .Dmem2Dcache_response(mem2proc_response),
    .Dmem2Dcache_data(mem2proc_data),
    .Dmem2Dcache_tag(mem2proc_tag),          
    // from Load FU
    .proc2Dcache_addr_load(load_addr),
    .load_en(load_en),
    // from store queue
    .proc2Dcache_addr_store(store_addr),
    .proc2Dcache_data_store(store_data),
    .store_en(store_en),      
    .is_32_bit(is_32_bit),        
    .is_16_bit(is_16_bit),           
    // to memory
    .Dcache2Dmem_command(proc2mem_command),
    .Dcache2Dmem_addr(proc2mem_addr),
    .Dcache2Dmem_data(proc2mem_data),
    // to Load FU
    .Dcache_data_out(Dcache_data_out),
    .Dcache_valid_out(Dcache_valid_out),
    .load_accepted(load_accepted),
    // to store queue
    .store_accepted(store_accepted)              // store may be blocked by too many pending loads/stores
);

// load[0] or load[1]
logic port;
task automatic single_load(input logic[63:0] addr, output logic[63:0] data);
    int cycles_waited = 0;
    load_addr[port] = addr;
    load_en[port] = 1;
    #1;
    if (Dcache_valid_out[port]) begin
        data = Dcache_data_out[port];
        load_en[port] = 0;
        $display("Load[%d] Read address [%0h]=%0h took %0d cycles", port, addr, data, cycles_waited);
        return;
    end else begin
        while(1) begin
            @(posedge clock);
            if(load_accepted[port])
                load_en[port] = 0;
            @(negedge clock);
            ++cycles_waited;
            if(Dcache_valid_out[port]) begin
                data = Dcache_data_out[port];
                $display("Load[%0d] Read address [%0h]=%0h took %0d cycles", port, addr, data, cycles_waited);
                break;
            end
        end
    end
endtask

task automatic relevant_load(input logic[63:0] addr);
    $display("Load from same address!");

    $display("Both loads get data!");
endtask

task automatic single_store(input logic[63:0] addr, input logic[31:0] data);
    int cycles_waited = 0;
    store_addr = addr;
    store_data = data;
    store_en = 1;
    is_32_bit = 0;
    is_16_bit = 0;
    $display("Store test!");

    while(1) begin
        @(posedge clock);
        if(store_accepted)begin
            store_en = 0;
            $display("Store %0h to address [%0h] took %0d cycles", data, addr, cycles_waited);
            break;
        end
        @(negedge clock);
        ++cycles_waited;
    end
    $display("Store finish!");
endtask

logic [63:0] clock_count;
logic [63:0] mem_data;
logic start;

initial begin
    $display("TB Start!");
    clock = 0;
    reset = 1;
    start = 0;

    load_addr = 0;
    load_en = 0;

    store_addr = 0;
    store_data = 0;
    store_en = 0;
    is_32_bit = 0;
    is_16_bit = 0;


    @(negedge clock);
    @(negedge clock);
    @(negedge clock);
    reset = 0;
    @(negedge clock);
    for (int i = 0; i < 1024; ++i) begin
        memory.unified_memory[i] = i;
    end
    repeat (10) @(negedge clock);
    
    start = 1;
    port = 0;
    // single_store(2048, 1000);

    // single_load(2018, mem_data);
    single_load(8, mem_data);

    
    @(negedge clock);
    @(negedge clock);

    $finish;
end

always_ff @(posedge clock) begin
    if(start)begin
        $display("@@@@@ clock: %d", clock_count);

        $display("");
        $display("@@ MEM IO:");
        $display("input: addr: %h, command: %d", proc2mem_addr, proc2mem_command);
        $display("output: response: %d, tag: %d", mem2proc_response, mem2proc_tag);

        $display("");
        $display("@@ Load/Store outside signal:");
        for (int i = 0; i < 2; i++) begin
            $display("FU %0d load_en: %d, load_accepted: %d",i , load_en[i], load_accepted[i]);
        end
        $display("store_en: %d, store_accepted: %d", store_en, store_accepted);

        $display("");
        $display("@@ D$ IO:");
        for (int i = 0; i < 2; i++) begin
            $display("%0d   load_en_ctrl: %d, load_accepted: %d", i, cc.load_en_ctrl[i], cc.load_store_accepted[i]);
            $display("      load_addr: %h", cc.proc2Dcache_addr_load_ctrl[i]);
            $display("      Dcache_valid_out_ctrl: %d", cc.Dcache_valid_out_ctrl[i]);
        end
        $display("store_en_ctrl: %d, store_accepted: %d", cc.store_en_ctrl, cc.load_store_accepted[2]);
        $display("store_data_ctrl: %h", cc.proc2Dcache_data_store_ctrl);

        $display("");
        $display("@@ CC data:");
        $display("state: %d, state_next: %d", cc.state, cc.state_next);
        $display("\n");
    end
end

always begin 
    #5 clock = ~clock;
end

always_ff @(posedge clock) begin
    if(reset) begin
        clock_count <= 0;
    end else begin
        clock_count <= clock_count + 1;
        if (clock_count > 10000) begin
            $display("Too many cycles passed");
            $finish;
        end
    end
end


endmodule