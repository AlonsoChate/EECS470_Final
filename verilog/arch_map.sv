/* DESIGN = arch_map */
`include "sys_defs.svh"

module arch_map #(
    parameter R_WIDTH = 3,
    parameter REG_SIZE = 32
) (
    input clock, reset,
    input arch_reg_idx_t [R_WIDTH-1:0] arch_reg,
    input phy_reg_idx_t  [R_WIDTH-1:0] phy_tag
);

    phy_reg_idx_t [REG_SIZE-1:0] map, map_next;

    always_comb begin
      for (int unsigned i = 0; i < R_WIDTH; i++)
        if (phy_tag[i] != '0)
          map_next[arch_reg[i]] = phy_tag[i];
    end

    always_ff @(posedge clock) begin
      if (reset)
        for (int unsigned i = 0; i < REG_SIZE; i++)
          map[i] <= `SD `PHY_REG_IDX_LEN'(i);
      else
        map <= `SD map_next;
    end

endmodule
