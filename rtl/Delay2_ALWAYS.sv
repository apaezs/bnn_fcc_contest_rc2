`timescale 1ns / 1ps

module Delay2_ALWAYS #(
    parameter int DWIDTH    = 32,
    parameter int FINAL_DLY = 4,
    parameter int TAP_DLY   = 0
)(
    input  logic              clk,

    input  logic [DWIDTH-1:0] din,
    output logic [DWIDTH-1:0] dout_tap,
    output logic [DWIDTH-1:0] dout_final
);

    localparam int DEPTH = (FINAL_DLY >= TAP_DLY) ? FINAL_DLY : TAP_DLY;

    logic [DWIDTH-1:0] stage [0:DEPTH];
    assign stage[0] = din;

    genvar i;
    generate
        for (i = 0; i < DEPTH; i++) begin : GEN_DELAY
            Register_ALWAYS #(
                .DWIDTH(DWIDTH)
            ) reg_i (
                .clk(clk),
                .d  (stage[i]),
                .q  (stage[i+1])
            );
        end
    endgenerate

    assign dout_tap   = stage[TAP_DLY];
    assign dout_final = stage[FINAL_DLY];

endmodule
