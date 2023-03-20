/* DESIGN = icache */
`include "sys_defs.svh"

`define CACHE_LINES 32
`define CACHE_LINE_BITS $clog2(`CACHE_LINES)

typedef struct packed {
  logic [63:0]                     data;
  logic [12 - `CACHE_LINE_BITS:0]  tags;
  logic                            valids;
} icache_packet_t;

module icache(
    input clock,
    input reset,

    // from memory
    input [3:0]  Imem2proc_response,
    input [63:0] Imem2proc_data,
    input [3:0]  Imem2proc_tag,

    // from fetch stage
    input [`XLEN-1:0] proc2Icache_addr,

    // to memory
    output logic [1:0] proc2Imem_command,
    output logic [`XLEN-1:0] proc2Imem_addr,

    // to fetch stage
    output logic [63:0] Icache_data_out, // value is memory[proc2Icache_addr]
    output logic Icache_valid_out        // when this is high
);

    icache_packet_t [`CACHE_LINES-1:0] icache_data;

    logic [`CACHE_LINE_BITS - 1:0] current_index, last_index;
    logic [12 - `CACHE_LINE_BITS:0] current_tag, last_tag; // 12 since only 16 bits of address is used - thus 0 to 15 -> 3 bits block offset

    assign {current_tag, current_index} = proc2Icache_addr[15:3];

    logic [3:0] current_mem_tag;
    logic miss_outstanding;

    logic data_write_enable;
    assign data_write_enable = (current_mem_tag == Imem2proc_tag) && (current_mem_tag != 0);

    logic changed_addr;
    assign changed_addr = (current_index != last_index) || (current_tag != last_tag);

    logic update_mem_tag;
    assign update_mem_tag = changed_addr || miss_outstanding || data_write_enable;

    logic unanswered_miss;
    assign unanswered_miss = changed_addr ? !Icache_valid_out :
                                            miss_outstanding && (Imem2proc_response == 0);

    assign proc2Imem_addr    = {proc2Icache_addr[31:3],3'b0};
    assign proc2Imem_command = (miss_outstanding && !changed_addr) ?  BUS_LOAD : BUS_NONE;

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
                current_mem_tag     <= `SD Imem2proc_response;
            end

            if(data_write_enable) begin // If data came from memory, meaning tag matches
                icache_data[current_index].data     <= `SD Imem2proc_data;
                icache_data[current_index].tags     <= `SD current_tag;
                icache_data[current_index].valids   <= `SD 1;
            end
        end
    end
endmodule
