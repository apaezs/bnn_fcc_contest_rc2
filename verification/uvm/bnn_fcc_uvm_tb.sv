`include "uvm_macros.svh"
import uvm_pkg::*;
import axi4_stream_pkg::*;
import bnn_fcc_uvm_pkg::*;

`timescale 1ns / 1ps

module bnn_fcc_uvm_tb #(
    parameter int      USE_CUSTOM_TOPOLOGY                      = 1'b0,
    parameter int      CUSTOM_LAYERS                            = 4,
    parameter int      CUSTOM_TOPOLOGY          [CUSTOM_LAYERS] = '{8, 8, 8, 8},
    parameter int      NUM_TEST_IMAGES                          = 50,
    parameter bit      VERIFY_MODEL                             = 1,
    parameter string   BASE_DIR                                 = "../../python",
    parameter bit      TOGGLE_DATA_OUT_READY                    = 1'b1,
    parameter real     CONFIG_VALID_PROBABILITY                 = 0.8,
    parameter real     DATA_IN_VALID_PROBABILITY                = 0.8,
    parameter realtime TIMEOUT                                  = 200ms,
    parameter realtime CLK_PERIOD                               = 10ns,
    parameter bit      DEBUG                                    = 1'b0,
    parameter bit      PRINT_THROUGH_IMAGES                     = 1'b0,
    parameter int      RESET_EVERY_N_IMAGES                     = 10,
    parameter bit      ALT_J_GAP_LEN                            = 1'b1,
    parameter bit      FORCE_SHORT_GAP_BEFORE_LAST              = 1'b1,
    parameter bit      FORCE_LONG_GAP_BEFORE_LAST               = 1'b1,
    parameter bit      FORCE_LARGE_CONFIG_GAP                   = 1'b1,
    parameter bit      FORCE_LARGE_CONFIG_STALL                 = 1'b1,
    parameter bit      THRESHOLD_FIRST_MSG_DIRECTED_TEST        = 1'b1,
    parameter bit      FORCE_BP_DURATION_COVERAGE               = 1'b1,
    parameter bit      ALLOW_BP_GREATER_THAN_100                = 1'b1,
    parameter bit      ALT_CONFIG_ORDERING                      = 1'b1,
    parameter int      INPUT_DATA_WIDTH_TB                      = 8,
    parameter int      INPUT_BUS_WIDTH_TB                       = 64,
    parameter int      CONFIG_BUS_WIDTH_TB                      = 64,
    parameter int      OUTPUT_DATA_WIDTH_TB                     = 4,
    parameter int      OUTPUT_BUS_WIDTH_TB                      = 8,
    parameter int      TRAINED_LAYERS                           = 4,
    parameter int      TRAINED_TOPOLOGY [TRAINED_LAYERS]        = '{784, 256, 256, 10},
    parameter int      PARALLEL_INPUTS                          = 8,
    localparam int     NON_INPUT_LAYERS                         = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS - 1 : TRAINED_LAYERS - 1,
    parameter int      LAYER_PARALLEL_INPUTS[NON_INPUT_LAYERS]  = '{64, 32, 32},
    parameter int      PARALLEL_NEURONS[NON_INPUT_LAYERS]       = '{32, 32, 10}
);
    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS;
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] = USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY;

    bnn_fcc_uvm_cfg cfg;
    bnn_fcc_ctrl_if ctrl_if();

    axi4_stream_if #(CONFIG_BUS_WIDTH) config_in (
        ctrl_if.clk,
        !ctrl_if.rst
    );

    axi4_stream_if #(INPUT_BUS_WIDTH) data_in (
        ctrl_if.clk,
        !ctrl_if.rst
    );

    axi4_stream_if #(OUTPUT_BUS_WIDTH) data_out (
        ctrl_if.clk,
        !ctrl_if.rst
    );

    initial begin
        assert (INPUT_DATA_WIDTH_TB  == INPUT_DATA_WIDTH)
        else $fatal(1, "UVM TB expects INPUT_DATA_WIDTH=%0d", INPUT_DATA_WIDTH);
        assert (INPUT_BUS_WIDTH_TB   == INPUT_BUS_WIDTH)
        else $fatal(1, "UVM TB expects INPUT_BUS_WIDTH=%0d", INPUT_BUS_WIDTH);
        assert (CONFIG_BUS_WIDTH_TB  == CONFIG_BUS_WIDTH)
        else $fatal(1, "UVM TB expects CONFIG_BUS_WIDTH=%0d", CONFIG_BUS_WIDTH);
        assert (OUTPUT_DATA_WIDTH_TB == OUTPUT_DATA_WIDTH)
        else $fatal(1, "UVM TB expects OUTPUT_DATA_WIDTH=%0d", OUTPUT_DATA_WIDTH);
        assert (OUTPUT_BUS_WIDTH_TB  == OUTPUT_BUS_WIDTH)
        else $fatal(1, "UVM TB expects OUTPUT_BUS_WIDTH=%0d", OUTPUT_BUS_WIDTH);
    end

    initial begin
        ctrl_if.clk = 1'b0;
    end

    always #(CLK_PERIOD / 2.0) ctrl_if.clk <= ~ctrl_if.clk;

    bnn_fcc #(
        .INPUT_DATA_WIDTH      (INPUT_DATA_WIDTH_TB),
        .INPUT_BUS_WIDTH       (INPUT_BUS_WIDTH_TB),
        .CONFIG_BUS_WIDTH      (CONFIG_BUS_WIDTH_TB),
        .OUTPUT_DATA_WIDTH     (OUTPUT_DATA_WIDTH_TB),
        .OUTPUT_BUS_WIDTH      (OUTPUT_BUS_WIDTH_TB),
        .TOTAL_LAYERS          (ACTUAL_TOTAL_LAYERS),
        .TOPOLOGY              (ACTUAL_TOPOLOGY),
        .PARALLEL_INPUTS       (PARALLEL_INPUTS),
        .LAYER_PARALLEL_INPUTS (LAYER_PARALLEL_INPUTS),
        .PARALLEL_NEURONS      (PARALLEL_NEURONS)
    ) DUT (
        .clk            (ctrl_if.clk),
        .rst            (ctrl_if.rst),
        .config_valid   (config_in.tvalid),
        .config_ready   (config_in.tready),
        .config_data    (config_in.tdata),
        .config_keep    (config_in.tkeep),
        .config_last    (config_in.tlast),
        .data_in_valid  (data_in.tvalid),
        .data_in_ready  (data_in.tready),
        .data_in_data   (data_in.tdata),
        .data_in_keep   (data_in.tkeep),
        .data_in_last   (data_in.tlast),
        .data_out_valid (data_out.tvalid),
        .data_out_ready (data_out.tready),
        .data_out_data  (data_out.tdata),
        .data_out_keep  (data_out.tkeep),
        .data_out_last  (data_out.tlast)
    );

    assign config_in.tstrb = config_in.tkeep;
    assign data_in.tstrb   = data_in.tkeep;

    initial begin
        ctrl_if.rst = 1'b1;

        cfg = new("cfg");
        cfg.use_custom_topology               = USE_CUSTOM_TOPOLOGY;
        cfg.custom_layers                     = CUSTOM_LAYERS;
        cfg.num_test_images                   = NUM_TEST_IMAGES;
        cfg.verify_model                      = VERIFY_MODEL;
        cfg.base_dir                          = BASE_DIR;
        cfg.toggle_data_out_ready             = TOGGLE_DATA_OUT_READY;
        cfg.config_valid_probability          = CONFIG_VALID_PROBABILITY;
        cfg.data_in_valid_probability         = DATA_IN_VALID_PROBABILITY;
        cfg.timeout                           = TIMEOUT;
        cfg.debug                             = DEBUG;
        cfg.print_through_images              = PRINT_THROUGH_IMAGES;
        cfg.reset_every_n_images              = RESET_EVERY_N_IMAGES;
        cfg.alt_j_gap_len                     = ALT_J_GAP_LEN;
        cfg.force_short_gap_before_last       = FORCE_SHORT_GAP_BEFORE_LAST;
        cfg.force_long_gap_before_last        = FORCE_LONG_GAP_BEFORE_LAST;
        cfg.force_large_config_gap            = FORCE_LARGE_CONFIG_GAP;
        cfg.force_large_config_stall          = FORCE_LARGE_CONFIG_STALL;
        cfg.threshold_first_msg_directed_test = THRESHOLD_FIRST_MSG_DIRECTED_TEST;
        cfg.force_bp_duration_coverage        = FORCE_BP_DURATION_COVERAGE;
        cfg.allow_bp_greater_than_100         = ALLOW_BP_GREATER_THAN_100;
        cfg.alt_config_ordering               = ALT_CONFIG_ORDERING;
        cfg.parallel_inputs                   = PARALLEL_INPUTS;

        for (int i = 0; i < ACTUAL_TOTAL_LAYERS; i++) cfg.actual_topology.push_back(ACTUAL_TOPOLOGY[i]);
        for (int i = 0; i < NON_INPUT_LAYERS; i++) begin
            cfg.layer_parallel_inputs.push_back(LAYER_PARALLEL_INPUTS[i]);
            cfg.parallel_neurons.push_back(PARALLEL_NEURONS[i]);
        end

        uvm_config_db#(bnn_fcc_uvm_cfg)::set(uvm_root::get(), "*", "cfg", cfg);
        uvm_config_db#(virtual bnn_fcc_ctrl_if)::set(uvm_root::get(), "*", "ctrl_vif", ctrl_if);
        uvm_config_db#(virtual axi4_stream_if #(CONFIG_BUS_WIDTH))::set(uvm_root::get(), "*", "config_vif", config_in);
        uvm_config_db#(virtual axi4_stream_if #(INPUT_BUS_WIDTH))::set(uvm_root::get(), "*", "data_in_vif", data_in);
        uvm_config_db#(virtual axi4_stream_if #(OUTPUT_BUS_WIDTH))::set(uvm_root::get(), "*", "data_out_vif", data_out);
    end

    initial begin
        run_test();
    end

    assert property (@(posedge ctrl_if.clk) disable iff (ctrl_if.rst) !data_out.tready && data_out.tvalid |=> $stable(data_out.tdata))
    else `uvm_error("ASSERT", "Output changed with tready disabled.");

    assert property (@(posedge ctrl_if.clk) disable iff (ctrl_if.rst) !data_out.tready && data_out.tvalid |=> $stable(data_out.tvalid))
    else `uvm_error("ASSERT", "Valid changed with tready disabled.");

    initial begin
        #TIMEOUT;
        $fatal(1, $sformatf("Simulation failed due to timeout of %0t.", TIMEOUT));
    end
endmodule
