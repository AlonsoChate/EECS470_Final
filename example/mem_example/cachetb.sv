`timescale 1ns/100ps

module cachetb;

`define CACHE_MODE

logic clock, reset;
// mem signals
logic [`XLEN-1:0] proc2mem_addr;
logic [3:0] mem2proc_tag, mem2proc_response;
logic [1:0] proc2mem_command;
logic [63:0] proc2mem_data, mem2proc_data;
// cache signals
logic wr1_en, rd1_valid;
logic [4:0] wr1_idx, rd1_idx;
logic [7:0] wr1_tag, rd1_tag;
logic [63:0] wr1_data, rd1_data;
// icache signals
logic [63:0] proc2Icache_addr;
logic [63:0] cachemem_data;
logic  cachemem_valid;
logic [63:0] Icache_data_out; // value is memory[proc2Icache_addr]
logic  Icache_valid_out;      // when this is high
logic  [4:0] current_index;
logic  [7:0] current_tag;
logic  [4:0] last_index;
logic  [7:0] last_tag;
logic  data_write_enable;

mem memory (
    .clk(clock),
    .proc2mem_addr,
    // .proc2mem_data(), // why is this disconnected for icache?
    .proc2mem_command,
    
    .mem2proc_response,
    .mem2proc_data,
    .mem2proc_tag
); // the system memory

icache ictrl (
    .clock,
    .reset,
    .Imem2proc_response(mem2proc_response),
    .Imem2proc_data(mem2proc_data),
    .Imem2proc_tag(mem2proc_tag),
    .proc2Icache_addr,
    .cachemem_data,
    .cachemem_valid,

    .proc2Imem_command(proc2mem_command),
    .proc2Imem_addr(proc2mem_addr),
    .Icache_valid_out,
    .Icache_data_out,
    .current_index,
    .current_tag,
    .last_index,
    .last_tag,
    .data_write_enable
); // the cache controller

cache cachemem (
    .clock,
    .reset,
    .wr1_en(data_write_enable),
    .wr1_idx(current_index),
    .rd1_idx(current_index),
    .wr1_tag(current_tag),
    .rd1_tag(current_tag),
    .wr1_data(mem2proc_data),
    .rd1_data(cachemem_data),
    .rd1_valid(cachemem_valid)
); // the cache storage

/*
    
    The main interface between the CPU and the icache module is proc2Icache_addr and Icache_valid_out

    The icache will return the hit status the same cycle as a read, if the read is not a hit, then the CPU
    needs to not change the address until it is a hit

*/

// this only works in simulation
task automatic read_addr(input logic[63:0] addr, output logic[63:0] data);
    int cycles_waited = 0;
    proc2Icache_addr = addr;
    #1;
    if (Icache_valid_out) begin
        data = Icache_data_out;
        $display("Read address [%0h]=%0h took %0d cycles", addr, data, cycles_waited);
        return;
    end else begin
        while(1) begin
            @(negedge clock);
            ++cycles_waited;
            if(Icache_valid_out) begin
                data = Icache_data_out;
                $display("Read address [%0h]=%0h took %0d cycles", addr, data, cycles_waited);
                break;
            end
        end
    end
endtask


logic [63:0] mem_data, clock_count;

initial begin
    $display("TB Start!");
    clock = 0;
    reset = 1;
    proc2Icache_addr = 0;
    @(negedge clock);
    @(negedge clock);
    @(negedge clock);
    reset = 0;
    @(negedge clock);
    for (int i = 0; i < 1024; ++i) begin
        memory.unified_memory[i] = i;
    end
    repeat (100) @(negedge clock);
    
    for (int i = 0; i < 16; ++i) begin
        read_addr(i * 8, mem_data);
    end

    for (int i = 0; i < 16; ++i) begin
        read_addr(i * 8, mem_data);
    end

    $finish;
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