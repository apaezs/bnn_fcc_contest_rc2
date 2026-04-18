module NP_UNIT_WithThreshold #(
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
    input  logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] threshold,

    output logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] popcount_total,
    output logic y,
    output logic valid_out,
    output logic valid_acc
);

  localparam int ACC_W = $clog2(TOTAL_BITS_NEURON+1);

  logic             acc_en, acc_ld;
  logic             valid_in_r;
  logic             last_in_r;
  logic [PW-1:0]    x_r;
  logic [PW-1:0]    w_r;
  logic [ACC_W-1:0] threshold_r;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      valid_in_r <= 1'b0;
    end else begin
      valid_in_r <= valid_in;
    end
  end

  always_ff @(posedge clk) begin
    x_r         <= x;
    w_r         <= w;
    threshold_r <= threshold;
    last_in_r   <= valid_in ? last_in : '0;
  end

  NP_FSM_WithOutputValid #(.LAT(LAT)) u_fsm (
    .clk       (clk),
    .rst       (rst),
    .valid_in  (valid_in_r),
    .last_in   (last_in_r),
    .acc_en    (acc_en),
    .acc_ld    (acc_ld),
    .valid_out (valid_out),
    .valid_acc (valid_acc)
  );

  NP_DP_WithThreshold #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TOTAL_BITS_NEURON)
  ) u_dp (
    .clk            (clk),
    .x              (x_r),
    .w              (w_r),
    .acc_en         (acc_en),
    .acc_ld         (acc_ld),
    .threshold      (threshold_r),
    .popcount_total (popcount_total),
    .y              (y)
  );

endmodule
