`include "uvm_macros.svh"

package bnn_fcc_uvm_pkg;
    import uvm_pkg::*;
    import axi4_stream_pkg::*;
    import bnn_fcc_tb_pkg::*;

    localparam int CONFIG_BUS_WIDTH = 64;
    localparam int INPUT_BUS_WIDTH  = 64;
    localparam int OUTPUT_BUS_WIDTH = 8;
    localparam int INPUT_DATA_WIDTH = 8;
    localparam int OUTPUT_DATA_WIDTH = 4;
    localparam int INPUTS_PER_CYCLE = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH;
    localparam int BYTES_PER_INPUT  = INPUT_DATA_WIDTH / 8;

    typedef bit [CONFIG_BUS_WIDTH-1:0]   config_word_t;
    typedef bit [CONFIG_BUS_WIDTH/8-1:0] config_keep_t;
    typedef bit [INPUT_BUS_WIDTH-1:0]    input_word_t;
    typedef bit [INPUT_BUS_WIDTH/8-1:0]  input_keep_t;
    typedef bit [INPUT_DATA_WIDTH-1:0]   pixel_t;

    typedef enum logic [1:0] {
        RST_IDLE,
        RST_DURING_CONFIG,
        RST_DURING_INPUT,
        RST_DURING_OUTPUT
    } reset_scenario_e;

    class bnn_fcc_uvm_cfg extends uvm_object;
        `uvm_object_utils(bnn_fcc_uvm_cfg)

        bit       use_custom_topology;
        int       custom_layers;
        int       num_test_images;
        bit       verify_model;
        string    base_dir;
        bit       toggle_data_out_ready;
        real      config_valid_probability;
        real      data_in_valid_probability;
        realtime  timeout;
        bit       debug;
        bit       print_through_images;
        int       reset_every_n_images;
        bit       alt_j_gap_len;
        bit       force_short_gap_before_last;
        bit       force_long_gap_before_last;
        bit       force_large_config_gap;
        bit       force_large_config_stall;
        bit       threshold_first_msg_directed_test;
        bit       force_bp_duration_coverage;
        bit       allow_bp_greater_than_100;
        bit       alt_config_ordering;

        int       actual_topology[$];
        int       parallel_inputs;
        int       layer_parallel_inputs[$];
        int       parallel_neurons[$];

        string    mnist_input_path;
        string    mnist_output_path;
        string    mnist_model_data_path;

        int       num_tests;
        int       total_tests;

        int       class_example_idx[10];
        bit       class_example_valid[10];
        pixel_t   class_cov_img[10][];
        bit       class_cov_valid[10];

        BNN_FCC_Model#(CONFIG_BUS_WIDTH)         model;
        BNN_FCC_Stimulus#(INPUT_DATA_WIDTH)      stim;
        config_word_t                            config_bus_data_stream[];
        config_keep_t                            config_bus_keep_stream[];
        bit                                      config_bus_tlast_stream[];

        function new(string name = "bnn_fcc_uvm_cfg");
            super.new(name);
            use_custom_topology               = 1'b0;
            custom_layers                     = 4;
            num_test_images                   = 50;
            verify_model                      = 1'b1;
            base_dir                          = "../../python";
            toggle_data_out_ready             = 1'b1;
            config_valid_probability          = 0.8;
            data_in_valid_probability         = 0.8;
            timeout                           = 200ms;
            debug                             = 1'b0;
            print_through_images              = 1'b0;
            reset_every_n_images              = 10;
            alt_j_gap_len                     = 1'b1;
            force_short_gap_before_last       = 1'b1;
            force_long_gap_before_last        = 1'b1;
            force_large_config_gap            = 1'b1;
            force_large_config_stall          = 1'b1;
            threshold_first_msg_directed_test = 1'b1;
            force_bp_duration_coverage        = 1'b1;
            allow_bp_greater_than_100         = 1'b1;
            alt_config_ordering               = 1'b1;
            mnist_input_path                  = "test_vectors/inputs.hex";
            mnist_output_path                 = "test_vectors/expected_outputs.txt";
            mnist_model_data_path             = "model_data";
            foreach (class_example_idx[i]) begin
                class_example_idx[i]   = -1;
                class_example_valid[i] = 1'b0;
                class_cov_valid[i]     = 1'b0;
            end
        endfunction

        function int actual_total_layers();
            return actual_topology.size();
        endfunction

        function int directed_input_tests();
            int count;
            count = 0;
            if (alt_j_gap_len)               count += 2;
            if (force_short_gap_before_last) count += 1;
            if (force_long_gap_before_last)  count += 1;
            return count;
        endfunction

        function int directed_tests();
            return directed_input_tests();
        endfunction
    endclass

    `include "bnn_fcc_sequences.svh"
    `include "bnn_fcc_ready_ctrl.svh"
    `include "bnn_fcc_scoreboard.svh"
    `include "bnn_fcc_coverage.svh"
    `include "bnn_fcc_env.svh"
    `include "bnn_fcc_base_test.svh"
    `include "bnn_fcc_coverage_test.svh"

endpackage
