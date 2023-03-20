/* DESIGN = p mem_ctrl */

`include "sys_defs.svh"

/*
  basically a mux to connect one port mem to either Icache or Dcache, where 
  Dcache has higher priority
*/

module mem_ctrl(
  input               clock,reset,

  /* memory I/O */
  // from mem
  input [3:0]         mem2ctrl_response,// 0 = can't accept, other=tag of transaction
  input [63:0]        mem2ctrl_data,    // data resulting from a load
  input [3:0]         mem2ctrl_tag,     // 0 = no value, other=tag of transaction
  // to mem
  output PC_t         ctrl2mem_addr,    // address for current command
  output [63:0]       ctrl2mem_data,    // data for store
  output [1:0]        ctrl2mem_command, // `BUS_NONE `BUS_LOAD or `BUS_STORE

  /* Dcache I/O */
  // from Dcache
  input [1:0]         Dcache2Dmem_command,
  input PC_t          Dcache2Dmem_addr,
  input [63:0]        Dcache2Dmem_data,
  // to Dcache
  output logic [3:0]  Dmem2Dcache_response,
  output logic [63:0] Dmem2Dcache_data,
  output logic [3:0]  Dmem2Dcache_tag,

  /* Icache I/O */
  // from Icache bank
  input [1:0]         Icache2Imem_command,
  input PC_t          Icache2Imem_addr,
  // to Icache bank
  output logic [3:0]  Imem2Icache_response,
  output logic [63:0] Imem2Icache_data,
  output logic [3:0]  Imem2Icache_tag
);  
  // Dcache has higher priority than Icache
  logic Dcache_on_bus;
  assign Dcache_on_bus = (Dcache2Dmem_command != BUS_NONE);

  /* output to mem */
  assign ctrl2mem_addr = Dcache_on_bus ? Dcache2Dmem_addr : Icache2Imem_addr;
  assign ctrl2mem_data = Dcache2Dmem_data;
  assign ctrl2mem_command = Dcache_on_bus ? Dcache2Dmem_command : Icache2Imem_command;

  /* output to Dcache */ 
  /* Note: tag from mem should be broadcast to Icache and Dcache */
  /* Note: response == 0 can stall the cache */
  assign Dmem2Dcache_response = Dcache_on_bus ? mem2ctrl_response : 0;
  assign Dmem2Dcache_data = mem2ctrl_data;
  assign Dmem2Dcache_tag = mem2ctrl_tag;

  /* output to Icache */
  assign Imem2Icache_response = Dcache_on_bus ? 0 : mem2ctrl_response;
  assign Imem2Icache_data = mem2ctrl_data;
  assign Imem2Icache_tag = mem2ctrl_tag;
endmodule
