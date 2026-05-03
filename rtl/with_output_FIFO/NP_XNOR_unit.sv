`timescale 1ns/1ps

module NP_XNOR_unit #(
    parameter int PW = 32
)(
    input  logic          clk,
    input  logic [PW-1:0] x,
    input  logic [PW-1:0] w,
    output logic [PW-1:0] out
);

    logic [PW-1:0] x_r;
    logic [PW-1:0] w_r;

    always_ff @(posedge clk) begin
        x_r <= x;
        w_r <= w;
    end

    always_ff @(posedge clk) begin
        out <= ~(x_r ^ w_r);
    end

endmodule
