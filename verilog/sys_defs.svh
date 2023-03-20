
/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  sys_defs.vh                                         //
//                                                                     //
//  Description :  This file has the macro-defines for macros used in  //
//                 the pipeline design.                                //
//                                                                     //
/////////////////////////////////////////////////////////////////////////


`ifndef __SYS_DEFS_VH__
`define __SYS_DEFS_VH__

`include "ISA.svh"

`timescale 1ns/100ps

/* Synthesis testing definition, used in DUT module instantiation */

`ifdef  SYNTH_TEST
`define DUT(mod) mod``_svsim
`else
`define DUT(mod) mod
`endif

//////////////////////////////////////////////
//
// Memory/testbench attribute definitions
//
//////////////////////////////////////////////
`define CACHE_MODE //removes the byte-level interface from the memory mode, DO NOT MODIFY!
`define NUM_MEM_TAGS           15

`define MEM_SIZE_IN_BYTES      (64*1024)
`define MEM_64BIT_LINES        (`MEM_SIZE_IN_BYTES/8)

//you can change the clock period to whatever, 10 is just fine
`define VERILOG_CLOCK_PERIOD   15.0
`define SYNTH_CLOCK_PERIOD     15.0 // Clock period for synth and memory latency

`define MEM_LATENCY_IN_CYCLES (100.0/`SYNTH_CLOCK_PERIOD+0.49999)
// the 0.49999 is to force ceiling(100/period).  The default behavior for
// float to integer conversion is rounding to nearest

typedef union packed {
    logic [7:0][7:0] byte_level;
    logic [3:0][15:0] half_level;
    logic [1:0][31:0] word_level;
} EXAMPLE_CACHE_BLOCK;

//////////////////////////////////////////////
// Exception codes
// This mostly follows the RISC-V Privileged spec
// except a few add-ons for our infrastructure
// The majority of them won't be used, but it's
// good to know what they are
//////////////////////////////////////////////

typedef enum logic [3:0] {
	INST_ADDR_MISALIGN  = 4'h0,
	INST_ACCESS_FAULT   = 4'h1,
	ILLEGAL_INST        = 4'h2,
	BREAKPOINT          = 4'h3,
	LOAD_ADDR_MISALIGN  = 4'h4,
	LOAD_ACCESS_FAULT   = 4'h5,
	STORE_ADDR_MISALIGN = 4'h6,
	STORE_ACCESS_FAULT  = 4'h7,
	ECALL_U_MODE        = 4'h8,
	ECALL_S_MODE        = 4'h9,
	NO_ERROR            = 4'ha, //a reserved code that we modified for our purpose
	ECALL_M_MODE        = 4'hb,
	INST_PAGE_FAULT     = 4'hc,
	LOAD_PAGE_FAULT     = 4'hd,
	HALTED_ON_WFI       = 4'he, //another reserved code that we used
	STORE_PAGE_FAULT    = 4'hf
} exception_code_e;


//////////////////////////////////////////////
//
// Datapath control signals
//
//////////////////////////////////////////////

//
// ALU opA input mux selects
//
typedef enum logic {
	OPA_IS_RS1  = 1'h0,
	OPA_IS_PC   = 1'h1
} opa_select_e;

//
// ALU opB input mux selects
//
typedef enum logic [3:0] {
	OPB_IS_RS2    = 4'h0,
	OPB_IS_I_IMM  = 4'h1,
	OPB_IS_S_IMM  = 4'h2,
	OPB_IS_B_IMM  = 4'h3,
	OPB_IS_U_IMM  = 4'h4,
	OPB_IS_J_IMM  = 4'h5
} opb_select_e;

//////////////////////////////////////////////
//
// Assorted things it is not wise to change
//
//////////////////////////////////////////////

//
// actually, you might have to change this if you change VERILOG_CLOCK_PERIOD
// JK you don't ^^^
//
`define SD #1

// the RISCV register file zero register, any read of this register always
// returns a zero value, and any write to this register is thrown away
//
`define ZERO_REG 5'd0

//
// Memory bus commands control signals
//
typedef enum logic [1:0] {
	BUS_NONE     = 2'h0,
	BUS_LOAD     = 2'h1,
	BUS_STORE    = 2'h2
} BUS_COMMAND;

