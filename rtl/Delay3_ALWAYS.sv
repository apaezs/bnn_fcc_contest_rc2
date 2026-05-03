`timescale 1ns / 1ps

module Delay3_ALWAYS #(
    parameter int DWIDTH    = 32,
    parameter int FINAL_DLY = 4,
    parameter int TAP1_DLY  = 0,
    parameter int TAP2_DLY  = 1
)(
    input  logic              clk,

    input  logic [DWIDTH-1:0] din,
    output logic [DWIDTH-1:0] dout_tap1,
    output logic [DWIDTH-1:0] dout_tap2,
    output logic [DWIDTH-1:0] dout_final
);

    localparam int DEPTH_A = (FINAL_DLY >= TAP1_DLY) ? FINAL_DLY : TAP1_DLY;
    localparam int DEPTH   = (DEPTH_A  >= TAP2_DLY) ? DEPTH_A  : TAP2_DLY;

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

    assign dout_tap1  = stage[TAP1_DLY];
    assign dout_tap2  = stage[TAP2_DLY];
    assign dout_final = stage[FINAL_DLY];

endmodule
