`timescale 1ns/1ps

module bnn_fcc #(
    parameter int INPUT_DATA_WIDTH  = 8,
    parameter int INPUT_BUS_WIDTH   = 64,
    parameter int CONFIG_BUS_WIDTH  = 32,
    parameter int OUTPUT_DATA_WIDTH = 4,
    parameter int OUTPUT_BUS_WIDTH  = 8,
    parameter int TOTAL_LAYERS = 4,
    parameter int TOPOLOGY[0:TOTAL_LAYERS-1] = '{0:784, 1:256, 2:256, 3:10, default:0},
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[0:TOTAL_LAYERS-2] = '{0:32, 1:256, 2:10, default:8},
    parameter int LAYER_PARALLEL_INPUTS[0:TOTAL_LAYERS-2] = '{0:784, 1:32, 2:256, default:8},
    parameter int THRESHOLD_WIDTH = 32,
    parameter int LAYER_LATENCY[0:TOTAL_LAYERS-2] = '{default:14}
)(
    input  logic clk,
    input  logic rst,

    input  logic                          config_valid,
    output logic                          config_ready,
    input  logic [CONFIG_BUS_WIDTH-1:0]   config_data,
    input  logic [CONFIG_BUS_WIDTH/8-1:0] config_keep,
    input  logic                          config_last,

    input  logic                          data_in_valid,
    output logic                          data_in_ready,
    input  logic [INPUT_BUS_WIDTH-1:0]    data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0]  data_in_keep,
    input  logic                          data_in_last,

    output logic                          data_out_valid,
    input  logic                          data_out_ready,
    output logic [OUTPUT_BUS_WIDTH-1:0]   data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0] data_out_keep,
    output logic                          data_out_last
);

    localparam int LAYERS = TOTAL_LAYERS - 1;
    localparam int LAYER_W = (LAYERS <= 1) ? 1 : $clog2(LAYERS);
    localparam int FINAL_LAYER_TN = TOPOLOGY[LAYERS-1];
    localparam int FINAL_POP_W = $clog2(FINAL_LAYER_TN + 1);

    logic [LAYER_PARALLEL_INPUTS[0]-1:0] first_layer_bits;
    logic                                first_layer_write;

    logic                    msg_valid;
    logic [LAYER_W-1:0]      msg_layer;
    logic              msg_type;
  

    logic                    payload_valid;
    logic                    payload_ready;
    logic [7:0]              payload_data;

    logic                    all_cfg_done;

    logic [LAYERS-1:0]       cfg_done_arr;
    logic                    h0_input_buffer_stall;
    logic [LAYERS-1:0]       write_bank_sel_arr;

    logic [PARALLEL_NEURONS[LAYERS-1]-1:0][FINAL_POP_W-1:0] final_pop_out;
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0]                  final_valid_acc;

    logic bnn_count_valid;

    logic [OUTPUT_BUS_WIDTH-1:0] argmax_data;
    logic                        argmax_valid;
    logic [31:0]                 argmax_valid_count;

    logic fifo_full;
    logic fifo_empty;
  
    Config_Manager #(
        .BUS_WIDTH (CONFIG_BUS_WIDTH),
        .LAYERS    (LAYERS)
    ) u_config_manager (
        .clk              (clk),
        .rst              (rst),

        .config_data_in   (config_data),
        .config_valid     (config_valid),
        .config_keep      (config_keep),
        .config_last      (config_last),
        .config_ready     (config_ready),

        .msg_valid        (msg_valid),

        .msg_layer        (msg_layer),
        .msg_type         (msg_type),
        

        .payload_valid    (payload_valid),
        .payload_ready    (payload_ready),
        .payload_data     (payload_data)
    );

    assign all_cfg_done = &cfg_done_arr;

    Input_Layer_Unit #(
        .INPUT_DATA_WIDTH      (INPUT_DATA_WIDTH),
        .INPUT_BUS_WIDTH       (INPUT_BUS_WIDTH),
        .FIRST_LAYER_IB_WIDTH  (LAYER_PARALLEL_INPUTS[0]),
        .FIFO_DEPTH            (2)
    ) u_input_layer_unit (
        .clk                   (clk),
        .rst                   (rst),

        .data_in_valid         (data_in_valid),
        .data_in_ready         (data_in_ready),
        .data_in_data          (data_in_data),
        .data_in_keep          (data_in_keep),
        .data_in_last          (data_in_last),
        .h0_input_buffer_stall (h0_input_buffer_stall),
        .first_layer_write     (first_layer_write),
        .first_layer_bits      (first_layer_bits),
        .fifo_full             (fifo_full),
        .fifo_empty            (fifo_empty)
    );

    BNN_Hidden #(
        .TOTAL_LAYERS         (TOTAL_LAYERS),
        .TOPOLOGY             (TOPOLOGY),
        .FIRST_LAYER_IB_WIDTH (LAYER_PARALLEL_INPUTS[0]),
        .PARALLEL_INPUTS      (LAYER_PARALLEL_INPUTS),
        .PARALLEL_NEURONS     (PARALLEL_NEURONS),
        .THRESHOLD_WIDTH      (THRESHOLD_WIDTH),
        .LAYER_LATENCY        (LAYER_LATENCY)
    ) u_bnn_hidden (
        .clk                   (clk),
        .rst                   (rst),

        .msg_valid             (msg_valid),
        .msg_layer             (msg_layer),
        .msg_type              (msg_type),
        .payload_valid         (payload_valid),
        .payload_ready         (payload_ready),
        .payload_data          (payload_data),
        .first_layer_istream   (first_layer_bits),
        .first_layer_write     (first_layer_write),
        .cfg_done_arr          (cfg_done_arr),
        .h0_input_buffer_stall (h0_input_buffer_stall),
        .write_bank_sel_arr    (write_bank_sel_arr),
        .final_valid_acc       (final_valid_acc),
        .final_pop_out         (final_pop_out)
    );

    assign bnn_count_valid = |final_valid_acc;

    Arg_MAX #(
        .act_w      (PARALLEL_NEURONS[LAYERS-1]),
        .popcount_w (FINAL_POP_W),
        .out_w      (OUTPUT_BUS_WIDTH)
    ) u_argmax (
        .clk       (clk),
        .rst       (rst),
        .en        (bnn_count_valid),
        .popcount  (final_pop_out),
        .bcc_out   (argmax_data),
        .out_valid (argmax_valid)
    );

    bnn_output_fifo u_output_fifo (
        .clk      (clk),
        .rst      (rst),
        .wr_valid (argmax_valid),
        .wr_data  (argmax_data),
        .rd_ready (data_out_ready),
        .rd_valid (data_out_valid),
        .rd_data  (data_out_data)
    );

    assign data_out_keep = '1;
    assign data_out_last = data_out_valid;

endmodule
