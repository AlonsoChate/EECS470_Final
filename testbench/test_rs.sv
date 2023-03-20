/* SOURCE = rs.sv selector.sv */

`timescale 1ns/100ps

module unittest;

parameter RS_SIZE   = 32;
parameter ROB_SIZE  = `PHY_REG_SIZE - 32;

// variables used in the testbench
logic   clock;
logic   reset;

dispatch_packet_t   [`WAY-1:0]          dispatch;
complete_packet_t   [`WAY-1:0]          complete;
issue_packet_t      [`WAY-1:0]          issue;
logic               [`CAL_IDX_LEN(`WAY)-1:0]                dispatch_empty_slots;
logic               [`CAL_IDX_LEN(`WAY)-1:0]                issue_empty_slots;
logic               [`WAY-1:0][`CAL_IDX_LEN(ROB_SIZE)-1:0]  issue_rob_index;

phy_reg_tag_t       [`WAY-1:0]                              correct_issue_targets;
logic               [`CAL_IDX_LEN(`WAY)-1:0]                correct_dispatch_empty_slots;
logic               [`WAY-1:0][`CAL_IDX_LEN(ROB_SIZE)-1:0]  correct_rob_index;

logic               [3:0]               error;
logic               [`CAL_IDX_LEN(RS_SIZE)-1:0]             inner_empty_slots;
logic               [`CAL_IDX_LEN(`WAY)-1:0]                current_dispatched;
logic rewind_valid;
rob_idx_t rewind_rob_index;

task report;
    begin
        $display("@@@ Time %4.0f", $time);
        $display("@@@ Dispatch empty slots: %h, Expected: %h", dispatch_empty_slots, correct_dispatch_empty_slots);
        $display("@@@ Issue empty slots: %h", issue_empty_slots);
        $display("@@@ ROB Index: %h, Expected: %h", issue_rob_index, correct_rob_index);

        $display("@@@ Issued 0 Target: %h, Valid: %b, Expected: %h", issue[0].target.index, issue[0].valid, correct_issue_targets[0]);
        $display("@@@ Issued 1 Target: %h, Valid: %b, Expected: %h", issue[1].target.index, issue[1].valid, correct_issue_targets[1]);
        $display("@@@ Issued 2 Target: %h, Valid: %b, Expected: %h", issue[2].target.index, issue[2].valid, correct_issue_targets[2]);

        for (int i = 0; i < 3; i++) begin
            if (issue[i].valid && issue[i].target.index != correct_issue_targets[i]) begin
                $display("@@@ Failed");
            end
        end

        $display("");
    end
endtask


rs      #(
    .D_WIDTH(`WAY),
    .C_WIDTH(`WAY),
    .I_WIDTH(`WAY),
    .SIZE(RS_SIZE),
    .ROB_SIZE(ROB_SIZE)
) rs_0  (
    .clock(clock),
    .reset(reset),
    .dispatch(dispatch),
    .complete(complete),
    .issue(issue),
    .dispatch_empty_slots(dispatch_empty_slots),
    .issue_empty_slots(issue_empty_slots),
    .issue_rob_index(issue_rob_index),
    .rewind_rob_index(rewind_rob_index),
    .rewind_valid(rewind_valid)
);


// Set up the clock to tick, notice that this block inverts clock every 5 ticks,
// so the actual period of the clock is 10, not 5.
always begin 
    #5;
    clock=~clock; 
end 

always @(posedge clock) begin
    report();
end

initial begin 
    clock = 0;
    reset = 1;
    
    dispatch = 0;
    complete = 0;
    issue_empty_slots = 'h3;

    correct_issue_targets           = 0;
    correct_dispatch_empty_slots    = 'h3;
    // correct_rob_index               = 0;

  rewind_valid = `FALSE;
  rewind_rob_index = 0;

    $display("STARTING TESTBENCH!");

    @(negedge clock);
    reset = 1;

    @(negedge clock);
    $display("@@  Test issuing one instruction at ready");

    reset = 0;

    // I0
    dispatch[0].valid = `TRUE;
    dispatch[0].ready = {`TRUE, `TRUE};
    dispatch[0].ps[0] = {'h1, `TRUE};
    dispatch[0].ps[1] = {'h2, `TRUE};
    dispatch[0].pd    = {'h40, `TRUE};

    @(negedge clock);
    dispatch[0].valid = `FALSE;
    correct_issue_targets[0] = 'h40;

    @(negedge clock);
    correct_issue_targets = 0;

    $display("@@  Test issuing 3 instructions");

    // I1
    dispatch[0].valid = `TRUE;
    dispatch[0].ready = {`TRUE, `TRUE};
    dispatch[0].ps[0] = {'h4, `TRUE};
    dispatch[0].ps[1] = {'h5, `TRUE};
    dispatch[0].pd    = {'h41, `TRUE};

    // I2
    dispatch[1].valid = `TRUE;
    dispatch[1].ready = {`TRUE, `TRUE};
    dispatch[1].ps[0] = {'h4, `TRUE};
    dispatch[1].ps[1] = {'h5, `TRUE};
    dispatch[1].pd    = {'h42, `TRUE};

    // I3
    dispatch[2].valid = `TRUE;
    dispatch[2].ready = {`TRUE, `TRUE};
    dispatch[2].ps[0] = {'h4, `TRUE};
    dispatch[2].ps[1] = {'h5, `TRUE};
    dispatch[2].pd    = {'h43, `TRUE};

    @(negedge clock);
    dispatch[0].valid = `FALSE;
    dispatch[1].valid = `FALSE;
    dispatch[2].valid = `FALSE;

    correct_issue_targets[0] = 'h41;
    correct_issue_targets[1] = 'h42;
    correct_issue_targets[2] = 'h43;

    @(negedge clock);
    correct_issue_targets = 0;

    $display("@@  Test issuing 3 not-ready instructions");

    // I4 <- I0, I1
    dispatch[0].valid = `TRUE;
    dispatch[0].ready = {`FALSE, `FALSE};
    dispatch[0].ps[0] = {'h40, `TRUE};
    dispatch[0].ps[1] = {'h41, `TRUE};
    dispatch[0].pd    = {'h44, `TRUE};

    // I5 <- I0, I2
    dispatch[1].valid = `TRUE;
    dispatch[1].ready = {`FALSE, `FALSE};
    dispatch[1].ps[0] = {'h40, `TRUE};
    dispatch[1].ps[1] = {'h42, `TRUE};
    dispatch[1].pd    = {'h45, `TRUE};

    // I6 <- I1, I2
    dispatch[2].valid = `TRUE;
    dispatch[2].ready = {`FALSE, `FALSE};
    dispatch[2].ps[0] = {'h41, `TRUE};
    dispatch[2].ps[1] = {'h42, `TRUE};
    dispatch[2].pd    = {'h46, `TRUE};

    @(negedge clock);
    dispatch[0].valid = `FALSE;
    dispatch[1].valid = `FALSE;
    dispatch[2].valid = `FALSE;

    // Waiting for I0, I1, I2 to complete...
    @(negedge clock);

    @(negedge clock);
    $display("@@  I0 completes");
    complete[0].tag = {'h40, `TRUE};

    @(negedge clock);
    $display("@@  I1, I2 completes; I4, I5, I6 should issue");
    complete = 0;
    complete[1].tag = {'h41, `TRUE};
    complete[2].tag = {'h42, `TRUE};

    correct_issue_targets[0] = 'h44;
    correct_issue_targets[1] = 'h45;
    correct_issue_targets[2] = 'h46;

    @(negedge clock);
    correct_issue_targets = 0;

    $display("@@  I3 completes");
    complete = 0;
    complete[0].tag = {'h43, `TRUE};

    // Insert lots of not-ready instructions
    inner_empty_slots = RS_SIZE;

    for (int i = 0; i <= RS_SIZE / 3 + 1; i++) begin
        @(negedge clock);
        current_dispatched = 0;

        if (dispatch_empty_slots > 0) begin
            // I7 <- I4, I5
            dispatch[0].valid = `TRUE;
            dispatch[0].ready = {`FALSE, `FALSE};
            dispatch[0].ps[0] = {'h44, `TRUE};
            dispatch[0].ps[1] = {'h45, `TRUE};
            dispatch[0].pd    = {'h48 + i * 3, `TRUE};

            current_dispatched++;
        end

        if (dispatch_empty_slots > 1) begin
            // I8 <- I5, I6
            dispatch[1].valid = `TRUE;
            dispatch[1].ready = {`FALSE, `FALSE};
            dispatch[1].ps[0] = {'h45, `TRUE};
            dispatch[1].ps[1] = {'h46, `TRUE};
            dispatch[1].pd    = {'h49 + i * 3, `TRUE};

            current_dispatched++;
        end

        if (dispatch_empty_slots > 2) begin
            // I9 <- I6, I4
            dispatch[2].valid = `TRUE;
            dispatch[2].ready = {`FALSE, `FALSE};
            dispatch[2].ps[0] = {'h46, `TRUE};
            dispatch[2].ps[1] = {'h44, `TRUE};
            dispatch[2].pd    = {'h4a + i * 3, `TRUE};

            current_dispatched++;
        end

        $display("@@  Remaining slots: %h", inner_empty_slots);

        correct_dispatch_empty_slots = inner_empty_slots > 3 ? 3 : inner_empty_slots;
        inner_empty_slots -= current_dispatched;
    end

    for (int i = 0; i <= RS_SIZE / 3; i++) begin
        @(negedge clock);

        if (i == 0) begin
            $display("@@  I4, I5, I6 completes");
            complete[0].tag = {'h44, `TRUE};
            complete[1].tag = {'h45, `TRUE};
            complete[2].tag = {'h46, `TRUE};
        end else
            complete = 0;

        dispatch = 0;

        correct_dispatch_empty_slots = 3;
        correct_issue_targets[0] = 'h48 + i * 3;
        correct_issue_targets[1] = 'h49 + i * 3;
        correct_issue_targets[2] = 'h4a + i * 3;
        
        for (int j = 0; j < 3; j++)
            correct_issue_targets[j] = correct_issue_targets[j] < 'h68 ? correct_issue_targets[j] : 0;
    end

    @(negedge clock);
    correct_issue_targets = 0;

    @(negedge clock);

    @(negedge clock);
    reset = 1;

    @(negedge clock);
    reset = 0;


    $display("@@@ Passed");
    @(negedge clock);
    $finish;

end

endmodule
