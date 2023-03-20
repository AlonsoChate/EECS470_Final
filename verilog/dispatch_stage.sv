/* DESIGN = p dispatch_stage */
`include "fetch.svh"
`include "dispatch.svh"
`include "sys_defs.svh"
`include "rename.svh"
`include "prepare.svh"

/*

basically all combinational logic to connect wires between ROB, RS, freelist, maptable for dispatch stage

*/


module dispatch_stage(
	  input         		                      clock, reset,

    /* instruction buffer */
    input fetch_packet_t [`WAY-1:0]         inst_buff_out,
    output logic [`WAY_CNT_LEN-1:0]         dispatch_stage_num_can_fetch,

    /* ROB Dispatch I/O */
    // # of instr.s actually dispatched to ROB, equal to # of valid instr.s in
    // inst_buff_out
    if_dispatch.dispatch_stage it_dispatch,

    /* RS I/O*/
    output dispatch_packet_t [`WAY-1:0]     dispatch,
    input [`WAY_CNT_LEN-1:0]                dispatch_empty_slots,

    input sq_idx_t store_tail_index,

    /* freelist I/O*/
    if_rename.dispatch_stage rename,

    /* map table I/O */
    if_prepare.dispatch_stage prepare
);
    logic [`WAY_CNT_LEN-1:0] valid_dispatch_num;  // number of instruction to dispatch this cycle
    sq_idx_t store_tail_index_next;

    /* decoded results */
    decoded_inst_t [`WAY-1:0] decode_result;
    arch_reg_idx_t [`WAY-1:0][1:0] arch_src_reg;
    //arch_reg_idx_t [`WAY-1:0] arch_dest_reg; // this becomes an output
    generate
        for(genvar i=0; i<`WAY; i++)begin
            decoder decoder0(
                // input
                .inst(inst_buff_out[i].inst),
                .valid(inst_buff_out[i].valid),
                // output
                .decoded_inst(decode_result[i]),
                .halt(it_dispatch.halt[i]),
                .illegal(it_dispatch.illegal[i]),
                .arch_src_reg(arch_src_reg[i]),
                .arch_dest_reg(it_dispatch.arch_dest_reg[i]));
        end
    endgenerate

    always_comb begin
        /* give # of instr.s ROB, RS, freelist can receive */
        dispatch_stage_num_can_fetch  = `WAY;
        // ROB
        if (dispatch_stage_num_can_fetch > it_dispatch.num_can_dispatch_inst)
            dispatch_stage_num_can_fetch = it_dispatch.num_can_dispatch_inst;
        // RS
        if (dispatch_stage_num_can_fetch > dispatch_empty_slots)
            dispatch_stage_num_can_fetch = dispatch_empty_slots;
        // Freelist
        if (dispatch_stage_num_can_fetch > rename.free_reg_valid)
            dispatch_stage_num_can_fetch = rename.free_reg_valid;

        /* get # of valid instr.s from instruction buffer*/
        valid_dispatch_num  = 0;
        for (int unsigned i = 0; i < `WAY; i++) begin
          if (inst_buff_out[i].valid) begin
            valid_dispatch_num++;
          end
        end

        /* output to Freelist */
        rename.num_to_dispatch = valid_dispatch_num;
        rename.arch_dest_reg = it_dispatch.arch_dest_reg;

        /* Output to Maptable */
        for (int unsigned i = 0; i < `WAY; i++) begin
            prepare.dispatch_input[i].arch_src_reg = arch_src_reg[i];
            prepare.dispatch_input[i].arch_dest_reg = it_dispatch.arch_dest_reg[i];    
        end
        prepare.free_tag = rename.dispatch_free_reg;
        prepare.num_maptable_update = valid_dispatch_num;

        /* Output to ROB */
        it_dispatch.num_dispatched_inst = valid_dispatch_num;
        it_dispatch.Told_in = '0;
        it_dispatch.T_in    = '0;
        it_dispatch.fu_type = fu_type_e'('0);
        it_dispatch.fu_func = '0;
        for (int unsigned i = 0; i < `WAY; i++)begin
          if (i < valid_dispatch_num) begin
            it_dispatch.Told_in[i] = prepare.Told_out[i];
            it_dispatch.T_in[i]    = rename.dispatch_free_reg[i];
            it_dispatch.fu_type[i] = decode_result[i].fu_type;
            it_dispatch.fu_func[i] = decode_result[i].fu_func;
            it_dispatch.pc[i] = inst_buff_out[i].PC;
            it_dispatch.target_pc[i] = inst_buff_out[i].target_pc;
            it_dispatch.taken[i] = inst_buff_out[i].taken;
          end
        end

        /* Output to RS */
        dispatch = 0;
        store_tail_index_next = store_tail_index;
        for (int unsigned i = 0; i < `WAY; i++)begin
          if (i < valid_dispatch_num && ~(it_dispatch.halt[i] || it_dispatch.illegal[i])) begin
            dispatch[i].pc = inst_buff_out[i].PC;
            dispatch[i].decoded_inst = decode_result[i];

            dispatch[i].phy_dest_reg.index = rename.dispatch_free_reg[i];
            if (dispatch[i].phy_dest_reg.index != 0)
                dispatch[i].phy_dest_reg.valid = `TRUE;

            dispatch[i].phy_src_reg[0].index = prepare.dispatch_output[i].phy_src_reg[0].index;
            dispatch[i].phy_src_reg[1].index = prepare.dispatch_output[i].phy_src_reg[1].index;
            if (dispatch[i].phy_src_reg[0].index != 0)
                dispatch[i].phy_src_reg[0].valid = `TRUE;
            if (dispatch[i].phy_src_reg[1].index != 0)
                dispatch[i].phy_src_reg[1].valid = `TRUE;

            dispatch[i].ready = prepare.dispatch_output[i].ready;

            dispatch[i].valid = `TRUE;
            dispatch[i].rob_index = it_dispatch.rob_index[i];
            if (dispatch[i].decoded_inst.fu_type == FU_MEM) begin
              dispatch[i].sq_index = store_tail_index_next;
              if (dispatch[i].decoded_inst.fu_func.mem.rw == FU_MEM_WRITE) begin
                store_tail_index_next = (store_tail_index_next + 1) % `SQ_SIZE;
              end
            end
          end
        end
    end
endmodule
