/* DESIGN = p branch_predictor twobc */
`include "sys_defs.svh"
`include "dispatch.svh"
`include "complete.svh"
`include "issue.svh"
`include "fetch.svh"
`include "resolve.svh"
`include "update.svh"

/*
 *** branch predictor with pattern and target PC
*/
module branch_predictor(
    input clock, reset,
    /* input from fetch stage */
    input logic [`WAY-1:0] pc_find_valid,
    input PC_t [`WAY-1:0] pc_find,

    /* input from execute stage */
    if_resolve.branch_predictor resolve,

    if_update.branch_predictor update,

    /* output to fetch state */
    output logic [`WAY-1:0] predict_result,
    output PC_t  [`WAY-1:0] target_pc_output
);
    typedef struct packed {
        br_buf_tag_t tag;
        PC_t target_pc;
        
        logic enable;
        logic take;
        logic reset_counter;
    } branch_entry;

    branch_entry [`BR_BUF_SIZE-1:0] branch_buffer;
    branch_entry [`BR_BUF_SIZE-1:0] branch_buffer_next;

    logic [`BR_BUF_SIZE-1:0] predict_taken;

    generate
        for(genvar i = 0; i < `BR_BUF_SIZE; i++) begin
            twobc counter0(
                // input
                .clock(clock),
                .reset(reset),
                .reset_counter(branch_buffer[i].reset_counter),
                .enable(branch_buffer[i].enable),
                .take(branch_buffer[i].take),
                // output
                .predict_bit(predict_taken[i]));
        end
    endgenerate

    br_buf_idx_t [`WAY-1:0] resolve_index;
    br_buf_tag_t [`WAY-1:0] resolve_tag;
    br_buf_idx_t [`WAY-1:0] find_index;
    br_buf_tag_t [`WAY-1:0] find_tag;
    br_buf_idx_t [`WAY-1:0] update_index;
    br_buf_idx_t [`WAY-1:0] update_tag;


    always_ff @(posedge clock) begin
        if (reset) begin
            // position <= `SD 0;
            branch_buffer <= `SD 0;
        end else begin
            // position <= `SD position_next;
            branch_buffer <= `SD branch_buffer_next;
        end
    end

  always_comb begin
    /* initialized in each logic */
    branch_buffer_next = branch_buffer;
    // position_next = position;
    resolve_index = '0;
    resolve_tag = '0;
    for (int i = 0; i < resolve.WIDTH; i++) begin
      if (resolve.valid[i]) begin
        resolve_index[i] = resolve.source_pc[i][`BR_BUF_IDX_LEN-1:0];
        resolve_tag[i] = resolve.source_pc[i][`XLEN-1:`BR_BUF_IDX_LEN];
      end
    end

    find_index = '0;
    find_tag = '0;
    for (int i = 0; i < `WAY; i++) begin
      if (pc_find_valid[i]) begin
        find_index[i] = pc_find[i][`BR_BUF_IDX_LEN-1:0];
        find_tag[i] = pc_find[i][`XLEN-1:`BR_BUF_IDX_LEN];
      end
    end

    update_index = '0;
    update_tag = '0;
    for (int i = 0; i < `WAY; i++) begin
      if (update.valid[i]) begin
        update_index[i] = update.source_pc[i][`BR_BUF_IDX_LEN-1:0];
        update_tag[i] = update.source_pc[i][`XLEN-1:`BR_BUF_IDX_LEN];
      end
    end

    for (int i = 0; i < `BR_BUF_SIZE; i++) begin
        branch_buffer_next[i].enable = `FALSE;
        branch_buffer_next[i].reset_counter = `FALSE;
    end

    /* new branch come in and update the buffer */
    for (int i = 0; i < resolve.WIDTH; i++) begin
      resolve.correct[i] = `TRUE;
      if (resolve.valid[i]) begin
        if (predict_taken[resolve_index[i]] != resolve.taken[i]) begin
          resolve.correct = `FALSE;
        end
        if (predict_taken[resolve_index[i]] && resolve.taken[i]) begin
          if (branch_buffer_next[resolve_index[i]].target_pc != resolve.target_pc[i]) begin
            resolve.correct = `FALSE;
          end
        end
      end
    end

    for (int i = 0; i < update.WIDTH; i++) begin
      if (update.valid[i]) begin
        if (update_tag[i] != branch_buffer_next[update_index[i]].tag) begin
          branch_buffer_next[update_index[i]].tag = update_tag[i];
          branch_buffer_next[update_index[i]].target_pc = update.target_pc[i];
          branch_buffer_next[update_index[i]].reset_counter = `TRUE;
        end else begin
          if (branch_buffer_next[update_index[i]].target_pc != update.target_pc[i]) begin
            branch_buffer_next[update_index[i]].target_pc = update.target_pc[i];
          end
        end
        branch_buffer_next[update_index[i]].enable = `TRUE;
        branch_buffer_next[update_index[i]].take = update.taken[i];
      end
    end 
    
    /* look for pc from fetch stage to see whether it is a branch and predict the result */
    predict_result = '0;
    target_pc_output = '0;
    for (int i = 0; i < `WAY; i++) begin
      if (pc_find_valid[i]) begin
        if (branch_buffer_next[find_index[i]].tag == find_tag[i]) begin
          predict_result[i] = predict_taken[find_index[i]];
          if (predict_result[i]) begin
            target_pc_output[i] = branch_buffer_next[find_index[i]].target_pc;
          end else begin
            target_pc_output[i] = pc_find[i] + 4;
          end
        end else begin
          predict_result[i] = `FALSE;
          target_pc_output[i] = pc_find[i] + 4;
        end
      end
    end
  end
endmodule
