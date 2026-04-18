`timescale 1ns/1ps

module Input_Layer_Unit #(
    parameter int INPUT_DATA_WIDTH       = 8,
    parameter int INPUT_BUS_WIDTH        = 64,
    parameter int FIRST_LAYER_IB_WIDTH   = 32,
    parameter int FIFO_DEPTH             = 256,
    localparam int INPUT_BUS_KEEP_W      = INPUT_BUS_WIDTH / 8,
    localparam int BIN_W                 = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH,
    localparam logic [INPUT_DATA_WIDTH-1:0] THRESH = (1 << (INPUT_DATA_WIDTH - 1))
)(
    input  logic                              clk,
    input  logic                              rst,

    input  logic                              data_in_valid,
    output logic                              data_in_ready,
    input  logic [INPUT_BUS_WIDTH-1:0]        data_in_data,
    input  logic [INPUT_BUS_KEEP_W-1:0]       data_in_keep,
    input  logic                              data_in_last,
    input  logic                              h0_input_buffer_stall,

    output logic                              first_layer_write,
    output logic [FIRST_LAYER_IB_WIDTH-1:0]   first_layer_bits,

    output logic                              fifo_full,
    output logic                              fifo_empty
);

    logic                              skid_valid;
    logic                              skid_ready;
    logic [INPUT_BUS_WIDTH-1:0]        skid_data;
    logic [INPUT_BUS_KEEP_W-1:0]       skid_keep;
    logic                              skid_last;

    logic                              input_layer_valid;
    logic                              input_layer_last;
    logic [BIN_W-1:0]                  input_layer_bits;
    logic [INPUT_BUS_WIDTH-1:0]        masked_input_data;
    logic                              consume_skid;

    logic                              fifo_wr_en;
    logic                              fifo_wr_last;
    logic [BIN_W-1:0]                  fifo_wr_data;
    logic                              fifo_almost_full;
    logic                              fifo_rd_en;
    logic                              fifo_rd_valid;
    logic [FIRST_LAYER_IB_WIDTH-1:0]   fifo_rd_data;

    integer i;

    always_comb begin
        masked_input_data = '0;
        for (i = 0; i < INPUT_BUS_KEEP_W; i++) begin
            if (skid_keep[i]) begin
                masked_input_data[i*8 +: 8] = skid_data[i*8 +: 8];
            end
        end
    end

    assign skid_ready   =  !h0_input_buffer_stall;
    assign consume_skid = skid_valid && skid_ready;

    assign fifo_wr_en   = input_layer_valid;
    assign fifo_wr_last = input_layer_last;
    assign fifo_wr_data = input_layer_bits;

    assign fifo_rd_en        = !fifo_empty && !h0_input_buffer_stall;
    assign first_layer_write = fifo_rd_valid;
    assign first_layer_bits  = fifo_rd_data;

    Skid_Buffer #(
        .DATA_W(INPUT_BUS_WIDTH),
        .KEEP_W(INPUT_BUS_KEEP_W)
    ) u_skid_buffer (
        .clk    (clk),
        .rst    (rst),

        .s_valid(data_in_valid),
        .s_ready(data_in_ready),
        .s_data (data_in_data),
        .s_keep (data_in_keep),
        .s_last (data_in_last),
        .m_valid(skid_valid),
        .m_ready(skid_ready),
        .m_data (skid_data),
        .m_keep (skid_keep),
        .m_last (skid_last)
    );

    Input_Layer #(
        .out_w (BIN_W),
        .in_w  (INPUT_BUS_WIDTH),
        .THRESH(THRESH)
    ) u_input_layer (
        .clk     (clk),
        .rst     (rst),
        .en      (consume_skid),
        .last_in (skid_last),
        .istream (masked_input_data),
        .valid   (input_layer_valid),
        .last_out(input_layer_last),
        .ostream (input_layer_bits)
    );

    FIFO #(
        .W_WIDTH (BIN_W),
        .R_WIDTH (FIRST_LAYER_IB_WIDTH),
        .DEPTH   (FIFO_DEPTH)
    ) u_input_fifo (
        .clk         (clk),
        .rst         (rst),

        .wr_en       (fifo_wr_en),
        .wr_last     (fifo_wr_last),
        .wr_data     (fifo_wr_data),
        .full        (fifo_full),
        .almost_full (fifo_almost_full),
        .rd_en       (fifo_rd_en),
        .rd_valid    (fifo_rd_valid),
        .rd_data     (fifo_rd_data),
        .empty       (fifo_empty)
    );

endmodule
