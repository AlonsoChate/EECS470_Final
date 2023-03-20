`ifndef __PREPARE_SVH__
`define __PREPARE_SVH__

interface if_prepare;
  map_table_input_t [`WAY-1:0]     dispatch_input;             // arch source and dest register
  phy_reg_idx_t [`WAY-1:0]         free_tag;                   // T from freelist
  logic [`WAY_CNT_LEN-1:0]         num_maptable_update;
  map_table_output_t [`WAY-1:0]    dispatch_output;            // PR source and ready bits
  phy_reg_idx_t [`WAY-1:0]         Told_out;                   // Told send back to rob

  modport dispatch_stage(
    output dispatch_input,
    output free_tag,
    output num_maptable_update,
    input dispatch_output,
    input Told_out
  );

  modport map_table(
    input dispatch_input,
    input free_tag,
    input num_maptable_update,
    output dispatch_output,
    output Told_out
  );
endinterface

`endif // __PREPARE_SVH__
