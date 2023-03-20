/* DESIGN = p decoder */

`include "sys_defs.svh"

// Decode an instruction: given instruction bits IR produce the
// appropriate datapath control signals.
//
// This is a *combinational* module (basically a PLA).
//
module decoder (
    input inst_t inst,  // instruction in union representation
    input        valid, // ignore inst when low, outputs will reflect a noop

    // decoded instruction information
    output decoded_inst_t       decoded_inst,
    output logic                halt,          // is this a halt?
    output logic                illegal,       // is this instruction illegal?
    // architectural source registers
    output arch_reg_idx_t [1:0] arch_src_reg,
    // architectural destination register
    output arch_reg_idx_t       arch_dest_reg
);

  // temporary logic holding values for output
  // must be identical to decoded_inst_t in sys_defs.svh
  fu_type_e                                fu_type;
  fu_func_t                                fu_func;
  opa_select_e                             opa_select;
  opb_select_e                             opb_select;
  logic        [`RV32_IMM_EXTRACTED_LEN:0] imm;
  logic                                    csr_op;
  // pack temporary variables into output
  assign decoded_inst.fu_type    = fu_type;
  assign decoded_inst.fu_func    = fu_func;
  assign decoded_inst.opa_select = opa_select;
  assign decoded_inst.opb_select = opb_select;
  assign decoded_inst.imm        = imm;
  assign decoded_inst.csr_op     = csr_op;

  always_comb begin
    // default control values:
    // - valid instructions must override these defaults as necessary.
    //	 opa_select, opb_select, fu_type, and fu_func should be set explicitly.
    // - Invalid defaults are equivalent to a "ADD x0, x0, x0" instruction
    fu_type               = FU_INT_FAST;
    fu_func.int_fast.func = FU_ADD;

    opa_select            = OPA_IS_RS1;
    opb_select            = OPB_IS_RS2;
    imm                   = '0;

    csr_op                = `FALSE;

    halt                  = `FALSE;
    illegal               = `FALSE;

    // default source and destination registers
    arch_src_reg[0]       = '0;
    arch_src_reg[1]       = '0;
    arch_dest_reg         = '0;

    if (valid) begin
      casez (inst)
        `RV32_LUI: begin
          opa_select    = OPA_IS_RS1;
          opb_select    = OPB_IS_U_IMM;
          // here although opa is RS1, it is just zero register (0)
          arch_dest_reg = inst.u.rd;
        end
        `RV32_AUIPC: begin
          opa_select    = OPA_IS_PC;
          opb_select    = OPB_IS_U_IMM;
          arch_dest_reg = inst.u.rd;
        end
        `RV32_JAL: begin
          fu_type           = FU_BRANCH;
          fu_func.branch.ty = FU_BRANCH_UNCOND;
          opa_select        = OPA_IS_PC;
          opb_select        = OPB_IS_J_IMM;
          arch_dest_reg     = inst.j.rd;
        end
        `RV32_JALR: begin
          fu_type           = FU_BRANCH;
          fu_func.branch.ty = FU_BRANCH_UNCOND;
          opb_select        = OPB_IS_I_IMM;
          arch_src_reg[0]   = inst.i.rs1;
          arch_dest_reg     = inst.i.rd;
        end
        `RV32_BEQ, `RV32_BNE, `RV32_BLT, `RV32_BGE, `RV32_BLTU, `RV32_BGEU:
        begin
          fu_type             = FU_BRANCH;
          fu_func.branch.func = fu_branch_cond_func_e'(inst.b.funct3);
          fu_func.branch.ty   = FU_BRANCH_COND;
          opa_select          = OPA_IS_PC;
          opb_select          = OPB_IS_B_IMM;
          // special case for B-type instructions
          arch_src_reg[0]     = inst.b.rs1;
          arch_src_reg[1]     = inst.b.rs2;
        end
        `RV32_LB, `RV32_LH, `RV32_LW, `RV32_LBU, `RV32_LHU: begin
          fu_type               = FU_MEM;
          fu_func.mem.func.read = fu_mem_read_func_e'(inst.i.funct3);
          fu_func.mem.rw        = FU_MEM_READ;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_SB, `RV32_SH, `RV32_SW: begin
          fu_type                = FU_MEM;
          fu_func.mem.func.write = fu_mem_write_func_e'(inst.s.funct3);
          fu_func.mem.rw         = FU_MEM_WRITE;
          opb_select             = OPB_IS_S_IMM;
          arch_src_reg[0]        = inst.s.rs1;
          // special case for S-type instructions
          arch_src_reg[1]        = inst.s.rs2;
        end
        `RV32_ADDI: begin
          opb_select      = OPB_IS_I_IMM;
          arch_src_reg[0] = inst.i.rs1;
          arch_dest_reg   = inst.i.rd;
        end
        `RV32_SLTI: begin
          fu_func.int_fast.func = FU_SLT;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_SLTIU: begin
          fu_func.int_fast.func = FU_SLTU;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_ANDI: begin
          fu_func.int_fast.func = FU_AND;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_ORI: begin
          fu_func.int_fast.func = FU_OR;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_XORI: begin
          fu_func.int_fast.func = FU_XOR;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_SLLI: begin
          fu_func.int_fast.func = FU_SLL;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_SRLI: begin
          fu_func.int_fast.func = FU_SRL;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_SRAI: begin
          fu_func.int_fast.func = FU_SRA;
          opb_select            = OPB_IS_I_IMM;
          arch_src_reg[0]       = inst.i.rs1;
          arch_dest_reg         = inst.i.rd;
        end
        `RV32_ADD: begin
          arch_src_reg[0] = inst.r.rs1;
          arch_src_reg[1] = inst.r.rs2;
          arch_dest_reg   = inst.r.rd;
        end
        `RV32_SUB: begin
          fu_func.int_fast.func = FU_SUB;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_SLT: begin
          fu_func.int_fast.func = FU_SLT;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_SLTU: begin
          fu_func.int_fast.func = FU_SLTU;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_AND: begin
          fu_func.int_fast.func = FU_AND;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_OR: begin
          fu_func.int_fast.func = FU_OR;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_XOR: begin
          fu_func.int_fast.func = FU_XOR;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_SLL: begin
          fu_func.int_fast.func = FU_SLL;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_SRL: begin
          fu_func.int_fast.func = FU_SRL;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_SRA: begin
          fu_func.int_fast.func = FU_SRA;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_MUL: begin
          fu_type               = FU_INT_MULT;
          fu_func.int_mult.func = FU_MUL;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_MULH: begin
          fu_type               = FU_INT_MULT;
          fu_func.int_mult.func = FU_MULH;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_MULHSU: begin
          fu_type               = FU_INT_MULT;
          fu_func.int_mult.func = FU_MULHSU;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_MULHU: begin
          fu_type               = FU_INT_MULT;
          fu_func.int_mult.func = FU_MULHU;
          arch_src_reg[0]       = inst.r.rs1;
          arch_src_reg[1]       = inst.r.rs2;
          arch_dest_reg         = inst.r.rd;
        end
        `RV32_CSRRW, `RV32_CSRRS, `RV32_CSRRC: begin
          csr_op = `TRUE;
        end
        `WFI: begin
          halt = `TRUE;
        end
        default: illegal = `TRUE;
      endcase  // casez (inst)

      // process imm
      case (opb_select)
        OPB_IS_I_IMM: imm = `RV32_Iimm_extract(inst);
        OPB_IS_S_IMM: imm = `RV32_Simm_extract(inst);
        OPB_IS_B_IMM: imm = `RV32_Bimm_extract(inst);
        OPB_IS_U_IMM: imm = `RV32_Uimm_extract(inst);
        OPB_IS_J_IMM: imm = `RV32_Jimm_extract(inst);
      endcase
    end  // if(valid)
  end  // always_comb
endmodule  // decoder
