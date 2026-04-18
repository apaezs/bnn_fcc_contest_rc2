module Delay_ALWAYS #(
    parameter int DWIDTH = 32,
    parameter int DELAY  = 1
)(
    input  logic              clk,

    input  logic [DWIDTH-1:0] din,
    output logic [DWIDTH-1:0] dout
);

    logic [DWIDTH-1:0] stage [0:DELAY];

    assign stage[0] = din;

    genvar i;
    generate
        for (i = 0; i < DELAY; i++) begin : GEN_DELAY
            Register_ALWAYS #(
                .DWIDTH(DWIDTH)
            ) reg_i (
                .clk(clk),
                .d  (stage[i]),
                .q  (stage[i+1])
            );
        end
    endgenerate

    assign dout = stage[DELAY];

endmodule
