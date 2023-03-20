/* DESIGN = p issue_queue */
`include "sys_defs.svh"
`include "issue.svh"
`include "execute.svh"

module issue_queue #(
  parameter I_WIDTH = 3,
  parameter SIZE = 6,
  localparam I_WIDTH_CNT_LEN = `CAL_CNT_LEN(I_WIDTH),
  localparam SIZE_CNT_LEN = `CAL_CNT_LEN(SIZE)
) (
  input clock,
  input reset,
  input flush,

  /* connect to FUs */
  // number of empty FUs per type
  // NOTE that the value of execute_empty_slots could be 0, ..., n-1, n
  // which has I_WIDTH+1 possible values
  // this is different from index a bus with maximum I_WIDTH width
  input [`NUM_FU_TYPE-1:0][I_WIDTH_CNT_LEN-1:0] execute_empty_slots,
  // instr. given to FUs
  output execute_packet_t [`NUM_FU_TYPE-1:0][I_WIDTH-1:0] execute,

  /* connect to RS */
  // new instr. to put in queue. This cannot be exceed issue_empty_slots
  input issue_packet_t [I_WIDTH-1:0] issue,
  // number of new instr. slots in the queue
  output logic [I_WIDTH_CNT_LEN-1:0] issue_empty_slots,

  /* connect to physical register file */
  // wires for getting opa and opb values from physical register file
  input xlen_t [I_WIDTH-1:0][1:0] reg_file_read_value,
  output phy_reg_tag_t [I_WIDTH-1:0][1:0] reg_file_read_tag
);

  /* queue data */
  // queue is last(largest index) in first(smallest index) out
  issue_packet_t [SIZE-1:0] queue;
  issue_packet_t [SIZE-1:0] queue_next;

  /* temporary variables */
  // number of instr. to execute
  logic [I_WIDTH_CNT_LEN-1:0] total_execute_cnt;
  // number of instr. to execute per FU type
  logic [`NUM_FU_TYPE-1:0][I_WIDTH_CNT_LEN-1:0] execute_cnt;
  // temporary holding the current fu_type and fu_func
  fu_type_e fu_type;
  fu_func_t fu_func;
  // temporary holding the execute_packet to send out
  execute_packet_t execute_packet;
  // number of entries(instr.) in current queue will be kept in queue_next
  // namely, number of those instr.s not to execute
  // this is also the next empty slots during processing output
  // this MUST NOT be modified after we processed the output
  logic [SIZE_CNT_LEN-1:0] inst_kept_cnt;

  // we have number of empty slots after we have traversed all queue entries
  // This will lead to long wire routing
  // could be changed to only rely on current empty spots
  assign issue_empty_slots = (SIZE - inst_kept_cnt) > I_WIDTH ?
                              I_WIDTH : SIZE - inst_kept_cnt;

  xlen_t [I_WIDTH-1:0][1:0] branch_operand_next;

  always_comb begin
    // initial value
    queue_next = '0;

    // module I/O
    branch_operand_next = '0;
    reg_file_read_tag = '0;

    // temporary variables
    total_execute_cnt = '0;
    execute_cnt = '0;
    inst_kept_cnt = '0;

    execute = '0;
    execute_packet = '0;

    /* process output first */
    // iterate through all (possible) entries in the queue
    for (int unsigned index = 0; index < SIZE; index++) begin
      if (queue[index].valid == `TRUE) begin
        // get current queue entry fu_type
        fu_type = queue[index].decoded_inst.fu_type;
        fu_func = queue[index].decoded_inst.fu_func;

        // case when we CAN put the current instr. to execute
        if (execute_cnt[fu_type] < execute_empty_slots[fu_type] &&
            total_execute_cnt < I_WIDTH) begin
          // output execute packet
          execute_packet.pc  = queue[index].pc;
          execute_packet.decoded_inst = queue[index].decoded_inst;
          execute_packet.phy_dest_reg = queue[index].phy_dest_reg;
          // process opa and opb value
          execute_packet.opa = `XLEN'hdeadbeef;
          case (queue[index].decoded_inst.opa_select)
            OPA_IS_RS1: begin
              // we can only know the opa physical register index now
              reg_file_read_tag[total_execute_cnt][0].valid = `TRUE;
              reg_file_read_tag[total_execute_cnt][0].index =
                queue[index].phy_src_reg[0].index;
              execute_packet.opa = reg_file_read_value[total_execute_cnt][0];
            end
            OPA_IS_PC:
              execute_packet.opa = queue[index].pc;
          endcase
          case (queue[index].decoded_inst.opb_select)
            OPB_IS_RS2: begin
              // we can only know the opb physical register index now
              reg_file_read_tag[total_execute_cnt][1].valid = `TRUE;
              reg_file_read_tag[total_execute_cnt][1].index =
                queue[index].phy_src_reg[1].index;
              execute_packet.opb = reg_file_read_value[total_execute_cnt][1];
            end
            OPB_IS_I_IMM:
              execute_packet.opb = `RV32_Iimm_expand(queue[index].decoded_inst.imm);
            OPB_IS_S_IMM:
              execute_packet.opb = `RV32_Simm_expand(queue[index].decoded_inst.imm);
            OPB_IS_B_IMM:
              execute_packet.opb = `RV32_Bimm_expand(queue[index].decoded_inst.imm);
            OPB_IS_U_IMM:
              execute_packet.opb = `RV32_Uimm_expand(queue[index].decoded_inst.imm);
            OPB_IS_J_IMM:
              execute_packet.opb = `RV32_Jimm_expand(queue[index].decoded_inst.imm);
            default:
              execute_packet.opb = `XLEN'hdeadbeef;
          endcase
          execute_packet.rob_index = queue[index].rob_index;
          execute_packet.valid = `TRUE;
          // assign to actual output
          execute[fu_type][execute_cnt[fu_type]] = execute_packet;

          // special case for B-type instructions
          if (fu_type == FU_BRANCH) begin
            priority case (fu_func.branch.ty)
              FU_BRANCH_COND:
                // here OPA must be PC and OPB must be B_IMM
                for (int unsigned i = 0; i < 2; i++) begin
                  reg_file_read_tag[total_execute_cnt][i].valid = `TRUE;
                  reg_file_read_tag[total_execute_cnt][i].index =
                    queue[index].phy_src_reg[i].index;
                  // note the index we put the result in the special purpose
                  // output for conditional branch here
                  execute[fu_type][execute_cnt[fu_type]].exa.branch[i] =
                    reg_file_read_value[total_execute_cnt][i];
                end
              FU_BRANCH_UNCOND:
                // here OPA must be PC or RS1 and OPB must be B_IMM
                // output instruction PC for calculating PC+4
                // note pc has type PC_t and branch_operand has type xlen_t
                // this could be different on some other platform
                execute[fu_type][execute_cnt[fu_type]].exa.branch[0] =
                  queue[index].pc;
            endcase
          end else if (fu_type == FU_MEM) begin
            if (fu_func.mem.rw == FU_MEM_WRITE) begin
              reg_file_read_tag[total_execute_cnt][1].valid = `TRUE;
              reg_file_read_tag[total_execute_cnt][1].index =
                queue[index].phy_src_reg[1].index;
              execute[fu_type][execute_cnt[fu_type]].exa.mem.store_data =
                reg_file_read_value[total_execute_cnt][1];
            end
            execute[fu_type][execute_cnt[fu_type]].exa.mem.sq_index =
              queue[index].sq_index;
          end

          // increment count
          total_execute_cnt++;
          execute_cnt[fu_type]++;
        end
        // case when we CANNOT put the current instr. to execute
        else begin
          // put this instr. to queue_next
          queue_next[inst_kept_cnt] = queue[index];
          inst_kept_cnt++;
        end
      end
    end

    /* then process input */
    for (int unsigned i = 0; i < I_WIDTH; i++) begin
      // no need to check issue packet validity here
      if (i < issue_empty_slots) begin
        queue_next[inst_kept_cnt+i] = issue[i];
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset || flush) begin
      queue <= `SD '0;
    end else begin
      queue <= `SD queue_next;
    end
  end
endmodule
