`timescale 1ns/1ps

module Layer_WithThreshold #(
    parameter int LAYER_ID = 0,
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int TN = 16,
    parameter int N_NEURONS = 16,
    parameter int TW = 32,
    parameter int LAT = 4,
    localparam int beats   = (TN + PW - 1) / PW,
    localparam int BEAT_W  = (beats <= 1) ? 1 : $clog2(beats),
    localparam int GROUPS  = (N_NEURONS + PN - 1) / PN,
    localparam int TW_addr = (GROUPS <= 1) ? 1 : $clog2(GROUPS),
    localparam int W_addr  = (beats * GROUPS <= 1) ? 1 : $clog2(beats * GROUPS),
    localparam int OUTC_W  = (GROUPS <= 1) ? 1 : $clog2(GROUPS + 1),
    localparam int BANK_W  = (PN <= 1) ? 1 : $clog2(PN)
)(
    input  logic clk,
    input  logic rst,

    input  logic start_allowed_bank0,
    input  logic start_allowed_bank1,
    input  logic write_bank_sel,
    input  logic [PW-1:0] input_buffer,

    output logic read_bank_sel,
    output logic clear_bank0,
    output logic clear_bank1,
    output logic [BEAT_W-1:0] buffer_raddr,

    input  logic                w_cfg_valid,
    input  logic [BANK_W-1:0]   w_cfg_bank,
    input  logic [W_addr-1:0]   w_cfg_addr,
    input  logic [PW-1:0]       w_cfg_data,

    input  logic                t_cfg_valid,
    input  logic [BANK_W-1:0]   t_cfg_bank,
    input  logic [TW_addr-1:0]  t_cfg_addr,
    input  logic [TW-1:0]       t_cfg_data,

    output logic [PN-1:0] out,
    output logic [PN-1:0][$clog2(TN+1)-1:0] pop_out,
    output logic [PN-1:0] valid_acc,
    output logic [PN-1:0] valid_out
);

  logic t_ram_b_ren;
  logic [W_addr-1:0]  w_ram_b_addr;
  logic [TW_addr-1:0] t_ram_b_addr;
  logic valid_in;
  logic last_in;

  logic [PN-1:0] np_out;
  logic [PN-1:0][$clog2(TN+1)-1:0] np_pop_out;
  logic [PN-1:0] np_valid_acc;
  logic [PN-1:0] np_valid_out;

  Layer_Control_WithThreshold #(
    .LAYER_ID  (LAYER_ID),
    .PN        (PN),
    .PW        (PW),
    .TN        (TN),
    .N_NEURONS (N_NEURONS),
    .TW        (TW)
  ) u_ctrl (
    .clk                 (clk),
    .rst                 (rst),
    .start_allowed_bank0 (start_allowed_bank0),
    .start_allowed_bank1 (start_allowed_bank1),
    .write_bank_sel      (write_bank_sel),
    .read_bank_sel       (read_bank_sel),
    .clear_bank0         (clear_bank0),
    .clear_bank1         (clear_bank1),
    .buffer_raddr        (buffer_raddr),
    .t_ram_b_ren         (t_ram_b_ren),
    .w_ram_b_addr        (w_ram_b_addr),
    .t_ram_b_addr        (t_ram_b_addr),
    .valid_in            (valid_in),
    .last_in             (last_in)
  );

  NP_Layer_WithThreshold #(
    .LAYER_ID (LAYER_ID),
    .PN       (PN),
    .PW       (PW),
    .TN       (TN),
    .N        (N_NEURONS),
    .TW       (TW),
    .LAT      (LAT)
  ) u_np_layer (
    .clk          (clk),
    .rst          (rst),
    .input_buffer (input_buffer),

    .w_cfg_valid  (w_cfg_valid),
    .w_cfg_bank   (w_cfg_bank),
    .w_cfg_addr   (w_cfg_addr),
    .w_cfg_data   (w_cfg_data),
    .t_cfg_valid  (t_cfg_valid),
    .t_cfg_bank   (t_cfg_bank),
    .t_cfg_addr   (t_cfg_addr),
    .t_cfg_data   (t_cfg_data),
    .w_ram_b_addr (w_ram_b_addr),
    .t_ram_b_addr (t_ram_b_addr),
    .valid_in     (valid_in),
    .last_in      (last_in),
    .t_ram_ren_b  (t_ram_b_ren),
    .out          (np_out),
    .pop_out      (np_pop_out),
    .valid_acc    (np_valid_acc),
    .valid_out    (np_valid_out)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      valid_out <= '0;
    end else begin
      out       <= np_out;
      pop_out   <= np_pop_out;
      valid_acc <= np_valid_acc;
      valid_out <= np_valid_out;
    end
  end

endmodule
