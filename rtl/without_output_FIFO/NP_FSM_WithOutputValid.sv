`timescale 1ns / 1ps

module NP_FSM_WithOutputValid #(
    parameter int LAT = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic last_in,

    output logic acc_en,
    output logic acc_ld,
    output logic valid_out,
    output logic valid_acc
);

  localparam int ALIGN_DELAY = (LAT >= 4) ? (LAT - 4) : 0;
  localparam int CNT_W       = (LAT <= 0) ? 1 : $clog2(LAT + 2);

  logic [$clog2(LAT+2)-1:0] reverse_lat, reverse_next_lat;

  logic valid_aligned;

  logic last_aligned;
  logic last_to_valid_acc;
  logic last_to_valid_out;

  logic need_first_pop_r, need_first_pop_d;

  logic acc_en_d;
  logic acc_ld_d;

  logic pipeline_busy;
  logic pipeline_drained;

  logic flush_active;
  logic [CNT_W-1:0] flush_count_r, flush_count_d;

  logic valid_in_g;
  logic valid_aligned_g;
  logic last_aligned_g;
  logic last_to_valid_acc_g;
  logic last_to_valid_out_g;

  generate
    if (ALIGN_DELAY == 0) begin : g_valid_align_bypass
      assign valid_aligned = valid_in;
    end else begin : g_valid_align_delay
      Delay_ALWAYS #(
        .DWIDTH(1),
        .DELAY (ALIGN_DELAY)
      ) u_valid_align (
        .clk (clk),
        .din (valid_in),
        .dout(valid_aligned)
      );
    end
  endgenerate

  Delay3_ALWAYS #(
    .DWIDTH   (1),
    .FINAL_DLY(LAT),
    .TAP1_DLY (ALIGN_DELAY),
    .TAP2_DLY (LAT - 1)
  ) u_last_delay (
    .clk       (clk),
    .din       (last_in),
    .dout_tap1 (last_aligned),
    .dout_tap2 (last_to_valid_acc),
    .dout_final(last_to_valid_out)
  );

  assign flush_active        = (flush_count_r != '0);

  assign valid_in_g          = flush_active ? 1'b0 : valid_in;
  assign valid_aligned_g     = flush_active ? 1'b0 : valid_aligned;
  assign last_aligned_g      = flush_active ? 1'b0 : last_aligned;
  assign last_to_valid_acc_g = flush_active ? 1'b0 : last_to_valid_acc;
  assign last_to_valid_out_g = flush_active ? 1'b0 : last_to_valid_out;

  assign pipeline_busy       = valid_aligned_g || last_to_valid_out_g;
  assign pipeline_drained    = !pipeline_busy;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      reverse_lat      <= '0;
      need_first_pop_r <= 1'b1;
      acc_en           <= 1'b0;
      acc_ld           <= 1'b0;
      flush_count_r    <= LAT[CNT_W-1:0];
    end else begin
      reverse_lat      <= reverse_next_lat;
      need_first_pop_r <= need_first_pop_d;
      acc_en           <= acc_en_d;
      acc_ld           <= acc_ld_d;
      flush_count_r    <= flush_count_d;
    end
  end

  always_comb begin
    valid_out = 1'b0;
    valid_acc = 1'b0;
    acc_en_d  = 1'b0;
    acc_ld_d  = 1'b0;

    reverse_next_lat = reverse_lat;
    need_first_pop_d = need_first_pop_r;
    flush_count_d    = flush_count_r;

    if (flush_active) begin
      reverse_next_lat = '0;
      need_first_pop_d = 1'b1;

      if (flush_count_r != '0)
        flush_count_d = flush_count_r - 1'b1;
    end else begin
      if (valid_aligned_g) begin
        if (need_first_pop_r)
          acc_ld_d = 1'b1;
        else
          acc_en_d = 1'b1;
      end

      if (pipeline_drained) begin
        need_first_pop_d = 1'b1;
      end else if (valid_aligned_g && last_aligned_g) begin
        need_first_pop_d = 1'b1;
      end else if (valid_aligned_g && need_first_pop_r) begin
        need_first_pop_d = 1'b0;
      end

      if (valid_in_g) begin
        reverse_next_lat = LAT;
      end else if (|reverse_lat) begin
        reverse_next_lat = reverse_lat - 1'b1;
      end else begin
        reverse_next_lat = '0;
      end

      if (pipeline_drained)
        reverse_next_lat = '0;

      valid_acc = last_to_valid_acc_g;
      valid_out = last_to_valid_out_g;
    end
  end

endmodule
