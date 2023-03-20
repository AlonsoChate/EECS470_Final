/* DESIGN = p rs */
`include "sys_defs.svh"

// Q_SIZE to S_SIZE selector, the order is *unspecified*. In this
// implementation, it will select the S_SIZE signals with highest
// indices.
module selector #(
  parameter Q_SIZE = 32,
  parameter S_SIZE = 3,
  localparam INDEX_LEN = `CAL_IDX_LEN(Q_SIZE)
) (
  input [Q_SIZE-1:0] request,
  output logic [S_SIZE-1:0][INDEX_LEN-1:0] select,
  output logic [S_SIZE-1:0] valid
);
  logic [Q_SIZE-1:0] request_next;
  always_comb begin
    request_next = request;
    select = {(INDEX_LEN * S_SIZE){`FALSE}};
    valid = {(S_SIZE){`FALSE}};
    for (int k = 0; k < S_SIZE; k++) begin
      for (int i = 0; i < Q_SIZE; i++) begin
        if (request_next[i]) begin
          select[k] = i[INDEX_LEN-1:0];
          valid[k] = `TRUE;
        end
      end
      if (valid[k]) begin
        request_next[select[k]] = `FALSE;
      end
    end
  end
endmodule
