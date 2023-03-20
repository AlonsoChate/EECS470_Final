`timescale 1ns/100ps
/* SOURCE = dcache.sv mem.sv */

`include "sys_defs.svh"

module dcachetb;

`define CACHE_MODE

logic clock, reset;
// mem signals
logic [`XLEN-1:0] proc2mem_addr;
logic [3:0] mem2proc_tag, mem2proc_response;
logic [1:0] proc2mem_command;
logic [63:0] proc2mem_data, mem2proc_data;


logic [1:0][63:0] Dcache_data_out;
logic [1:0] Dcache_valid_out;
logic [2:0]  load_store_accepted;

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

logic [1:0][`XLEN-1:0] load_addr;
logic [1:0] load_en;

logic [`XLEN-1:0] store_addr;
logic [63:0] store_data;
logic store_en;

dcache d (
    .clock(clock), .reset(reset),
	// from memory
	.Dmem2Dcache_response(mem2proc_response),
	.Dmem2Dcache_data(mem2proc_data),
	.Dmem2Dcache_tag(mem2proc_tag),
	// from Load process
	.proc2Dcache_addr_load(load_addr),
	.load_en(load_en),
	// from store
	.proc2Dcache_addr_store(store_addr),
	.proc2Dcache_data_store(store_data),
	.store_en(store_en),
	// to memory
	.Dcache2Dmem_command(proc2mem_command),
	.Dcache2Dmem_addr(proc2mem_addr),
	.Dcache2Dmem_data(proc2mem_data),
	// to Load process
	.Dcache_data_out(Dcache_data_out),
	.Dcache_valid_out(Dcache_valid_out),
    // to load/store process
    .load_store_accepted(load_store_accepted)
);

// load[0]
task automatic read_addr0(input logic[63:0] addr, output logic[63:0] data);
    int cycles_waited = 0;
    load_addr[0] = addr;
    load_en[0] = 1;
    #1;
    if (Dcache_valid_out[0]) begin
        data = Dcache_data_out[0];
        load_en[0] = 0;
        $display("Load[0] Read address [%0h]=%0h took %0d cycles", addr, data, cycles_waited);
        return;
    end else begin
        while(1) begin
            @(posedge clock);
            if(load_store_accepted[0])
                load_en[0] = 0;
            @(negedge clock);
            ++cycles_waited;
            if(Dcache_valid_out[0]) begin
                data = Dcache_data_out[0];
                $display("Load[0] Read address [%0h]=%0h took %0d cycles", addr, data, cycles_waited);
                break;
            end
        end
    end
endtask

// load[1]
task automatic read_addr1(input logic[63:0] addr, output logic[63:0] data);
    int cycles_waited = 0;
    load_addr[1] = addr;
    load_en[1] = 1;
    #1;
    if (Dcache_valid_out[1]) begin
        data = Dcache_data_out[1];
        load_en[1] = 0;
        $display("Load[1] Read address [%0h]=%0h took %0d cycles", addr, data, cycles_waited);
        return;
    end else begin
        while(1) begin
            @(posedge clock);
            if(load_store_accepted[1])
                load_en[1] = 0;
            @(negedge clock);
            ++cycles_waited;
            if(Dcache_valid_out[1]) begin
                data = Dcache_data_out[1];
                $display("Load[1] Read address [%0h]=%0h took %0d cycles", addr, data, cycles_waited);
                break;
            end
        end
    end
endtask


task automatic relevant_load(input logic[63:0] addr);
    $display("Load from same address!");
    // same cycle load
    load_addr[0] = addr;
    load_addr[1] = addr;
    load_en[0] = 1;
    load_en[1] = 1;
    while(1)begin
        @(posedge clock);
        if(load_store_accepted[1])begin
            load_en[1] = 0;
        end
        if(load_store_accepted[0])begin
            load_en[0] = 0;
        end
        if(Dcache_valid_out[0] && Dcache_valid_out[1])begin
            @(posedge clock);
            @(posedge clock);
            break;
        end
    end
    $display("Both loads get data!");
endtask

task automatic store_test(input logic[63:0] addr, input logic[63:0] data);
    $display("Store test!");
    store_en = 1;
    store_addr = addr;
    store_data = data;
    while(1)begin
        @(posedge clock);
        if(load_store_accepted[2])begin
            store_en = 0;
            break;
        end
    end
    $display("Store finish!");
endtask

logic [63:0] mem_data, clock_count;
logic start;

initial begin
    $display("TB Start!");
    clock = 0;
    reset = 1;
    start = 0;
    load_addr = 0;
    load_en = 0;

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
    // relevant_load(8);
    // read_addr0(16, mem_data); // miss
    // read_addr1(24, mem_data); // miss
    // read_addr0(16, mem_data); // hit

    store_test(8, 24);
    read_addr0(8, mem_data); // should be hit

    $finish;
end

always_ff @(posedge clock) begin
    if(start)begin
        $display("@@@@@ clock: %d", clock_count);

        $display("MEM input: addr: %h, command: %d", proc2mem_addr, proc2mem_command);
        $display("MEM output: response: %d, tag: %d", mem2proc_response, mem2proc_tag);

        for (int i = 0; i < 2; i++) begin
            $display("@@ Load %d", i);
            $display("load_en: %d, load accepted: %d", load_en[i], load_store_accepted[i]);
            $display("MSHR[%d]: mem_tag: %h, miss_addr: %h", i,
                d.MSHR_table[i].mem_tag,
                d.MSHR_table[i].miss_addr);
            $display("Update_MSHR_en: %d", d.update_MSHR_enable[i]);
            $display("data_write_en: %d", d.data_write_enable[i]);
        end
        $display("");
        $display("D: operation: %d, operation_next: %d", d.operation, d.operation_next);
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