/* SOURCE = cq.sv */

`timescale 1ns/100ps

module testbench;
  logic clock, reset;

  always #5 clock = ~clock;

  localparam SIZE = 32;
  localparam E_WIDTH = 7;
  localparam C_WIDTH = 3;

  result_packet_t [E_WIDTH-1:0] execute;
  logic [E_WIDTH-1:0] stall;
  complete_packet_t [C_WIDTH-1:0] complete;

  cq #(SIZE, C_WIDTH, E_WIDTH) dut (
    .clock(clock),
    .reset(reset),
    .execute(execute),
    .stall(stall),
    .complete(complete)
  );

  phy_reg_idx_t phy_reg_idx;

  integer avail;

  initial begin
    $dumpfile("cq.vcd");
    $dumpvars(0, testbench);

    avail = SIZE;
    clock = 0;
    reset = 1;

    @(negedge clock);
    reset = 0;
    execute[0].target.index = 1;
    execute[0].target.valid = `TRUE;
    execute[0].result = 32'hdeadbeef;
    execute[0].rob_index = 2;
    execute[0].valid = `TRUE;
    for (int i = 1; i < E_WIDTH; i++) begin
      execute[i] = execute[i - 1];
      execute[i].target.index++;
      execute[i].result++;
      execute[i].rob_index++;
    end
    avail -= $min(avail, E_WIDTH);

    @(posedge clock);
    $display("head: %d, tail: %d", dut.head, dut.tail);
    for (int i = 0; i < $min(avail, E_WIDTH); i++) begin
      if (stall[i]) begin
        $display("stall[%d]", i);
      end
      assert(stall[i] == `FALSE);
    end
    for (int i = $min(avail, E_WIDTH); i < E_WIDTH; i++) begin
      assert(stall[i] == `TRUE);
    end

    for (int i = 0; i < C_WIDTH; i++) begin
      assert(complete[i].tag.valid == `FALSE);
    end

    @(negedge clock);
    avail -= $min(avail, E_WIDTH);

    @(posedge clock);
    $display("head: %d, tail: %d", dut.head, dut.tail);
    for (int i = 0; i < $min(avail, E_WIDTH); i++) begin
      assert(stall[i] == `FALSE);
    end
    for (int i = $min(avail, E_WIDTH); i < E_WIDTH; i++) begin
      assert(stall[i] == `TRUE);
    end

    for (int i = 0; i < $min(E_WIDTH, C_WIDTH); i++) begin
      $display("complete[%d].tag.valid: %b", i, complete[i].tag.valid);
      assert(complete[i].tag.valid);
      $display("complete[%d].tag.index: %h", i, complete[i].tag.index);
      assert(complete[i].tag.index == 1 + i);
      $display("complete[%d].rob_index: %h", i, complete[i].rob_index);
      assert(complete[i].rob_index == 2 + i);
    end
    for (int i = $min(E_WIDTH, C_WIDTH); i < C_WIDTH; i++) begin
      assert(complete[i].tag.valid == `FALSE);
    end

    @(negedge clock);
    avail -= $min(avail, E_WIDTH);

    @(posedge clock);
    $display("head: %d, tail: %d", dut.head, dut.tail);
    for (int i = 0; i < $min(avail, E_WIDTH); i++) begin
      assert(stall[i] == `FALSE);
    end
    for (int i = $min(avail, E_WIDTH); i < E_WIDTH; i++) begin
      assert(stall[i] == `TRUE);
    end

    $finish;
  end

endmodule
