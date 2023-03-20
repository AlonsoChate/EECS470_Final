/* DESIGN = p freelist */
`include "dispatch.svh"
`include "complete.svh"
`include "issue.svh"
`include "fetch.svh"
`include "rename.svh"
`include "rewind.svh"
`include "retire.svh"

/*
some cases for rewind:
    rewind inst1(Told = PR1), store(Told = PR0), inst2(Told = PR2)
    get PR1, PR2

some cases for dispatch:
    dispatch inst1(dest = R1), store(dest = R0), inst2(dest = R3)
    give PR_A, PR_0, PR_B
*/

module freelist(
    input                                       clock, reset,

    if_rename.freelist rename,

    /* Retire stage I/O */
    if_retire.freelist retire,

    /* rewind I/O */
    if_rewind.freelist rewind
);
    
    /* stage registers */
    phy_reg_idx_t                               head;               // Head points to the PR for T new
    phy_reg_idx_t                               tail;
    phy_reg_idx_t  [`FREELIST_SIZE-1:0]      free_list_entry;
    logic                                       isEmpty;

    /* next stage registers */
    phy_reg_idx_t                               head_next;
    phy_reg_idx_t                               tail_next;
    phy_reg_idx_t  [`FREELIST_SIZE-1:0]      free_list_entry_next ;
    logic                                       isEmpty_next;

    /* temp variables */
    integer free_reg_number;

    always_ff @(posedge clock) begin
        if(reset)begin
            head            <= `SD 0;
            tail            <= `SD `FREELIST_SIZE - 1;
            isEmpty         <= `SD `FALSE;
            // assume PR 0~31 is mapped in the map table
            for (int i=0; i<`FREELIST_SIZE; i++) begin
                free_list_entry[i] <= `SD i+32;
            end
        end else begin
            head            <= `SD head_next;
            tail            <= `SD tail_next;
            free_list_entry <= `SD free_list_entry_next;
            isEmpty         <= `SD isEmpty_next;
        end
    end

    always_comb begin
        head_next = head;
        tail_next = tail;
        free_list_entry_next = free_list_entry;
        isEmpty_next = isEmpty;
        rename.dispatch_free_reg = 0;

        free_reg_number = isEmpty ? 0 :
                    (tail >= head) ? (tail - head + 1) : (tail + `FREELIST_SIZE - head + 1);
        rename.free_reg_valid = free_reg_number > `WAY ? `WAY : free_reg_number;

        /* retire stage */
        // get Told from rob, may happen at the same time of rewind
        for(int i=0; i<`WAY; i++)begin
            // jump for cases like store instruction
            if (retire.Told[i] != 0) begin
                tail_next = tail_next == `FREELIST_SIZE - 1 ? 0 : tail_next + 1;
                free_list_entry_next[tail_next] = retire.Told[i];
                isEmpty_next = `FALSE;
            end
        end

        if(rewind.num == 0) begin
            /* dispatch stage */
            // give T based on input
            for (int i=0; i<rename.num_to_dispatch; i++)begin
                // don't give T if dest register is 0
                if (!isEmpty_next && rename.arch_dest_reg[i] != 0) begin
                    rename.dispatch_free_reg[i] = free_list_entry_next[head_next];
                    if(head_next == tail_next)
                        isEmpty_next = `TRUE;
                    head_next = head_next == `FREELIST_SIZE - 1 ? 0 : head_next + 1;
                end
            end
        end else begin
            /* rewind logic, get T from rog */
            for(int i=`WAY - 1; i>=0; i--)begin
                if(rewind.reg_T[i] != 0) begin
                    head_next = head_next > 0 ? head_next - 1 : `FREELIST_SIZE - 1;
                    free_list_entry_next[head_next] = rewind.reg_T[i];
                    if(isEmpty_next)
                        isEmpty_next = `FALSE;
                end
            end
        end
    end
endmodule
