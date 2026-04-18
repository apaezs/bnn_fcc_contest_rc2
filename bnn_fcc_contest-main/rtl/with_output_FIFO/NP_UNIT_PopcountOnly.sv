`timescale 1ns/1ps

module NP_UNIT_PopcountOnly #(
    parameter int LAYER_ID           = 0,
    parameter int LANE_ID            = 0,
    parameter int PW                 = 32,
    parameter int TOTAL_BITS_NEURON  = 64,
    parameter int LAT                = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic last_in,
    input  logic [PW-1:0] x,
    input  logic [PW-1:0] w,

    output logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] popcount_total,
    output logic valid_acc
);

  logic acc_en, acc_ld;
  logic          valid_in_r;
  logic          last_in_r;
  logic [PW-1:0] x_r;
  logic [PW-1:0] w_r;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      valid_in_r <= 1'b0;
    end else begin
      valid_in_r <= valid_in;
    end
  end

  always_ff @(posedge clk) begin
    x_r <= x;
    w_r <= w;
    last_in_r <= valid_in ? last_in : '0;
  end

  NP_FSM_PopcountOnly #(.LAT(LAT)) u_fsm (
    .clk       (clk),
    .rst       (rst),
    .valid_in  (valid_in_r),
    .last_in   (last_in_r),
    .acc_en    (acc_en),
    .acc_ld    (acc_ld),
    .valid_acc (valid_acc)
  );

  NP_DP_PopcountOnly #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TOTAL_BITS_NEURON)
  ) u_dp (
    .clk            (clk),
    .x              (x_r),
    .w              (w_r),
    .acc_en         (acc_en),
    .acc_ld         (acc_ld),
    .popcount_total (popcount_total)
  );

endmodule
