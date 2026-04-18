`timescale 1ns/1ps

module BNN_Hidden #(
    parameter int TOTAL_LAYERS = 4,
    localparam int LAYERS = TOTAL_LAYERS - 1,
    parameter int TOPOLOGY[0:TOTAL_LAYERS-1] = '{0:784, 1:256, 2:256, 3:10, default:0},
    parameter int FIRST_LAYER_IB_WIDTH = 8,
    parameter int PARALLEL_INPUTS[0:LAYERS-1]  = '{default:8},
    parameter int PARALLEL_NEURONS[0:LAYERS-1] = '{default:8},
    parameter int THRESHOLD_WIDTH = 32,
    parameter int LAYER_LATENCY[0:LAYERS-1] = '{default:4},
    localparam int LAYER_W = (LAYERS <= 1) ? 1 : $clog2(LAYERS)
)(
    input  logic clk,
    input  logic rst,

    input  logic               msg_valid,
  
    input  logic [LAYER_W-1:0] msg_layer,
    input  logic          msg_type,


    input  logic               payload_valid,
    output logic               payload_ready,
    input  logic [7:0]         payload_data,

    input  logic [FIRST_LAYER_IB_WIDTH-1:0] first_layer_istream,
    input  logic                            first_layer_write,

    output logic [LAYERS-1:0] cfg_done_arr,

    output logic              h0_input_buffer_stall,
    output logic [LAYERS-1:0] write_bank_sel_arr,

    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0]                                      final_valid_acc,
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0][$clog2(TOPOLOGY[LAYERS-1] + 1)-1:0] final_pop_out
);


    logic [LAYERS-1:0] payload_ready_vec;

    assign payload_ready = |payload_ready_vec;

    genvar g;
    generate
        for (g = 0; g < LAYERS; g++) begin : GEN_LAYERS

            if (g == 0) begin : GEN_H0

                localparam int CUR_IB_WIDTH = FIRST_LAYER_IB_WIDTH;

                localparam int CUR_TN = TOPOLOGY[0];

                logic [CUR_IB_WIDTH-1:0] istream_local;
                logic                    write_local;

                logic [PARALLEL_NEURONS[g]-1:0] out_local;
                logic [PARALLEL_NEURONS[g]-1:0] valid_acc_local;
                logic [PARALLEL_NEURONS[g]-1:0] valid_out_local;

                assign istream_local = first_layer_istream;
                assign write_local   = first_layer_write;

                if (g == LAYERS-1) begin : GEN_H0_FINAL

                    logic [PARALLEL_NEURONS[g]-1:0][$clog2(CUR_TN + 1)-1:0] pop_local;

                    BNN_OutputLayer_PopcountOnly #(
                        .LAYER_ID  (g),
                        .LAYER_W   (LAYER_W),
                        .IB_WIDTH  (CUR_IB_WIDTH),
                        .PW        (PARALLEL_INPUTS[g]),
                        .PN        (PARALLEL_NEURONS[g]),
                        .TN        (CUR_TN),
                        .N_NEURONS (TOPOLOGY[g+1]),
                        .LAT       (LAYER_LATENCY[g])
                    ) u_bnn_layer (
                        .clk                (clk),
                        .rst                (rst),

                        .msg_valid          (msg_valid),
                        .msg_layer          (msg_layer),
                        .msg_type           (msg_type),
                        .payload_valid      (payload_valid),
                        .payload_ready      (payload_ready_vec[g]),
                        .payload_data       (payload_data),
                        .buffer_write       (write_local),
                        .istream            (istream_local),
                        .pop_out            (pop_local),
                        .valid_acc          (valid_acc_local),
                        .cfg_done           (cfg_done_arr[g]),
                        .write_bank_sel_out (write_bank_sel_arr[g])
                    );

                    assign h0_input_buffer_stall = 1'b0;
                    assign final_valid_acc       = valid_acc_local;
                    assign final_pop_out         = pop_local;

                end else begin : GEN_H0_NONFINAL

                    BNN_Layer_StallableInput #(
                        .LAYER_ID  (g),
                        .LAYER_W   (LAYER_W),
                        .IB_WIDTH  (CUR_IB_WIDTH),
                        .PW        (PARALLEL_INPUTS[g]),
                        .PN        (PARALLEL_NEURONS[g]),
                        .TN        (CUR_TN),
                        .N_NEURONS (TOPOLOGY[g+1]),
                        .TW        (THRESHOLD_WIDTH),
                        .LAT       (LAYER_LATENCY[g])
                    ) u_bnn_layer (
                        .clk                (clk),
                        .rst                (rst),

                        .msg_valid          (msg_valid),                       
                        .msg_layer          (msg_layer),
                        .msg_type           (msg_type),                 
                        .payload_valid      (payload_valid),
                        .payload_ready      (payload_ready_vec[g]),
                        .payload_data       (payload_data),
                        .buffer_write       (write_local),
                        .istream            (istream_local),
                        .out                (out_local),
                        .pop_out            (),
                        .valid_acc          (valid_acc_local),
                        .valid_out          (valid_out_local),
                        .cfg_done           (cfg_done_arr[g]),
                        .input_buffer_stall (h0_input_buffer_stall),
                        .write_bank_sel_out (write_bank_sel_arr[g])
                    );

                end

            end else begin : GEN_HN

                localparam int CUR_IB_WIDTH = PARALLEL_NEURONS[g-1];

                localparam int CUR_TN = TOPOLOGY[g];

                logic [CUR_IB_WIDTH-1:0] istream_local;
                logic                    write_local;

                logic [PARALLEL_NEURONS[g]-1:0] out_local;
                logic [PARALLEL_NEURONS[g]-1:0] valid_acc_local;
                logic [PARALLEL_NEURONS[g]-1:0] valid_out_local;

                if (g == 1) begin : GEN_FROM_H0
                    assign istream_local = GEN_LAYERS[g-1].GEN_H0.out_local;
                    assign write_local   = |GEN_LAYERS[g-1].GEN_H0.valid_out_local;
                end else begin : GEN_FROM_HN
                    assign istream_local = GEN_LAYERS[g-1].GEN_HN.out_local;
                    assign write_local   = |GEN_LAYERS[g-1].GEN_HN.valid_out_local;
                end

                if (g == LAYERS-1) begin : GEN_HN_FINAL

                    logic [PARALLEL_NEURONS[g]-1:0][$clog2(CUR_TN + 1)-1:0] pop_local;

                    BNN_OutputLayer_PopcountOnly #(
                        .LAYER_ID  (g),
                        .LAYER_W   (LAYER_W),
                        .IB_WIDTH  (CUR_IB_WIDTH),
                        .PW        (PARALLEL_INPUTS[g]),
                        .PN        (PARALLEL_NEURONS[g]),
                        .TN        (CUR_TN),
                        .N_NEURONS (TOPOLOGY[g+1]),
                        .LAT       (LAYER_LATENCY[g])
                    ) u_bnn_layer (
                        .clk                (clk),
                        .rst                (rst),

                        .msg_valid          (msg_valid),                     
                        .msg_layer          (msg_layer),
                        .msg_type           (msg_type),                  
                        .payload_valid      (payload_valid),
                        .payload_ready      (payload_ready_vec[g]),
                        .payload_data       (payload_data),
                        .buffer_write       (write_local),
                        .istream            (istream_local),
                        .pop_out            (pop_local),
                        .valid_acc          (valid_acc_local),
                        .cfg_done           (cfg_done_arr[g]),
                        .write_bank_sel_out (write_bank_sel_arr[g])
                    );

                    assign final_valid_acc = valid_acc_local;
                    assign final_pop_out   = pop_local;

                end else begin : GEN_HN_NONFINAL

                    BNN_Layer_NoStallInput #(
                        .LAYER_ID  (g),
                        .LAYER_W   (LAYER_W),
                        .IB_WIDTH  (CUR_IB_WIDTH),
                        .PW        (PARALLEL_INPUTS[g]),
                        .PN        (PARALLEL_NEURONS[g]),
                        .TN        (CUR_TN),
                        .N_NEURONS (TOPOLOGY[g+1]),
                        .TW        (THRESHOLD_WIDTH),
                        .LAT       (LAYER_LATENCY[g])
                    ) u_bnn_layer (
                        .clk                (clk),
                        .rst                (rst),

                        .msg_valid          (msg_valid),                       
                        .msg_layer          (msg_layer),
                        .msg_type           (msg_type),                
                        .payload_valid      (payload_valid),
                        .payload_ready      (payload_ready_vec[g]),
                        .payload_data       (payload_data),
                        .buffer_write       (write_local),
                        .istream            (istream_local),
                        .out                (out_local),
                        .pop_out            (),
                        .valid_acc          (valid_acc_local),
                        .valid_out          (valid_out_local),
                        .cfg_done           (cfg_done_arr[g]),
                        .write_bank_sel_out (write_bank_sel_arr[g])
                    );

                end

            end

        end
    endgenerate

endmodule
