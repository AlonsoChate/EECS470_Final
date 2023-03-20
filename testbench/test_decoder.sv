/* SOURCE = decoder.sv */

`timescale 1ns/100ps

`include "sys_defs.svh"

module testbench;
  logic clock;
  always #5 clock = ~clock;

  int unsigned instr_index;
  string fu_func_str;

  /* wires for decoder I/O */
  inst_t inst;  // instruction in union representation
  logic  valid; // ignore inst when low, outputs will reflect a noop

  decoded_inst_t decoded_inst;  // see sys_defs.svh for definition

  // instantiate module
  decoder dec (
    .inst(inst),
    .valid(valid),
    .decoded_inst(decoded_inst)
  );

  // memory for storing actual compiled instructions
  logic [63:0] unified_memory  [`MEM_64BIT_LINES - 1:0];
  assign inst = (instr_index % 2 == 0) ? unified_memory[(instr_index>>1)][31:0] :
                                         unified_memory[(instr_index>>1)][63:32];

  always @(posedge clock) begin
    $display("mem:%h valid:%b inst:%h", instr_index*4, valid, inst);

    fu_func_str = "";
    case (decoded_inst.fu_type)
      FU_MEM: begin
        case (decoded_inst.fu_func.mem.rw)
          FU_MEM_READ:
            fu_func_str = {decoded_inst.fu_func.mem.rw.name, " ", decoded_inst.fu_func.mem.func.read.name};
          FU_MEM_WRITE:
            fu_func_str = {decoded_inst.fu_func.mem.rw.name, " ", decoded_inst.fu_func.mem.func.write.name};
        endcase
      end
      FU_INT_FAST:
        fu_func_str = decoded_inst.fu_func.int_fast.func.name;
      FU_INT_MULT:
        fu_func_str = decoded_inst.fu_func.int_mult.func.name;
      FU_BRANCH: begin
        case (decoded_inst.fu_func.branch.ty)
          FU_BRANCH_COND:
            fu_func_str = {decoded_inst.fu_func.branch.ty.name, " ", decoded_inst.fu_func.branch.func.name};
          FU_BRANCH_UNCOND:
            fu_func_str = {decoded_inst.fu_func.branch.ty.name};
        endcase
      end
    endcase
    $display("\tfu_type:%s fu_func:%s", decoded_inst.fu_type.name, fu_func_str);

    $display("\topa_select:%s opb_select:%s imm:%h : %d", decoded_inst.opa_select.name, decoded_inst.opb_select.name, decoded_inst.imm, decoded_inst.imm);

    $display("\thalt:%b illegal:%b csr_op:%b", decoded_inst.halt, decoded_inst.illegal, decoded_inst.csr_op);

    $display("");
  end

  initial begin
    $dumpfile("decoder.vcd");
    $dumpvars(0, testbench);

    $readmemh("program.mem", unified_memory);

    clock = 0;
    valid = `FALSE;

    @(negedge clock)
    valid = `TRUE;
    // read through all instructions and give output from decoder
    for (instr_index = 0; instr_index < `MEM_64BIT_LINES*2; instr_index++) begin
      @(posedge clock)
      #3
      // if we have reached the end of memory
      if (inst == 32'h0 || inst == `WFI) begin
        break;
      end

      @(negedge clock) begin
      end
    end

    $finish;
  end

endmodule