`ifndef CACHE_MODE
typedef enum logic [1:0] {
  BYTE = 2'h0,
  HALF = 2'h1,
  WORD = 2'h2,
  DOUBLE = 2'h3,
} mem_size_e;
`endif
//
// useful boolean single-bit definitions
//
`define FALSE  1'h0
`define TRUE  1'h1

// RISCV ISA SPEC
`define XLEN 32
typedef logic [31:0] word;
typedef union packed {
	logic [31:0] inst;
	struct packed {
		logic [6:0] funct7;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] rd;
		logic [6:0] opcode;
	} r; //register to register instructions
	struct packed {
		logic [11:0] imm;
		logic [4:0]  rs1; //base
		logic [2:0]  funct3;
		logic [4:0]  rd;  //dest
		logic [6:0]  opcode;
	} i; //immediate or load instructions
	struct packed {
		logic [6:0] off; //offset[11:5] for calculating address
		logic [4:0] rs2; //source
		logic [4:0] rs1; //base
		logic [2:0] funct3;
		logic [4:0] set; //offset[4:0] for calculating address
		logic [6:0] opcode;
	} s; //store instructions
	struct packed {
		logic       of; //offset[12]
		logic [5:0] s;   //offset[10:5]
		logic [4:0] rs2;//source 2
		logic [4:0] rs1;//source 1
		logic [2:0] funct3;
		logic [3:0] et; //offset[4:1]
		logic       f;  //offset[11]
		logic [6:0] opcode;
	} b; //branch instructions
	struct packed {
		logic [19:0] imm;
		logic [4:0]  rd;
		logic [6:0]  opcode;
	} u; //upper immediate instructions
	struct packed {
		logic       of; //offset[20]
		logic [9:0] et; //offset[10:1]
		logic       s;  //offset[11]
		logic [7:0] f;	//offset[19:12]
		logic [4:0] rd; //dest
		logic [6:0] opcode;
	} j;  //jump instructions
`ifdef ATOMIC_EXT
	struct packed {
		logic [4:0] funct5;
		logic       aq;
		logic       rl;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] rd;
		logic [6:0] opcode;
	} a; //atomic instructions
`endif
`ifdef SYSTEM_EXT
	struct packed {
		logic [11:0] csr;
		logic [4:0]  rs1;
		logic [2:0]  funct3;
		logic [4:0]  rd;
		logic [6:0]  opcode;
	} sys; //system call instructions
`endif

} inst_t; //instruction typedef, this should cover all types of instructions

//
// Basic NOP instruction. Allows pipeline registers to clearly be reset with
// an instruction that does nothing instead of Zero which is really an ADDI x0, x0, 0
//
`define NOP 32'h00000013

//
// New defines and macros for P4 starts here
//
`define CAL_IDX_LEN(NUM) (int'($ceil($clog2(NUM))))
`define CAL_CNT_LEN(NUM) (int'($ceil($clog2(NUM+1))))

`define WAY 3
`define WAY_CNT_LEN 2 // how many bits required to represent 0,...,`WAY

`define PHY_REG_SIZE 64
`define PHY_REG_IDX_LEN 6
`define ARCH_REG_SIZE 32
`define ARCH_REG_IDX_LEN 5
`define ROB_SIZE 32 // (`PHY_REG_SIZE - `ARCH_REG_SIZE)
`define ROB_IDX_LEN 5
`define FREELIST_SIZE 32 // (`PHY_REG_SIZE - `ARCH_REG_SIZE)
`define FREELIST_IDX_LEN 5
`define BR_BUF_SIZE 32
`define BR_BUF_IDX_LEN 5
`define BR_BUF_TAG_LEN (`BR_BUF_SIZE - `BR_BUF_IDX_LEN)
`define DCACHE_SIZE 32
`define DCACHE_IDX_LEN 5

`define LQ_SIZE 4
`define SQ_SIZE 4
`define LQ_IDX_LEN 2
`define SQ_IDX_LEN 2

typedef logic [`LQ_IDX_LEN-1:0] lq_idx_t;
typedef logic [`SQ_IDX_LEN-1:0] sq_idx_t;
typedef logic [`XLEN-1:0] xlen_t;
typedef logic [`XLEN-1:0] PC_t;

typedef logic [`ARCH_REG_IDX_LEN-1:0] arch_reg_idx_t;
typedef logic [`PHY_REG_IDX_LEN-1:0] phy_reg_idx_t;
typedef logic [`ROB_IDX_LEN-1:0] rob_idx_t;
typedef logic [`BR_BUF_IDX_LEN-1:0] br_buf_idx_t;
typedef logic [`BR_BUF_TAG_LEN-1:0] br_buf_tag_t;

