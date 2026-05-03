`timescale 1ns/1ps

module bnn_fcc #(
    parameter int INPUT_DATA_WIDTH  = 8,
    parameter int INPUT_BUS_WIDTH   = 64,
    parameter int CONFIG_BUS_WIDTH  = 64,
    parameter int OUTPUT_DATA_WIDTH = 4,
    parameter int OUTPUT_BUS_WIDTH  = 8,
    parameter int TOTAL_LAYERS = 4,
    parameter logic [TOTAL_LAYERS*32-1:0] TOPOLOGY_PACKED = 'h0000000A000001000000010000000310,
    parameter int PARALLEL_INPUTS = 8,
    parameter logic [(TOTAL_LAYERS-1)*32-1:0] PARALLEL_NEURONS_PACKED = 'h0000000A0000002000000020,
    parameter logic [(TOTAL_LAYERS-1)*32-1:0] LAYER_PARALLEL_INPUTS_PACKED = 'h000000200000002000000040,
    parameter int THRESHOLD_WIDTH = 32,
    parameter logic [(TOTAL_LAYERS-1)*32-1:0] LAYER_LATENCY_PACKED = 'h0000000E0000000E0000000E
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
    typedef int topology_t [0:TOTAL_LAYERS-1];
    typedef int layer_param_t [0:LAYERS-1];

    function automatic topology_t unpack_topology(input logic [TOTAL_LAYERS*32-1:0] packed_words);
        topology_t unpacked;

        for (int idx = 0; idx < TOTAL_LAYERS; idx++) begin
            unpacked[idx] = int'(packed_words[idx*32 +: 32]);
        end

        return unpacked;
    endfunction

    function automatic layer_param_t unpack_layer_params(input logic [LAYERS*32-1:0] packed_words);
        layer_param_t unpacked;

        for (int idx = 0; idx < LAYERS; idx++) begin
            unpacked[idx] = int'(packed_words[idx*32 +: 32]);
        end

        return unpacked;
    endfunction

    localparam topology_t TOPOLOGY = unpack_topology(TOPOLOGY_PACKED);
    localparam layer_param_t PARALLEL_NEURONS = unpack_layer_params(PARALLEL_NEURONS_PACKED);
    localparam layer_param_t LAYER_PARALLEL_INPUTS = unpack_layer_params(LAYER_PARALLEL_INPUTS_PACKED);
    localparam layer_param_t LAYER_LATENCY = unpack_layer_params(LAYER_LATENCY_PACKED);

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
