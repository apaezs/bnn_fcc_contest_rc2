`timescale 1ns/1ps

module BNN_Layer_NoStallInput #(
    parameter int LAYER_ID  = 0,
    parameter int LAYER_W   = 1,
    parameter int IB_WIDTH  = 8,
    parameter int PW        = 8,
    parameter int PN        = 8,
    parameter int TN        = 16,
    parameter int N_NEURONS = 16,
    parameter int TW        = 32,
    parameter int LAT       = 4,
    localparam int BEATS     = (TN + PW - 1) / PW,
    localparam int GROUPS    = (N_NEURONS + PN - 1) / PN,
    localparam int W_ADDR_W  = (GROUPS * BEATS <= 1) ? 1 : $clog2(GROUPS * BEATS),
    localparam int TW_ADDR_W = (GROUPS <= 1) ? 1 : $clog2(GROUPS),
    localparam int IB_ADDR_W = (BEATS <= 1) ? 1 : $clog2(BEATS),
    localparam int BANK_W    = (PN <= 1) ? 1 : $clog2(PN)
)(
    input  logic clk,
    input  logic rst,

    input  logic               msg_valid,
    input  logic [LAYER_W-1:0] msg_layer,
    input  logic          msg_type,
    
    input  logic               payload_valid,
    output logic               payload_ready,
    input  logic [7:0]         payload_data,

    input  logic                buffer_write,
    input  logic [IB_WIDTH-1:0] istream,

    output logic [PN-1:0] out,
    output logic [PN-1:0][$clog2(TN+1)-1:0] pop_out,
    output logic [PN-1:0] valid_acc,
    output logic [PN-1:0] valid_out,

    output logic cfg_done,
    output logic write_bank_sel_out
);

    logic                 clear_bank0;
    logic                 clear_bank1;
    logic                 read_bank_sel;
    logic [IB_ADDR_W-1:0] buffer_raddr;

    logic                 start_allowed_bank0;
    logic                 start_allowed_bank1;
    logic [PW-1:0]        input_buffer_out;

    logic                 w_cfg_valid;
    logic [BANK_W-1:0]    w_cfg_bank;
    logic [W_ADDR_W-1:0]  w_cfg_addr;
    logic [PW-1:0]        w_cfg_data;

    logic                 t_cfg_valid;
    logic [BANK_W-1:0]    t_cfg_bank;
    logic [TW_ADDR_W-1:0] t_cfg_addr;
    logic [TW-1:0]        t_cfg_data;

    Config_HiddenLayer_Control #(
        .LAYER_ID  (LAYER_ID),
        .LAYER_W   (LAYER_W),
        .PN        (PN),
        .PW        (PW),
        .TN        (TN),
        .N_NEURONS (N_NEURONS),
        .TW        (TW)
    ) u_cfg_ctrl (
        .clk              (clk),
        .rst              (rst),

        .msg_valid        (msg_valid),
        .msg_layer        (msg_layer),
        .msg_type         (msg_type),
        .payload_valid    (payload_valid),
        .payload_ready    (payload_ready),
        .payload_data     (payload_data),
        .w_cfg_valid      (w_cfg_valid),
        .w_cfg_bank       (w_cfg_bank),
        .w_cfg_addr       (w_cfg_addr),
        .w_cfg_data       (w_cfg_data),
        .t_cfg_valid      (t_cfg_valid),
        .t_cfg_bank       (t_cfg_bank),
        .t_cfg_addr       (t_cfg_addr),
        .t_cfg_data       (t_cfg_data),
        .cfg_done         (cfg_done)
    );

    Input_Buffer_NoStall #(
        .LAYER_ID (LAYER_ID),
        .IB_WIDTH (IB_WIDTH),
        .PW       (PW),
        .TN       (TN)
    ) u_input_buffer (
        .clk                 (clk),
        .rst                 (rst),

        .buffer_write        (buffer_write),
        .raddr               (buffer_raddr),
        .read_bank_sel       (read_bank_sel),
        .clear_bank0         (clear_bank0),
        .clear_bank1         (clear_bank1),
        .istream             (istream),
        .ostream             (input_buffer_out),
        .start_allowed_bank0 (start_allowed_bank0),
        .start_allowed_bank1 (start_allowed_bank1),
        .write_bank_sel_out  (write_bank_sel_out)
    );

    Layer_WithThreshold #(
        .LAYER_ID  (LAYER_ID),
        .PN        (PN),
        .PW        (PW),
        .TN        (TN),
        .N_NEURONS (N_NEURONS),
        .TW        (TW),
        .LAT       (LAT)
    ) u_layer (
        .clk                 (clk),
        .rst                 (rst),

        .start_allowed_bank0 (start_allowed_bank0),
        .start_allowed_bank1 (start_allowed_bank1),
        .write_bank_sel      (write_bank_sel_out),
        .read_bank_sel       (read_bank_sel),
        .clear_bank0         (clear_bank0),
        .clear_bank1         (clear_bank1),
        .buffer_raddr        (buffer_raddr),
        .input_buffer        (input_buffer_out),
        .w_cfg_valid         (w_cfg_valid),
        .w_cfg_bank          (w_cfg_bank),
        .w_cfg_addr          (w_cfg_addr),
        .w_cfg_data          (w_cfg_data),
        .t_cfg_valid         (t_cfg_valid),
        .t_cfg_bank          (t_cfg_bank),
        .t_cfg_addr          (t_cfg_addr),
        .t_cfg_data          (t_cfg_data),
        .out                 (out),
        .pop_out             (pop_out),
        .valid_acc           (valid_acc),
        .valid_out           (valid_out)
    );

endmodule
