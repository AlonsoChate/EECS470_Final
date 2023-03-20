/* DESIGN = p rob */
`include "sys_defs.svh"
`include "dispatch.svh"
`include "complete.svh"
`include "issue.svh"
`include "fetch.svh"
`include "rewind.svh"
`include "resolve.svh"
`include "retire.svh"
`include "update.svh"

/*
    if
        head -> inst1 -> inst2 -> exception <- tail
    then
        retire inst1, inst2 and start rewind at the same cycle

    it's possible that
        cycle 1: retire 2 insts -> exception at head and start rewind -> exception bit flipped and finish rewind
        cycle 2: start new dispatch
*/

module rob(
  input                                       clock, reset,

  if_dispatch.rob it_dispatch,

  /** Rewind I/O **/
  if_rewind.rob rewind,

  output  PC_t                                rewind_target_PC,       // real target PC, send to fetch stage
  output  logic                               fetch_flush,              // signal to start new fetch, basically to notify fetch stage
  output  logic                               store_flush,

  /** Complete I/O **/
  input  	complete_packet_t   [`WAY-1:0]      complete,

  if_resolve.rob resolve,

  if_update.rob update,

  /** Retire I/O **/
  if_retire.rob retire,
  output  exception_code_e                    exception_code       // output of processor
);

  typedef struct packed {
    fu_type_e fu_type;
    fu_func_t fu_func;
    arch_reg_idx_t arch_dest_reg;
    phy_reg_idx_t T;
    phy_reg_idx_t Told;
    logic valid;
    logic complete;
    logic exception;
    PC_t pc;
    logic taken;
    logic correct;
    PC_t target_pc;
    exception_code_e code;
  } rob_entry;

  /* some temp variables for calculation*/
  integer     occupied_spot_number;
  integer     dist1, dist2;

  /* stage registers */
  rob_entry   [`ROB_SIZE-1:0] rob_mem;
  rob_idx_t   head;
  rob_idx_t   tail;
  logic       is_empty;                   // whether rob is empty

  // status indicators for resembling FSM
  logic has_rewind;                       // whether there is an exception flipped in rob
  logic in_rewind;                        // whether rob is currently rewinding instructions
  logic in_retire;

  // store the rob index of the oldest instruction with exception
  rob_idx_t   oldest_exc_rob_index;

  /* next stage registers */
  rob_entry   [`ROB_SIZE-1:0] rob_mem_next;
  rob_idx_t                   head_next;
  rob_idx_t                   tail_next;
  logic                       is_empty_next;

  logic has_rewind_next;
  logic in_rewind_next;
  logic in_retire_next;
  logic fetch_flush_next;
  logic store_flush_next;

  PC_t        rewind_target_PC_next;
  rob_idx_t   oldest_exc_rob_index_next;

  exception_code_e exception_code_next;

  always_ff @(posedge clock) begin
    if (reset) begin
      rob_mem     <= `SD 0;
      head        <= `SD 0;
      tail        <= `SD `ROB_SIZE - 1;   // make tail + 1 points to the position for dispatch
      is_empty    <= `SD `TRUE;

      has_rewind  <= `SD `FALSE;
      in_rewind   <= `SD `FALSE;
      in_retire   <= `SD `FALSE;
      fetch_flush <= `SD `FALSE;
      store_flush <= `SD `FALSE;

      rewind_target_PC      <= `SD 0;
      oldest_exc_rob_index  <= `SD 0;
      exception_code <= `SD NO_ERROR;
    end else begin
      rob_mem     <= `SD rob_mem_next;
      head        <= `SD head_next;
      tail        <= `SD tail_next;
      is_empty    <= `SD is_empty_next;

      has_rewind  <= `SD has_rewind_next;
      in_rewind   <= `SD in_rewind_next;
      in_retire   <= `SD in_retire_next;
      fetch_flush <= `SD fetch_flush_next;
      store_flush <= `SD store_flush_next;

      rewind_target_PC      <= `SD rewind_target_PC_next;
      oldest_exc_rob_index  <= `SD oldest_exc_rob_index_next;
      exception_code <= `SD exception_code_next;
    end
  end

  // combination logic to judge whether rewind_target_PC,
  // oldest_exc_rob_index, and exception_code stored should be update
  // in other words, to judge whether there is an older instruction with
  // exception (wfi, illegal, branch taken)
  // we assume an instruction with exception must cause rewind, so we
  // name 'update_rewind_point' here

  always_comb begin
    head_next = head;
    tail_next = tail;
    rob_mem_next = rob_mem;
    is_empty_next = is_empty;

    has_rewind_next = has_rewind;
    in_rewind_next = in_rewind;
    in_retire_next = in_retire;

    rewind_target_PC_next = rewind_target_PC;
    oldest_exc_rob_index_next = oldest_exc_rob_index;
    fetch_flush_next = fetch_flush;
    store_flush_next = store_flush;

    it_dispatch.rob_index = '0;
    it_dispatch.num_can_dispatch_inst = '0;

    rewind.reg_T = '0;
    rewind.reg_Told = '0;
    rewind.rob_index = '0;
    rewind.num = '0;

    retire.instr_num = '0;
    retire.Told = '0;
    retire.arch_dest_reg = '0;
    retire.T = '0;
    retire.is_store = `FALSE;
    exception_code_next = NO_ERROR; // No error at the beginning

    update.valid = '0;
    update.source_pc = '0;
    update.target_pc = '0;
    update.taken = '0;
    update.correct = '0;

    // fetch_flush only assert to TRUE for one cycle */
    if (fetch_flush)
      fetch_flush_next = `FALSE;

    if (store_flush)
      store_flush_next = `FALSE;

	  /** retire stage first **/
    if (!in_rewind) begin
      for (int unsigned i = 0; i < `WAY; i++) begin
        // rob empty or head not completed
        if (is_empty_next || !rob_mem[head_next].complete)
            break;

        if (rob_mem[head_next].fu_type == FU_MEM
            && rob_mem[head_next].fu_func.mem.rw == FU_MEM_WRITE) begin
          if (retire.is_store) begin
            break;
          end
          retire.is_store = `TRUE;
          if (!retire.store_accepted) begin
            break;
          end
        end

        if (rob_mem[head_next].fu_type == FU_BRANCH) begin
          update.valid[i] = `TRUE;
          update.source_pc[i] = rob_mem[head_next].pc;
          update.target_pc[i] = rob_mem[head_next].target_pc;
          update.taken[i] = rob_mem[head_next].taken;
          update.correct[i] = rob_mem[head_next].correct;
        end

        // start rewind and jump retire process
        if (rob_mem[head_next].exception == `TRUE) begin
          // output exception code if any
          // since branch is NO_ERROR while wfi and illegal will
          // just stop the system, we can combine then here
          exception_code_next = rob_mem[head_next].code;
          in_rewind_next = `TRUE;
          // special case for WFI instr.
          if (exception_code_next == HALTED_ON_WFI)
            retire.instr_num++;
          break;
        end

        // normal retire
        retire.instr_num++;
        retire.Told[i] = rob_mem[head_next].Told;
        retire.arch_dest_reg[i] = rob_mem[head_next].arch_dest_reg;
        retire.T[i] = rob_mem[head_next].T;
        rob_mem_next[head_next] = 0;

        // update head
        if (head_next == tail_next)
          is_empty_next = `TRUE;
        head_next = head_next == `ROB_SIZE - 1 ? 0 : head_next + 1;
      end
    end

    // we assert in_rewind_next here since the above retire stage might
    // change it
    if (!in_rewind_next) begin
      /** complete stage logic **/
      for (int unsigned i = 0; i < `WAY; i++) begin
        if (complete[i].valid) begin
          rob_mem_next[complete[i].rob_index].complete = `TRUE;
        end
      end

      for (int unsigned i = 0; i < resolve.WIDTH; i++) begin
        if (resolve.valid[i] && rob_mem_next[resolve.rob_index[i]].valid) begin
          // process branch misprediction
          rob_mem_next[resolve.rob_index[i]].correct = `TRUE;
          if (rob_mem_next[resolve.rob_index[i]].target_pc != resolve.target_pc[i]) begin
            rob_mem_next[resolve.rob_index[i]].exception = `TRUE;
            rob_mem_next[resolve.rob_index[i]].code = NO_ERROR;
            rob_mem_next[resolve.rob_index[i]].correct = `FALSE;

            // check whether we need to update information for the oldest
            // instruction with exception
            dist1 = resolve.rob_index[i] >= head ?
                resolve.rob_index[i] - head :
                resolve.rob_index[i] + `ROB_SIZE - head;
            dist2 = oldest_exc_rob_index_next >= head ?
                oldest_exc_rob_index_next - head :
                oldest_exc_rob_index_next + `ROB_SIZE - head;
            if (dist1 < dist2 || !has_rewind_next) begin
              rewind_target_PC_next = resolve.target_pc[i];
              oldest_exc_rob_index_next = resolve.rob_index[i];
              fetch_flush_next = `TRUE;
            end

            has_rewind_next = `TRUE;
          end
          rob_mem_next[resolve.rob_index[i]].target_pc = resolve.target_pc[i];
          rob_mem_next[resolve.rob_index[i]].taken = resolve.taken[i];
        end
      end


      /** dispatch stage logic **/
      // not necessary to dispatch if there're exceptions in rob
      if (!has_rewind_next) begin
        occupied_spot_number = is_empty_next ? 0 :
          (tail_next >= head_next) ?
            (tail_next - head_next + 1) :
            (tail_next + `ROB_SIZE - head_next + 1);
        it_dispatch.num_can_dispatch_inst =
          ((`ROB_SIZE - occupied_spot_number) > `WAY) ?
            `WAY :
            (`ROB_SIZE - occupied_spot_number);

        for (int unsigned i = 0; i < it_dispatch.num_dispatched_inst; i++) begin
          is_empty_next = `FALSE;
          tail_next = tail_next == `ROB_SIZE - 1 ? 0 : tail_next + 1;
          rob_mem_next[tail_next] = 0;
          rob_mem_next[tail_next].arch_dest_reg = it_dispatch.arch_dest_reg[i];
          rob_mem_next[tail_next].T = it_dispatch.T_in[i];
          rob_mem_next[tail_next].Told = it_dispatch.Told_in[i];
          rob_mem_next[tail_next].fu_type = it_dispatch.fu_type[i];
          rob_mem_next[tail_next].fu_func = it_dispatch.fu_func[i];
          rob_mem_next[tail_next].code = NO_ERROR;
          rob_mem_next[tail_next].pc = it_dispatch.pc[i];
          rob_mem_next[tail_next].target_pc = it_dispatch.target_pc[i];
          rob_mem_next[tail_next].taken = it_dispatch.taken[i];

          // mark halt or illegal instruction to be completed since
          // they will never be issued
          // also set oldest_exc_rob_index_next and
          // exception_code in ROB entries
          // set has_rewind_next to be TRUE
          if (it_dispatch.halt[i] || it_dispatch.illegal[i]) begin
            rob_mem_next[tail_next].complete = `TRUE;
            rob_mem_next[tail_next].exception = `TRUE;

            unique if (it_dispatch.halt[i])
              rob_mem_next[tail_next].code = HALTED_ON_WFI;
            else if (it_dispatch.illegal[i])
              rob_mem_next[tail_next].code = ILLEGAL_INST;

            if (!has_rewind_next)
              oldest_exc_rob_index_next = tail_next;
            has_rewind_next = `TRUE;
          end

          rob_mem_next[tail_next].valid = `TRUE;
          it_dispatch.rob_index[i] = tail_next;
        end
      end
    end else begin
      /* rewind output logic */
      rewind.reg_T = 0;
      rewind.reg_Told = 0;
      for (int i = 0; i < `WAY; i++) begin
        // if there's only one instruction left (the exception instruction), then rewind finishes
        // normally retire this exception instruction next cycle
        if (head_next == tail_next) begin
          // TODO: check again the exception is really handled
          rob_mem_next[head_next].exception = `FALSE;
          in_rewind_next = `FALSE;
          has_rewind_next = `FALSE;
          rewind_target_PC_next = '0;
          oldest_exc_rob_index_next = '0;
          store_flush_next = `TRUE;
          break;
        end

        rewind.reg_T[i] = rob_mem_next[tail_next].T;
        rewind.reg_Told[i] = rob_mem_next[tail_next].Told;
        rewind.rob_index[i] = tail_next;
        rob_mem_next[tail_next] = 0; // clear the rob entry
        rewind.num++;
        tail_next = tail_next == 0 ? `ROB_SIZE - 1 : tail_next - 1;
      end
    end
  end
endmodule
