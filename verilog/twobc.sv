/* DESIGN = p branch_predictor twobc */

/*
 *** FSM for the two bit saturation counter
*/

module twobc (
    input              clock, reset,
    input              take,
    input              enable,
    input              reset_counter,

    output logic       predict_bit
);

    localparam SN = 2'b00;
    localparam N = 2'b01;
    localparam T = 2'b11;
    localparam ST = 2'b10;
    logic [1:0] curr_state;
    logic [1:0] next_state;
    logic [1:0] reset_and_en;
    
    assign predict_bit = curr_state[1];
    assign reset_and_en = take ? 2'b01 : 2'b00;

    always_ff @(posedge clock) begin
        if (reset) begin
            curr_state <= `SD 2'b00;
        end else begin
            if (reset_counter) begin
                curr_state <= `SD reset_and_en;
            end else if (enable) begin
                curr_state <= `SD next_state;
            end
        end
    end

    always_comb begin
        next_state = curr_state;
        case (curr_state)
            SN: begin
                next_state = (take) ? N : SN;
            end
            N: begin
                next_state = (take) ? T : SN;
            end
            T: begin
                next_state = (take) ? ST : N;
            end
            ST: begin
                next_state = (take) ? ST : T;
            end
        endcase
    end

endmodule

