`timescale 1ns / 1ps

module Pulse (
    input  logic clk,
    input  logic in,
    
    output logic pulse
);

    logic in_d;

    always_ff @(posedge clk) begin
        in_d <= in;
    end

    assign pulse = in & ~in_d;

endmodule
