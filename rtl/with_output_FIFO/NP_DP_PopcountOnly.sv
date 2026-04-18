`timescale 1ns/1ps

module NP_DP_PopcountOnly #(
    parameter int PW                = 32,
    parameter int TOTAL_BITS_NEURON = 64
)(
    input  logic clk,

    input  logic [PW-1:0] x,
    input  logic [PW-1:0] w,

    input  logic acc_en,
    input  logic acc_ld,

    output logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] popcount_total
);

  localparam int POP_W = $clog2(PW + 1);
  localparam int ACC_W = $clog2(TOTAL_BITS_NEURON + 1);

  logic [PW-1:0]    xnor_bits;
  logic [POP_W-1:0] popcount_beat;

  NP_XNOR_unit #(.PW(PW)) u_xnor (
    .clk (clk),
    .x   (x),
    .w   (w),
    .out (xnor_bits)
  );

  NP_Pop_unit #(
    .iwidth(PW),
    .owidth(POP_W)
  ) u_pop (
    .clk   (clk),
    .x     (xnor_bits),
    .count (popcount_beat)
  );

  NP_Accum_Unit #(
    .iwidth(POP_W),
    .owidth(ACC_W)
  ) u_accum (
    .clk (clk),
    .en  (acc_en),
    .ld  (acc_ld),
    .din (popcount_beat),
    .acc (popcount_total)
  );

endmodule