typedef struct packed {
  phy_reg_idx_t index;
  logic valid;
} phy_reg_tag_t;

// how many different types of FUs
`define NUM_FU_TYPE 4

typedef enum logic [1:0] {
  FU_MEM = 2'h0,
  FU_INT_FAST = 2'h1,
  FU_INT_MULT = 2'h2,
  FU_BRANCH = 2'h3
} fu_type_e;

typedef enum logic [2:0] {
  FU_LB = 3'b000,
  FU_LH = 3'b001,
  FU_LW = 3'b010,
  FU_LBU = 3'b100,
  FU_LHU = 3'b101
} fu_mem_read_func_e;

typedef enum logic [2:0] {
  FU_SB = 3'b000,
  FU_SH = 3'b001,
  FU_SW = 3'b010
} fu_mem_write_func_e;

typedef union packed {
  fu_mem_read_func_e  read;
  fu_mem_write_func_e write;
} fu_mem_func_t;

typedef enum logic [3:0] {
	FU_ADD     = 4'h0,
	FU_SUB     = 4'h1,
	FU_SLT     = 4'h2,
	FU_SLTU    = 4'h3,
	FU_AND     = 4'h4,
	FU_OR      = 4'h5,
	FU_XOR     = 4'h6,
	FU_SLL     = 4'h7,
	FU_SRL     = 4'h8,
	FU_SRA     = 4'h9
} fu_int_fast_func_e;

typedef enum logic [1:0] {
	FU_MUL     = 2'h0,
	FU_MULH    = 2'h1,
	FU_MULHSU  = 2'h2,
	FU_MULHU   = 2'h3
//	ALU_DIV     = 5'h0e,
//	ALU_DIVU    = 5'h0f,
//	ALU_REM     = 5'h10,
//	ALU_REMU    = 5'h11
} fu_int_mult_func_e;

// conditional branch func enum
// this is ignored when branch is unconditional
// note that this should correspond to
// the funct3 section [14:12] of each instruction
typedef enum logic [2:0] {
  FU_BEQ = 3'b000,
  FU_BNE = 3'b001,
  FU_BLT = 3'b100,
  FU_BGE = 3'b101,
  FU_BLTU = 3'b110,
  FU_BGEU = 3'b111
} fu_branch_cond_func_e;

typedef enum logic {
  FU_MEM_READ,
  FU_MEM_WRITE
} fu_mem_type_e;

typedef enum logic {
  FU_BRANCH_COND,
  FU_BRANCH_UNCOND
} fu_branch_type_e;

typedef union packed {
  struct packed {
    fu_mem_func_t 		func;
    fu_mem_type_e 		rw;
  } mem;
  struct packed {
    fu_int_fast_func_e func;
  } int_fast;
  struct packed {
    fu_int_mult_func_e func;
    logic [1:0]        __pad__;
  } int_mult;
  struct packed {
    fu_branch_cond_func_e 	func;
    fu_branch_type_e 	      ty;
  } branch;
} fu_func_t;

typedef struct packed {
  // operation information
  fu_type_e fu_type;
  fu_func_t fu_func;

  // operand information
  opa_select_e opa_select;
  opb_select_e opb_select;
  logic [`RV32_IMM_EXTRACTED_LEN:0] imm;

  // other information inherited from P3
	logic     csr_op;        // is this a CSR operation? (we only used this as a cheap way to get return code)
	//logic     valid;         // is inst a valid instruction to be counted for CPI calculations?
} decoded_inst_t;

typedef logic [63:0] mem_t;

`endif // __SYS_DEFS_VH__
