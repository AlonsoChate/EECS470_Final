/* DESIGN = p map_table */
`include "sys_defs.svh"
`include "fetch.svh"
`include "dispatch.svh"
`include "prepare.svh"
`include "rewind.svh"

/*
    CDB_tag should be 0 for no instruction completion, map_table will set
    ready bit for arch reg0 and phy reg0, which is fine
*/

module map_table (
    input clock, reset,
    
    /* dispatch stage I/O */
    if_prepare.map_table prepare,

    /* complete stage I/O */
    input phy_reg_idx_t               [`WAY-1:0]    CDB_tag,                // used to set the ready bit

    /* branch rewind */
    if_rewind.map_table rewind
);

    phy_reg_idx_t [`ARCH_REG_SIZE-1:0] map;
    phy_reg_idx_t [`ARCH_REG_SIZE-1:0] map_next;
    logic [`ARCH_REG_SIZE-1:0] ready;
    logic [`ARCH_REG_SIZE-1:0] ready_next;

    always_ff @(posedge clock) begin
        if (reset) begin
            for (int i = 0; i < `ARCH_REG_SIZE; i++) begin
                map[i]   <= `SD i;
                ready[i] <= `SD `TRUE; // all ready at the reset
            end
        end else begin
            map     <= `SD map_next;
            ready   <= `SD ready_next;
        end
    end

    always_comb begin
        map_next = map;
        ready_next = ready;
        prepare.dispatch_output = 0;
        prepare.Told_out = 0;

        /* complete stage */
        for (int i = 0; i < `ARCH_REG_SIZE; i++) begin
            for (int j = 0; j < `WAY; j++) begin
                if (map_next[i] == CDB_tag[j])
                    ready_next[i] = 1'b1;
            end
        end

        if (rewind.num == 0) begin
            /* dispatch stage */
            
            for (int i = 0; i < prepare.num_maptable_update; i++) begin
                prepare.dispatch_output[i].phy_src_reg[0].valid = `TRUE;
                prepare.dispatch_output[i].phy_src_reg[0].index = map_next[prepare.dispatch_input[i].arch_src_reg[0]];
                prepare.dispatch_output[i].phy_src_reg[1].valid = `TRUE;
                prepare.dispatch_output[i].phy_src_reg[1].index = map_next[prepare.dispatch_input[i].arch_src_reg[1]];
                prepare.dispatch_output[i].ready[0] = ready_next[prepare.dispatch_input[i].arch_src_reg[0]];
                prepare.dispatch_output[i].ready[1] = ready_next[prepare.dispatch_input[i].arch_src_reg[1]];

                // send Told to rob and update T from freelist
                // do nothing if source register is 0
                if (prepare.dispatch_input[i].arch_dest_reg != 0) begin
                    prepare.Told_out[i] = map_next[prepare.dispatch_input[i].arch_dest_reg];
                    map_next[prepare.dispatch_input[i].arch_dest_reg] = prepare.free_tag[i];
                    ready_next[prepare.dispatch_input[i].arch_dest_reg] = 1'b0;
                end
                prepare.dispatch_output[i].phy_dest_reg = map_next[prepare.dispatch_input[i].arch_dest_reg];
            end
        end else begin
            for (int i = 0; i < rewind.num; i++) begin
                for (int j = 0; j < `ARCH_REG_SIZE; j++) begin
                    if (map_next[j] == rewind.reg_T[i]) begin
                        map_next[j] = rewind.reg_Told[i];
                        ready_next[j] = 1'b1;
                    end
                end
            end
        end
    end
endmodule
