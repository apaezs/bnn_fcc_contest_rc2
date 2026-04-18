`timescale 1ns / 1ps

module bnn_fcc_coverage_tb #(
    parameter int      USE_CUSTOM_TOPOLOGY                      = 1'b0,
    parameter int      CUSTOM_LAYERS                            = 4,
    parameter int      CUSTOM_TOPOLOGY          [CUSTOM_LAYERS] = '{8, 8, 8, 8},
    parameter int      NUM_TEST_IMAGES                          = 50,
    parameter bit      VERIFY_MODEL                             = 1,
    parameter string   BASE_DIR                                 = "../python",
    parameter bit      TOGGLE_DATA_OUT_READY                    = 1'b1,
    parameter real     CONFIG_VALID_PROBABILITY                 = 0.8,
    parameter real     DATA_IN_VALID_PROBABILITY                = 0.8,
    parameter realtime TIMEOUT                                  = 200ms,
    parameter realtime CLK_PERIOD                               = 10ns,
    parameter bit      DEBUG                                    = 1'b0,
    parameter bit      PRINT_THROUGH_IMAGES                     = 1'b0,
    parameter int      RESET_EVERY_N_IMAGES                     = 0,     // 0 disables periodic resets else reset every N images
    parameter bit      ALT_J_GAP_LEN                            = 1'b1,  // force data_in gap bins to hit
    parameter bit      FORCE_SHORT_GAP_BEFORE_LAST              = 1'b1,  // force one short gap right before a final beat
    parameter bit      FORCE_LONG_GAP_BEFORE_LAST               = 1'b1,  // force one long gap right before a final beat
    parameter bit      FORCE_LARGE_CONFIG_GAP                   = 1'b1,
    parameter bit      FORCE_LARGE_CONFIG_STALL                 = 1'b1,  
    parameter bit      THRESHOLD_FIRST_MSG_DIRECTED_TEST        = 1'b1,  
    parameter bit      FORCE_BP_DURATION_COVERAGE               = 1'b1,  // run explicit output backpressure tests
    parameter bit      ALLOW_BP_GREATER_THAN_100                = 1'b1,  // bp from 101-1k
    parameter bit      ALT_CONFIG_ORDERING                      = 1'b1,  // swap between normal and weights-first ordering after resets

    // Bus widths
    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int INPUT_BUS_WIDTH  = 64,
    parameter int OUTPUT_BUS_WIDTH = 8,

    // Input and output data widths
    parameter  int INPUT_DATA_WIDTH  = 8,
    localparam int INPUTS_PER_CYCLE  = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH,
    localparam int BYTES_PER_INPUT   = INPUT_DATA_WIDTH / 8,
    parameter  int OUTPUT_DATA_WIDTH = 4,

    // Keep tied to the trained model files
    localparam int TRAINED_LAYERS = 4,
    localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10},

    // DUT parallelism
    localparam int NON_INPUT_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS - 1 : TRAINED_LAYERS - 1,
    parameter int PARALLEL_INPUTS = 8,
    parameter int LAYER_PARALLEL_INPUTS[NON_INPUT_LAYERS] = '{64, 32, 32},
    parameter int PARALLEL_NEURONS[NON_INPUT_LAYERS]      = '{32, 32, 10}
);
    import bnn_fcc_tb_pkg::*;

    typedef enum logic [1:0] {
        RST_IDLE,
        RST_DURING_CONFIG,
        RST_DURING_INPUT,
        RST_DURING_OUTPUT
    } reset_scenario_e;

    // Topology and file paths
    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS;
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] = USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY;

    localparam string MNIST_TEST_VECTOR_INPUT_PATH  = "test_vectors/inputs.hex";
    localparam string MNIST_TEST_VECTOR_OUTPUT_PATH = "test_vectors/expected_outputs.txt";
    localparam string MNIST_MODEL_DATA_PATH         = "model_data";

    // Fixed timing used by the driver and directed tests
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int DIRECTED_SHORT_GAP_CYCLES = 2;
    localparam int DIRECTED_LONG_GAP_CYCLES  = 6;
localparam int DIRECTED_INPUT_TESTS =
        (ALT_J_GAP_LEN ? 2 : 0) +
        (FORCE_SHORT_GAP_BEFORE_LAST ? 1 : 0) +
        (FORCE_LONG_GAP_BEFORE_LAST ? 1 : 0);
    localparam int DIRECTED_TESTS = DIRECTED_INPUT_TESTS;

    initial begin
        assert (INPUT_DATA_WIDTH == 8)
        else $fatal(1, "TB ERROR: INPUT_DATA_WIDTH must be 8. Sub-byte or multi-byte packing logic not yet implemented.");
    end

    // Returns 1 with probability p
    function automatic bit chance(real p);
        if (p > 1.0 || p < 0.0) $fatal(1, "Invalid probability in chance()");
        return ($urandom < (p * (2.0 ** 32)));
    endfunction

    // Model, stimulus, and scoreboarding state
    BNN_FCC_Model #(CONFIG_BUS_WIDTH) model;
    BNN_FCC_Stimulus #(INPUT_DATA_WIDTH) stim;

    bit [CONFIG_BUS_WIDTH-1:0]   config_bus_data_stream[];
    bit [CONFIG_BUS_WIDTH/8-1:0] config_bus_keep_stream[];
    bit                          config_bus_tlast_stream[];

    int num_tests;
    int total_tests;
    int passed;
    int failed;
    int dbg_img_idx;
    logic [OUTPUT_DATA_WIDTH-1:0] expected_outputs[$];

    // Output tracking
    int output_count;

    logic clk = 1'b0;
    logic rst;

    axi4_stream_if #(
        .DATA_WIDTH(CONFIG_BUS_WIDTH)
    ) config_in (
        .aclk   (clk),
        .aresetn(!rst)
    );

    axi4_stream_if #(
        .DATA_WIDTH(INPUT_BUS_WIDTH)
    ) data_in (
        .aclk   (clk),
        .aresetn(!rst)
    );

    axi4_stream_if #(
        .DATA_WIDTH(OUTPUT_BUS_WIDTH)
    ) data_out (
        .aclk   (clk),
        .aresetn(!rst)
    );

    bnn_fcc #(
        .INPUT_DATA_WIDTH      (INPUT_DATA_WIDTH),
        .INPUT_BUS_WIDTH       (INPUT_BUS_WIDTH),
        .CONFIG_BUS_WIDTH      (CONFIG_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH     (OUTPUT_DATA_WIDTH),
        .OUTPUT_BUS_WIDTH      (OUTPUT_BUS_WIDTH),
        .TOTAL_LAYERS          (ACTUAL_TOTAL_LAYERS),
        .TOPOLOGY              (ACTUAL_TOPOLOGY),
        .PARALLEL_INPUTS       (PARALLEL_INPUTS),
        .LAYER_PARALLEL_INPUTS (LAYER_PARALLEL_INPUTS),
        .PARALLEL_NEURONS      (PARALLEL_NEURONS)
    ) DUT (
        .clk(clk),
        .rst(rst),

        .config_valid(config_in.tvalid),
        .config_ready(config_in.tready),
        .config_data (config_in.tdata),
        .config_keep (config_in.tkeep),
        .config_last (config_in.tlast),

        .data_in_valid(data_in.tvalid),
        .data_in_ready(data_in.tready),
        .data_in_data (data_in.tdata),
        .data_in_keep (data_in.tkeep),
        .data_in_last (data_in.tlast),

        .data_out_valid(data_out.tvalid),
        .data_out_ready(data_out.tready),
        .data_out_data (data_out.tdata),
        .data_out_keep (data_out.tkeep),
        .data_out_last (data_out.tlast)
    );

    // Signals only used for coverage tracking
    logic            prev_config_valid;
    logic            prev_tlast_accepted;
    logic [7:0]      config_cur_msg_type;
    logic [7:0]      config_cur_layer_id;
    logic            prev_data_out_ready;
    int              data_out_valid_wait;
    int              config_stalls_this_burst;
    int              config_stalls_at_burst_end;
    int              data_in_burst_run;
    int              data_in_gap_len;
    int              data_out_stall_count;
    bit              partial_config_sent;
    bit              config_load_done;
    int              reset_count;
    bit              seen_weight_after_reset;
    bit              seen_thresh_after_reset;
    int              img_pixel_range;
    reset_scenario_e current_reset_scenario;
    bit              reconfig_after_reset;
    bit              alt_ordering;
    int              last_output_class;

    int              config_inter_msg_gap;
    bit              config_msg_gap_pending;
    bit              config_had_first_tlast;
    int              config_beat_in_msg;
    logic            prev_data_in_valid;
    bit              data_in_ready_at_valid_rise;
    int              data_in_inter_image_gap;
    bit              data_in_inter_image_gap_active;
    int              class_example_idx[10];
    bit              class_example_valid[10];
    bit [INPUT_DATA_WIDTH-1:0] class_cov_img[10][];
    bit                        class_cov_valid[10];

// Coverage models
covergroup cg_config_bus @(posedge clk iff (!rst && config_in.tvalid && config_in.tready));
    
cp_valid_after_prev_not: coverpoint (prev_config_valid == 1'b0) {
        bins continuous                = {1'b0};
        bins prev_not_valid_then_valid = {1'b1};
    }

    cp_last: coverpoint config_in.tlast {
        bins middle_of_stream = {1'b0};
        bins end_of_stream    = {1'b1};
    }

    cp_keep: coverpoint config_in.tkeep {
        bins full_word    = {8'hFF};
        bins partial_word = default;
    }

endgroup

// Config message ordering coverage
covergroup cg_config_msg_ordering @(posedge clk iff (!rst && config_in.tvalid && config_in.tready && prev_tlast_accepted));

    cp_msg_type: coverpoint config_in.tdata[7:0] {
        bins weights   = {8'd0};
        bins threshold = {8'd1};
    }

    cp_prev_msg_type: coverpoint config_cur_msg_type {
        bins prev_weights    = {8'd0};
        bins prev_thresholds = {8'd1};
        bins first_message   = {8'hFF};
    }

    cx_msg_ordering: cross cp_prev_msg_type, cp_msg_type;

    cp_layer_id: coverpoint config_in.tdata[15:8] {
        bins layer_0 = {8'd0};
        bins layer_1 = {8'd1};
        bins layer_2 = {8'd2};
        
    }
    cp_layer_order: coverpoint ((config_in.tdata[15:8] > config_cur_layer_id) ? 2'b01 :
                                (config_in.tdata[15:8] < config_cur_layer_id) ? 2'b10 : 2'b00) {
        bins increased  = {2'b01};
        bins decreased  = {2'b10};
        bins same_layer = {2'b00};
    }

    cx_layer_msg: cross cp_layer_id, cp_msg_type {
        ignore_bins output_layer_threshold = binsof(cp_layer_id.layer_2) && binsof(cp_msg_type.threshold);
    }

    cp_dont_care_fields: coverpoint (config_in.tdata[63:16] != '0) {
        bins nonzero = {1'b1};
    }

endgroup

// Config valid burst coverage
covergroup cg_config_valid_pattern @(posedge clk iff (!rst && config_in.tvalid && !prev_config_valid));

    cp_stalls_in_burst: coverpoint config_stalls_at_burst_end {
        bins zero         = {0};
        bins stalls_1_3   = {[1:3]};
        bins stalls_4_10  = {[4:10]};
        bins stalls_11_50  = {[11:50]};
        bins stalls_51_200 = {[51:200]};
    }
endgroup

// Config ready stall position coverage
covergroup cg_config_stall_position @(posedge clk iff (!rst && config_in.tvalid && !config_in.tready));
    cp_stall_beat: coverpoint config_beat_in_msg {
        bins header_beat  = {0};
        bins payload_beat = {[1:$]};
    }
endgroup

// Config inter-message gap coverage
covergroup cg_config_inter_msg_gap @(posedge clk iff (!rst && config_msg_gap_pending && config_in.tvalid));
    cp_gap: coverpoint config_inter_msg_gap {
        bins back_to_back = {0};
        bins gap_1        = {1};
        bins gap_2_5      = {[2:5]};
        bins gap_6_20     = {[6:20]};
        bins gap_21_100   = {[21:100]};
        bins gap_101_500  = {[101:500]};
    }
    cp_next_msg_type: coverpoint config_in.tdata[7:0] {
        bins weights   = {8'd0};
        bins threshold = {8'd1};
    }
    cx_gap_x_type: cross cp_gap, cp_next_msg_type;
endgroup

// Config message length coverage
covergroup cg_config_msg_length @(posedge clk iff (!rst && config_in.tvalid && config_in.tready && prev_tlast_accepted));
    cp_single_beat: coverpoint config_in.tlast {
        bins single_beat_msg = {1'b1};
        bins multi_beat_msg  = {1'b0};
    }
    cp_msg_type: coverpoint config_in.tdata[7:0] {
        bins weights   = {8'd0};
        bins threshold = {8'd1};
    }
    cx_len_x_type: cross cp_single_beat, cp_msg_type;
endgroup

// Config keep and last coverage
covergroup cg_config_keep_last @(posedge clk iff (!rst && config_in.tvalid && config_in.tready));
    cp_keep: coverpoint config_in.tkeep {
        bins full_word    = {8'hFF};
        bins partial_word = default;
    }
    cp_last: coverpoint config_in.tlast {
        bins not_last = {1'b0};
        bins is_last  = {1'b1};
    }
    cx_keep_x_last: cross cp_keep, cp_last;
endgroup

// Input bus coverage
covergroup cg_data_in_bus @(posedge clk iff (!rst && data_in.tvalid && data_in.tready));

    cp_burst_run: coverpoint data_in_burst_run {
        bins single      = {1};
        bins run_2_8     = {[2:8]};
        bins run_9_32    = {[9:32]};
        bins run_33_128  = {[33:128]};
        bins run_129_512 = {[129:512]};
        bins run_513plus = {[513:$]};
    }

    cp_gap_len: coverpoint data_in_gap_len {
        bins no_gap      = {0};
        bins gap_1       = {1};
        bins gap_2_5     = {[2:5]};
        bins gap_6_20    = {[6:20]};
        bins gap_21_100  = {[21:100]};
        bins gap_101_500 = {[101:500]};
    }

    cp_last_beat: coverpoint data_in.tlast {
        bins not_last = {1'b0};
        bins last     = {1'b1};
    }

    cx_gap_at_last: cross cp_gap_len, cp_last_beat {
        ignore_bins common = binsof(cp_gap_len.no_gap) && binsof(cp_last_beat.not_last);
    }

    cp_pixel_content: coverpoint count_zero_bytes(data_in.tdata) {
        bins all_zero = {8};
        bins all_F    = {0};
        bins mixed    = {[1:7]};
    }

    cp_keep: coverpoint data_in.tkeep {
        bins full_word    = {8'hFF};
        bins partial_word = default;
    }
endgroup

// Output bus and class coverage
covergroup cg_output_bus @(posedge clk iff (!rst && data_out.tvalid && data_out.tready));

    cp_backpressure: coverpoint (prev_data_out_ready == 1'b0) {
        bins no_backpressure  = {1'b0};
        bins had_backpressure = {1'b1};
    }

    cp_bp_duration: coverpoint data_out_stall_count {
        bins bp_0       = {0};
        bins bp_1       = {1};
        bins bp_2_5     = {[2:5]};
        bins bp_6_10    = {[6:10]};
        bins bp_11_25   = {[11:25]};
        bins bp_26_50   = {[26:50]};
        bins bp_51_100  = {[51:100]};
        bins bp_101_250 = {[101:250]};
        bins bp_251_500 = {[251:500]};
        bins bp_501_1k  = {[501:1000]};
    }

    cp_output_class: coverpoint data_out.tdata[3:0] {
        bins class0 = {4'd0}; bins class1 = {4'd1}; bins class2 = {4'd2};
        bins class3 = {4'd3}; bins class4 = {4'd4}; bins class5 = {4'd5};
        bins class6 = {4'd6}; bins class7 = {4'd7}; bins class8 = {4'd8};
        bins class9 = {4'd9};
    }

    cx_class_under_bp: cross cp_output_class, cp_backpressure;

    cp_ready_timing: coverpoint data_out_valid_wait {
        bins ready_before_or_same = {0};
        bins wait_1               = {1};
        bins wait_2_5             = {[2:5]};
        bins wait_6_20            = {[6:20]};
        bins wait_21_100          = {[21:100]};
        bins wait_101_500         = {[101:500]};
        bins wait_501_1k          = {[501:1000]};
    }

    cx_class_ready_timing: cross cp_output_class, cp_ready_timing;

endgroup

// Output backpressure at tlast coverage
covergroup cg_output_tlast_bp @(posedge clk iff (!rst && data_out.tvalid && data_out.tready));
    cp_bp_at_tlast: coverpoint (prev_data_out_ready == 1'b0) {
        bins no_bp_at_last   = {1'b0};
        bins had_bp_at_tlast = {1'b1};
    }
endgroup

// Input pixel spread coverage
covergroup cg_input_diversity;

    cp_input_pixel_range: coverpoint img_pixel_range {
        bins uniform_image     = {0};
        bins low_spread_image  = {1};
        bins high_spread_image = {2};
    }

    cp_class_from_diverse: coverpoint last_output_class {
        bins class_0 = {0}; bins class_1 = {1}; bins class_2 = {2};
        bins class_3 = {3}; bins class_4 = {4}; bins class_5 = {5};
        bins class_6 = {6}; bins class_7 = {7}; bins class_8 = {8};
        bins class_9 = {9};
    }

endgroup

// Reset and reconfiguration coverage
covergroup cg_scenarios;

    cp_reset_when: coverpoint current_reset_scenario {
        bins during_idle   = {RST_IDLE};
        bins during_config = {RST_DURING_CONFIG};
        bins during_input  = {RST_DURING_INPUT};
        bins during_output = {RST_DURING_OUTPUT};
    }

    cp_post_reset_reconfig: coverpoint reconfig_after_reset {
        bins same_config = {1'b0};
        bins new_config  = {1'b1};
    }

    cp_partial_config: coverpoint partial_config_sent {
        bins full_config    = {1'b0};
        bins partial_config = {1'b1};
    }

    cp_reset_frequency: coverpoint reset_count {
        bins one_reset   = {1};
        bins resets_2_4  = {[2:4]};
        bins resets_5_10 = {[5:10]};
        bins resets_11plus = {[11:$]};
    }

    cp_reconfig_type: coverpoint {seen_thresh_after_reset, seen_weight_after_reset} {
        bins neither         = {2'b00};
        bins weights_only    = {2'b01};
        bins thresholds_only = {2'b10};
        bins both            = {2'b11};
    }

    cp_reset_at_tlast: coverpoint (config_in.tvalid && config_in.tready && config_in.tlast) {
        bins not_at_tlast = {1'b0};
        bins at_tlast     = {1'b1};
    }

endgroup

// Data-in handshake order coverage
covergroup cg_data_in_handshake_order @(posedge clk iff (!rst && data_in.tvalid && !prev_data_in_valid));
    cp_ready_when_valid_rose: coverpoint data_in_ready_at_valid_rise {
        bins ready_before_valid = {1'b1};
        bins valid_before_ready = {1'b0};
    }
    cp_beat_position: coverpoint data_in.tlast {
        bins mid_image = {1'b0};
        bins last_beat = {1'b1};
    }
    cx_handshake_at_beat: cross cp_ready_when_valid_rose, cp_beat_position;
endgroup

// Data-in inter-image gap coverage
covergroup cg_data_in_inter_image_gap @(posedge clk iff (!rst && data_in_inter_image_gap_active && data_in.tvalid));
    cp_gap: coverpoint data_in_inter_image_gap {
        bins back_to_back = {0};
        bins gap_1        = {1};
        bins gap_2_10     = {[2:10]};
        bins gap_11_50    = {[11:50]};
        bins gap_51_200   = {[51:200]};
        bins gap_201_1k   = {[201:1000]};
    }
endgroup

    // Coverage instances
    cg_config_bus            cov_config            = new();
    cg_config_valid_pattern  cov_config_pattern    = new();
    cg_config_msg_ordering   cov_config_msg_order  = new();
    cg_data_in_bus           cov_data_in           = new();
    cg_output_bus            cov_output            = new();
    cg_scenarios             cov_scenario          = new();
    cg_input_diversity       cov_input_diversity   = new();
    cg_config_inter_msg_gap    cov_config_inter_msg_gap = new();
    cg_config_stall_position   cov_config_stall_pos     = new();
    cg_data_in_handshake_order cov_data_in_hs_order     = new();
    cg_config_msg_length       cov_config_msg_len       = new();
    cg_config_keep_last        cov_config_keep_last     = new();
    cg_data_in_inter_image_gap cov_data_in_img_gap      = new();
    cg_output_tlast_bp         cov_output_tlast_bp      = new();

    // Track coverage state each cycle
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_config_valid          <= 1'b0;
            prev_tlast_accepted        <= 1'b1;
            config_cur_msg_type        <= 8'hFF;
            config_cur_layer_id        <= 8'hFF;
            prev_data_out_ready        <= 1'b1;
            data_out_valid_wait        <= 0;
            config_stalls_this_burst   <= 0;
            config_stalls_at_burst_end <= 0;
            data_in_burst_run              <= 0;
            data_in_gap_len                <= 0;
            data_out_stall_count           <= 0;
            partial_config_sent            <= 1'b0;
            config_load_done               <= 1'b0;
            seen_weight_after_reset        <= 1'b0;
            seen_thresh_after_reset        <= 1'b0;
            config_inter_msg_gap           <= 0;
            config_msg_gap_pending         <= 1'b0;
            config_had_first_tlast         <= 1'b0;
            config_beat_in_msg             <= 0;
            prev_data_in_valid             <= 1'b0;
            data_in_ready_at_valid_rise    <= 1'b0;
            data_in_inter_image_gap        <= 0;
            data_in_inter_image_gap_active <= 1'b0;
        end else begin
            prev_config_valid   <= config_in.tvalid;
            prev_data_out_ready <= data_out.tready;

            if (config_in.tvalid && !config_in.tready)
                config_stalls_this_burst <= config_stalls_this_burst + 1;
            else if (!config_in.tvalid) begin
                if (prev_config_valid)
                    config_stalls_at_burst_end <= config_stalls_this_burst;
                config_stalls_this_burst <= 0;
            end

            if (config_in.tvalid && config_in.tready) begin
                partial_config_sent <= ~config_in.tlast;
                if (config_in.tlast) config_load_done <= 1'b1;
            end

            if (config_in.tvalid && config_in.tready) begin
                if (prev_tlast_accepted) begin
                    config_cur_msg_type <= config_in.tdata[7:0];
                    config_cur_layer_id <= config_in.tdata[15:8];
                end
                prev_tlast_accepted <= config_in.tlast;
            end

            if (config_in.tvalid && config_in.tready && prev_tlast_accepted) begin
                if (config_in.tdata[7:0] == 8'd0) seen_weight_after_reset <= 1'b1;
                if (config_in.tdata[7:0] == 8'd1) seen_thresh_after_reset <= 1'b1;
            end

            if (data_in.tvalid && data_in.tready) begin
                data_in_burst_run <= data_in_burst_run + 1;
                data_in_gap_len   <= 0;
            end else if (!data_in.tvalid) begin
                data_in_burst_run <= 0;
                data_in_gap_len   <= data_in_gap_len + 1;
            end

            if (data_out.tvalid && !data_out.tready)
                data_out_stall_count <= data_out_stall_count + 1;
            else if (data_out.tvalid && data_out.tready)
                data_out_stall_count <= 0;

            if (data_out.tvalid && !data_out.tready)
                data_out_valid_wait <= data_out_valid_wait + 1;
            else if (data_out.tvalid && data_out.tready)
                data_out_valid_wait <= 0;

            if (config_in.tvalid && config_in.tready && config_in.tlast) begin
                config_had_first_tlast <= 1'b1;
                if (config_had_first_tlast) begin
                    config_msg_gap_pending <= 1'b1;
                    config_inter_msg_gap   <= 0;
                end
            end else if (config_msg_gap_pending) begin
                if (!config_in.tvalid)
                    config_inter_msg_gap <= config_inter_msg_gap + 1;
                else
                    config_msg_gap_pending <= 1'b0;
            end

            if (config_in.tvalid && config_in.tready && config_in.tlast)
                config_beat_in_msg <= 0;
            else if (config_in.tvalid && config_in.tready)
                config_beat_in_msg <= config_beat_in_msg + 1;

            prev_data_in_valid <= data_in.tvalid;
            if (data_in.tvalid && !prev_data_in_valid)
                data_in_ready_at_valid_rise <= data_in.tready;

            if (data_in.tvalid && data_in.tready && data_in.tlast) begin
                data_in_inter_image_gap_active <= 1'b1;
                data_in_inter_image_gap        <= 0;
            end else if (data_in_inter_image_gap_active) begin
                if (!data_in.tvalid)
                    data_in_inter_image_gap <= data_in_inter_image_gap + 1;
                else
                    data_in_inter_image_gap_active <= 1'b0;
            end
        end
    end

    // Classify each reset
    always @(posedge rst) begin
        reset_count = reset_count + 1;

        if (config_in.tvalid || partial_config_sent)
            current_reset_scenario = RST_DURING_CONFIG;
        else if (data_in.tvalid)
            current_reset_scenario = RST_DURING_INPUT;
        else if (data_out.tvalid)
            current_reset_scenario = RST_DURING_OUTPUT;
        else
            current_reset_scenario = RST_IDLE;

        reconfig_after_reset = config_load_done;
        cov_scenario.sample();
    end

    // Small helpers
    function automatic int count_zero_bytes(input logic [63:0] d);
        int n = 0;
        for (int i = 0; i < 8; i++)
            if (d[i*8+:8] == 8'h00) n++;
        return n;
    endfunction

    function automatic int compute_pixel_range(input int pmin, input int pmax);
        automatic int spread = pmax - pmin;
        return (spread < 32) ? 0 : (spread < 128) ? 1 : 2;
    endfunction

    // Coverage helpers
    task automatic compute_coverage_init();
        reset_count             = 0;
        last_output_class       = -1;
        reconfig_after_reset    = 1'b0;
        alt_ordering            = 1'b0;
        img_pixel_range         = 0;
    endtask

    // scan all test imagages and find one example image for each predicted class
    // for later direct tests
    task automatic build_class_example_index();
        automatic bit [INPUT_DATA_WIDTH-1:0] sample_img[];
        automatic int pred_class;
        automatic int missing_classes;
        automatic string input_path;
        BNN_FCC_Stimulus #(INPUT_DATA_WIDTH) stim_all;

        for (int class_id = 0; class_id < 10; class_id++) begin
            class_example_idx[class_id]   = -1;
            class_example_valid[class_id] = 1'b0;
            class_cov_valid[class_id]     = 1'b0;
        end

        for (int stim_idx = 0; stim_idx < num_tests; stim_idx++) begin
            stim.get_vector(stim_idx, sample_img);
            pred_class = model.compute_reference(sample_img);
            if (pred_class >= 0 && pred_class < 10 && !class_example_valid[pred_class]) begin
                class_example_idx[pred_class]   = stim_idx;
                class_example_valid[pred_class] = 1'b1;
                class_cov_img[pred_class]       = sample_img;
                class_cov_valid[pred_class]     = 1'b1;
            end
        end

        missing_classes = 0;
        for (int class_id = 0; class_id < 10; class_id++) begin
            if (!class_cov_valid[class_id])
                missing_classes++;
        end

        if (missing_classes > 0 && !USE_CUSTOM_TOPOLOGY) begin
            input_path = $sformatf("%s/%s", BASE_DIR, MNIST_TEST_VECTOR_INPUT_PATH);
            stim_all   = new(ACTUAL_TOPOLOGY[0]);
            stim_all.load_from_file(input_path);

            for (int stim_idx = 0; stim_idx < stim_all.get_num_vectors() && missing_classes > 0; stim_idx++) begin
                stim_all.get_vector(stim_idx, sample_img);
                pred_class = model.compute_reference(sample_img);
                if (pred_class >= 0 && pred_class < 10 && !class_cov_valid[pred_class]) begin
                    class_cov_img[pred_class]   = sample_img;
                    class_cov_valid[pred_class] = 1'b1;
                    missing_classes--;
                end
            end
        end

    endtask

    // pick images for later directed bp tests
    function automatic int select_bp_stim_idx(input int slot);
        for (int offset = 0; offset < 10; offset++) begin
            automatic int class_id = (slot + offset) % 10;
            if (class_example_valid[class_id])
                return class_example_idx[class_id];
        end
        return (num_tests > 0) ? (slot % num_tests) : 0;
    endfunction



    // check how much pixel values vary in input image
    task automatic compute_image_pixel_range(input bit [7:0] img[]);
        automatic int pmin = 255, pmax = 0;
        foreach (img[k]) begin
            if (int'(img[k]) < pmin) pmin = int'(img[k]);
            if (int'(img[k]) > pmax) pmax = int'(img[k]);
        end
        img_pixel_range = compute_pixel_range(pmin, pmax);
    endtask

    task automatic sample_output_coverage(int cur_class);
        last_output_class = cur_class;
        cov_input_diversity.sample();
    endtask

    // sends image, waits for output to be valid and keeps tready low for stall_cycles; then accepts it
    task automatic run_output_hold_case(input int tb_img_idx, input int stim_idx, input int stall_cycles);
        if (stall_cycles <= 0) begin
            force data_out.tready = 1'b1;
            drive_image(tb_img_idx, stim_idx, 0, 0);
            @(negedge clk);
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);
            @(negedge clk);
            release data_out.tready;
            return;
        end

        force data_out.tready = 1'b0;

        drive_image(tb_img_idx, stim_idx, 0, 0);
        @(negedge clk);
        clear_data_input_bus();

        @(posedge clk iff !rst && data_out.tvalid);
        if (stall_cycles > 1)
            repeat (stall_cycles - 1) @(posedge clk iff !rst && data_out.tvalid);

        @(negedge clk);
        force data_out.tready = 1'b1;
        wait_for_expected_outputs_to_drain(5);
        @(negedge clk);
        release data_out.tready;
    endtask

    task automatic run_output_hold_case_image(
        input int tb_img_idx,
        input bit [INPUT_DATA_WIDTH-1:0] custom_img[],
        input int stall_cycles
    );
        if (stall_cycles <= 0) begin
            force data_out.tready = 1'b1;
            drive_custom_image(tb_img_idx, custom_img, 0, 0);
            @(negedge clk);
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);
            @(negedge clk);
            release data_out.tready;
            return;
        end

        force data_out.tready = 1'b0;

        drive_custom_image(tb_img_idx, custom_img, 0, 0);
        @(negedge clk);
        clear_data_input_bus();

        @(posedge clk iff !rst && data_out.tvalid);
        if (stall_cycles > 1)
            repeat (stall_cycles - 1) @(posedge clk iff !rst && data_out.tvalid);

        @(negedge clk);
        force data_out.tready = 1'b1;
        wait_for_expected_outputs_to_drain(5);
        @(negedge clk);
        release data_out.tready;
    endtask

    // force data_out.tread to 0; fee multiple images into BNN; wait until first output is valid; keep output blocked for stall_cycles
    // relese data_out.tready; see if all outputs good 
    // WILL BREAK DESIGN RIGHT NOW BECAUSE NO OUTPUT FIFO
    task automatic run_output_overflow_case(input int base_tb_img_idx, input int first_slot, input int num_imgs, input int stall_cycles);
        automatic bit driver_done;

        driver_done = 1'b0;
        force data_out.tready = 1'b0;

        fork
            begin : drive_blocked_outputs
                for (int img_idx = 0; img_idx < num_imgs; img_idx++) begin
                    drive_image(base_tb_img_idx + img_idx, select_bp_stim_idx(first_slot + img_idx), 0, 0);
                end
                @(negedge clk);
                clear_data_input_bus();
                driver_done = 1'b1;
            end
        join_none

        @(posedge clk iff !rst && data_out.tvalid);
        if (stall_cycles > 1)
            repeat (stall_cycles - 1) @(posedge clk iff !rst && data_out.tvalid);

        @(negedge clk);
        force data_out.tready = 1'b1;

        wait (driver_done);
        wait_for_expected_outputs_to_drain(5);
        @(negedge clk);
        release data_out.tready;
    endtask

    // Driver helpers
    task automatic pulse_reset();
        @(negedge clk);
        rst <= 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);
    endtask

    task automatic clear_config_input_bus();
        config_in.tvalid <= 1'b0;
        config_in.tlast  <= 1'b0;
    endtask

    task automatic clear_data_input_bus();
        data_in.tvalid <= 1'b0;
        data_in.tlast  <= 1'b0;
        data_in.tkeep  <= '0;
    endtask

    task automatic clear_expected_outputs();
        expected_outputs = {};
    endtask

    task automatic pulse_reset_and_clear_expected();
        @(negedge clk);
        rst <= 1'b1;
        clear_expected_outputs();
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);
    endtask

    task automatic wait_for_input_ready(input int settle_cycles);
        wait (data_in.tready);
        repeat (settle_cycles) @(posedge clk);
    endtask

    task automatic wait_for_expected_outputs_to_drain(input int settle_cycles);
        wait (expected_outputs.size() == 0);
        repeat (settle_cycles) @(posedge clk);
    endtask

    task automatic send_default_config_and_wait(input int settle_cycles);
        send_config_stream(1'b0, 1'b0);
        wait_for_input_ready(settle_cycles);
    endtask

    always @(posedge clk) begin
        if (PRINT_THROUGH_IMAGES && !rst && data_in.tvalid && data_in.tready) begin
            $display("[IN_HS] img=%0d last=%0b data=%0h", dbg_img_idx, data_in.tlast, data_in.tdata);
        end
    end

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task verify_model();
        int python_preds[];
        bit [INPUT_DATA_WIDTH-1:0] current_img[];
        string input_path;
        string output_path;

        input_path  = $sformatf("%s/%s", BASE_DIR, MNIST_TEST_VECTOR_INPUT_PATH);
        output_path = $sformatf("%s/%s", BASE_DIR, MNIST_TEST_VECTOR_OUTPUT_PATH);

        stim.load_from_file(input_path);
        num_tests = stim.get_num_vectors();

        python_preds = new[num_tests];
        $readmemh(output_path, python_preds);

        for (int i = 0; i < num_tests; i++) begin
            int sv_pred;
            stim.get_vector(i, current_img);
            sv_pred = model.compute_reference(current_img);

            if (sv_pred !== python_preds[i]) begin
                $error("TB LOGIC ERROR: Img %0d. SV Model says %0d, Python says %0d", i, sv_pred, python_preds[i]);
                $finish;
            end
        end

        $display("SV model successfully verified.");
    endtask

    // Config stream helpers
    // write junk into reserved header of each config message
    task inject_reserved_garbage();
        for (int i = 0; i < config_bus_data_stream.size(); i++) begin
            // Reserved field is in beat 1 of each message
            if ((i == 0 || config_bus_tlast_stream[i-1]) && (i + 1 < config_bus_data_stream.size())) begin
                // [63:32] of beat 1 is the reserved field
                config_bus_data_stream[i+1][63:32] = 32'hDEAD_BEEF;
            end
        end
    endtask

    // Compute which beats in the config stream are the last beat of their AXI message (tlast).
    // encode_configuration doesn't output this anymore, so we rebuild it by asking the model
    // for each message's size and marking the final beat of each one.
    task automatic compute_config_tlast();
        bit [CONFIG_BUS_WIDTH-1:0]   msg_stream[];
        bit [CONFIG_BUS_WIDTH/8-1:0] msg_keep[];
        bit msg_tlast[];
        config_bus_tlast_stream = new[0];

        for (int l = 0; l < model.num_layers; l++) begin
            model.get_layer_config(l, 0, msg_stream, msg_keep);
            msg_tlast = new[msg_stream.size()];
            foreach (msg_tlast[i]) msg_tlast[i] = (i == msg_stream.size() - 1);
            config_bus_tlast_stream = {config_bus_tlast_stream, msg_tlast};

            if (l < model.num_layers - 1) begin
                model.get_layer_config(l, 1, msg_stream, msg_keep);
                msg_tlast = new[msg_stream.size()];
                foreach (msg_tlast[i]) msg_tlast[i] = (i == msg_stream.size() - 1);
                config_bus_tlast_stream = {config_bus_tlast_stream, msg_tlast};
            end
        end
    endtask

    task automatic rebuild_default_config_stream();
        //  convert model weights and thresholds into AXI-stream config words
        model.encode_configuration(config_bus_data_stream, config_bus_keep_stream);
        compute_config_tlast();
        inject_reserved_garbage();
    endtask

    task reorder_config_stream_weights_first();
        automatic int chunk_starts[$];
        automatic int chunk_sizes[$];
        automatic bit [7:0] chunk_types[$];
        automatic bit [CONFIG_BUS_WIDTH-1:0]   new_data[];
        automatic bit [CONFIG_BUS_WIDTH/8-1:0] new_keep[];
        automatic bit                          new_tlast[];
        automatic int total = config_bus_data_stream.size();
        automatic int idx   = 0;

        for (int i = 0; i < total; i++) begin
            if (i == 0 || config_bus_tlast_stream[i-1]) begin
                chunk_starts.push_back(i);
                chunk_types.push_back(config_bus_data_stream[i][7:0]);
            end
        end
        for (int c = 0; c < chunk_starts.size(); c++) begin
            automatic int next = (c + 1 < chunk_starts.size()) ? chunk_starts[c+1] : total;
            chunk_sizes.push_back(next - chunk_starts[c]);
        end

        new_data  = new[total];
        new_keep  = new[total];
        new_tlast = new[total];

        foreach (chunk_starts[c]) begin
            if (chunk_types[c] == 8'd0) begin
                for (int i = 0; i < chunk_sizes[c]; i++) begin
                    new_data[idx]  = config_bus_data_stream[chunk_starts[c] + i];
                    new_keep[idx]  = config_bus_keep_stream[chunk_starts[c] + i];
                    new_tlast[idx] = config_bus_tlast_stream[chunk_starts[c] + i];
                    idx++;
                end
            end
        end
        foreach (chunk_starts[c]) begin
            if (chunk_types[c] == 8'd1) begin
                for (int i = 0; i < chunk_sizes[c]; i++) begin
                    new_data[idx]  = config_bus_data_stream[chunk_starts[c] + i];
                    new_keep[idx]  = config_bus_keep_stream[chunk_starts[c] + i];
                    new_tlast[idx] = config_bus_tlast_stream[chunk_starts[c] + i];
                    idx++;
                end
            end
        end

        config_bus_data_stream  = new_data;
        config_bus_keep_stream  = new_keep;
        config_bus_tlast_stream = new_tlast;
    endtask

    task reorder_config_stream_threshold_first();
        automatic int chunk_starts[$];
        automatic int chunk_sizes[$];
        automatic bit [7:0] chunk_types[$];
        automatic bit [CONFIG_BUS_WIDTH-1:0]   new_data[];
        automatic bit [CONFIG_BUS_WIDTH/8-1:0] new_keep[];
        automatic bit                          new_tlast[];
        automatic int total = config_bus_data_stream.size();
        automatic int idx   = 0;

        for (int i = 0; i < total; i++) begin
            if (i == 0 || config_bus_tlast_stream[i-1]) begin
                chunk_starts.push_back(i);
                chunk_types.push_back(config_bus_data_stream[i][7:0]);
            end
        end
        for (int c = 0; c < chunk_starts.size(); c++) begin
            automatic int next = (c + 1 < chunk_starts.size()) ? chunk_starts[c+1] : total;
            chunk_sizes.push_back(next - chunk_starts[c]);
        end

        new_data  = new[total];
        new_keep  = new[total];
        new_tlast = new[total];

        foreach (chunk_starts[c]) begin
            if (chunk_types[c] == 8'd1) begin
                for (int i = 0; i < chunk_sizes[c]; i++) begin
                    new_data[idx]  = config_bus_data_stream[chunk_starts[c] + i];
                    new_keep[idx]  = config_bus_keep_stream[chunk_starts[c] + i];
                    new_tlast[idx] = config_bus_tlast_stream[chunk_starts[c] + i];
                    idx++;
                end
            end
        end
        foreach (chunk_starts[c]) begin
            if (chunk_types[c] == 8'd0) begin
                for (int i = 0; i < chunk_sizes[c]; i++) begin
                    new_data[idx]  = config_bus_data_stream[chunk_starts[c] + i];
                    new_keep[idx]  = config_bus_keep_stream[chunk_starts[c] + i];
                    new_tlast[idx] = config_bus_tlast_stream[chunk_starts[c] + i];
                    idx++;
                end
            end
        end

        config_bus_data_stream  = new_data;
        config_bus_keep_stream  = new_keep;
        config_bus_tlast_stream = new_tlast;
    endtask

    // send only one kind of config packet from config stream
    task automatic send_config_packets_of_type(input bit [7:0] msg_type);
        automatic int i = 0;

        while (i < config_bus_data_stream.size()) begin
            if (config_bus_data_stream[i][7:0] == msg_type) begin
                do begin
                    @(negedge clk);
                    config_in.tdata  <= config_bus_data_stream[i];
                    config_in.tkeep  <= config_bus_keep_stream[i];
                    config_in.tlast  <= config_bus_tlast_stream[i];
                    config_in.tvalid <= 1'b1;
                    @(posedge clk iff config_in.tready);
                    @(negedge clk);
                    config_in.tvalid <= 1'b0;
                    config_in.tlast  <= 1'b0;
                end while (!config_bus_tlast_stream[i++]);
            end else begin
                while (!config_bus_tlast_stream[i])
                    i++;
                i++;
            end
        end
    endtask

    task send_config_stream(
        input bit force_large_gap,
        input bit force_large_stall
    );
        automatic int large_gap_beat;
        automatic int large_stall_tlast;
        large_gap_beat = (force_large_gap && config_bus_data_stream.size() > 1) ? 1 : -1;

        large_stall_tlast = -1;
        if (force_large_stall) begin
            for (int i = 0; i < config_bus_data_stream.size() - 1; i++) begin
                if (config_bus_tlast_stream[i]) begin
                    large_stall_tlast = i;
                    break;
                end
            end
        end

        for (int i = 0; i < config_bus_data_stream.size(); i++) begin
            if (i == large_gap_beat) begin
                @(negedge clk);
                config_in.tvalid <= 1'b0;
                repeat (15) @(posedge clk);
            end
            while (!chance(CONFIG_VALID_PROBABILITY)) begin
                @(negedge clk);
                config_in.tvalid <= 1'b0;
                config_in.tlast  <= 1'b0;
            end
            @(negedge clk);
            config_in.tdata  <= config_bus_data_stream[i];
            config_in.tkeep  <= config_bus_keep_stream[i];
            config_in.tlast  <= config_bus_tlast_stream[i];
            config_in.tvalid <= 1'b1;
            while (1) begin
                @(posedge clk);
                if (config_in.tvalid && config_in.tready)
                    break;
            end
            // usually tb stops asking to send between beat but here keeps asking while DUT says not ready (for real stall cycles)
            if (i != large_stall_tlast) begin
                @(negedge clk);
                config_in.tvalid <= 1'b0;
                config_in.tlast  <= 1'b0;
            end
        end
    endtask

    // directed tests with stall lengths to see if dut good with BP
    task automatic run_output_backpressure_tests();
        automatic int stall_cycles[10] = '{0, 1, 4, 8, 20, 40, 75, 150, 350, 750};
        automatic int num_cases;

        if (!FORCE_BP_DURATION_COVERAGE)
            return;

        if (num_tests == 0)
            return;

        num_cases = ALLOW_BP_GREATER_THAN_100 ? 10 : 7;

        $display("[%0t] Running directed output backpressure tests.", $realtime);

        for (int case_idx = 0; case_idx < num_cases; case_idx++) begin
            run_output_hold_case(
                total_tests,
                select_bp_stim_idx(case_idx),
                stall_cycles[case_idx]
            );
            total_tests = total_tests + 1;
        end

        if (ALLOW_BP_GREATER_THAN_100) begin
            $display("[%0t] Running multi-image long-stall output stress test.", $realtime);
            run_output_overflow_case(total_tests, 0, 4, 750);
            total_tests = total_tests + 4;
        end
    endtask

    // Testbench setup and stimulus
    initial begin : l_init_model
        string path;

        model      = new();
        stim       = new(ACTUAL_TOPOLOGY[0]);

        if (!USE_CUSTOM_TOPOLOGY) begin
            $display("--- Loading Trained Model ---");
            path = $sformatf("%s/%s", BASE_DIR, MNIST_MODEL_DATA_PATH);
            model.load_from_file(path, ACTUAL_TOPOLOGY);
            if (VERIFY_MODEL) verify_model();
            rebuild_default_config_stream();
            $display("--- Configuration created: %0d words (%0d-bit wide) ---", config_bus_data_stream.size(), CONFIG_BUS_WIDTH);

            $display("--- Loading Test Vectors ---");
            path = $sformatf("%s/%s", BASE_DIR, MNIST_TEST_VECTOR_INPUT_PATH);
            stim.load_from_file(path, NUM_TEST_IMAGES);
        end else begin
            $display("--- Loading Randomized Model ---");
            model.create_random(ACTUAL_TOPOLOGY);
            rebuild_default_config_stream();
            $display("--- Configuration created: %0d words (%0d-bit wide) ---", config_bus_data_stream.size(), CONFIG_BUS_WIDTH);

            $display("--- Generating Random Test Vectors ---");
            stim.generate_random_vectors(NUM_TEST_IMAGES);
        end

        num_tests = stim.get_num_vectors();
        total_tests = num_tests + DIRECTED_TESTS;
        model.print_summary();
        build_class_example_index();

        if (DEBUG) model.print_model();
    end

    assign config_in.tstrb = config_in.tkeep;
    assign data_in.tstrb   = data_in.tkeep;

    // Send config stream with TVALID never dropped between messages
    task automatic send_config_stream_back_to_back();
        for (int i = 0; i < config_bus_data_stream.size(); i++) begin
            @(negedge clk);
            config_in.tdata  <= config_bus_data_stream[i];
            config_in.tkeep  <= config_bus_keep_stream[i];
            config_in.tlast  <= config_bus_tlast_stream[i];
            config_in.tvalid <= 1'b1;
            @(posedge clk iff config_in.tready);
        end
        @(negedge clk);
        config_in.tvalid <= 1'b0;
        config_in.tlast  <= 1'b0;
    endtask

    // Send config stream with a N-cycle gap inserted after every message tlast
    // to hit cg_config_inter_msg_gap gap_21_100 and gap_101_500 bins
    task automatic send_config_stream_with_inter_msg_gap(input int gap_cycles);
        for (int i = 0; i < config_bus_data_stream.size(); i++) begin
            @(negedge clk);
            config_in.tdata  <= config_bus_data_stream[i];
            config_in.tkeep  <= config_bus_keep_stream[i];
            config_in.tlast  <= config_bus_tlast_stream[i];
            config_in.tvalid <= 1'b1;
            while (1) begin
                @(posedge clk);
                if (config_in.tvalid && config_in.tready) break;
            end
            @(negedge clk);
            config_in.tvalid <= 1'b0;
            config_in.tlast  <= 1'b0;
            if (config_bus_tlast_stream[i])
                repeat (gap_cycles) @(posedge clk);
        end
    endtask

    // Drive one image with no random TVALID gaps
    task automatic drive_image_back_to_back(input int stim_idx);
        automatic int expected_pred;
        automatic bit [INPUT_DATA_WIDTH-1:0] img[];
        stim.get_vector(stim_idx, img);
        compute_image_pixel_range(img);
        expected_pred = model.compute_reference(img);
        expected_outputs.push_back(expected_pred);
        for (int j = 0; j < img.size(); j += INPUTS_PER_CYCLE) begin
            @(negedge clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                if (j + k < img.size()) begin
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img[j+k];
                    data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
                end else begin
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= '0;
                    data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '0;
                end
            end
            data_in.tvalid <= 1'b1;
            data_in.tlast  <= (j + INPUTS_PER_CYCLE >= img.size());
            @(posedge clk);
            while (!data_in.tready) @(posedge clk);
        end
    endtask

    task automatic reset_and_reconfigure(
        input bit force_large_gap,
        input bit force_large_stall,
        input bit force_threshold_first
    );
        pulse_reset();

        clear_expected_outputs();
        rebuild_default_config_stream();
        if (force_threshold_first) begin
            reorder_config_stream_threshold_first();
        end else if (ALT_CONFIG_ORDERING) begin
            alt_ordering = ~alt_ordering;
            if (alt_ordering) reorder_config_stream_weights_first();
        end

        if (PRINT_THROUGH_IMAGES) begin
            automatic string cfg_suffix;
            cfg_suffix = "";
            if (force_threshold_first)
                cfg_suffix = " (threshold first)";
            else if (ALT_CONFIG_ORDERING && alt_ordering)
                cfg_suffix = " (alt ordering)";
            $display("[%0t] Re-streaming config%s.", $realtime, cfg_suffix);
        end

        send_config_stream(force_large_gap, force_large_stall);
        wait_for_input_ready(5);
    endtask

    task automatic drive_image(
        input int tb_img_idx,
        input int stim_idx,
        input int gap_before_image_cycles,
        input int gap_before_last_cycles
    );
        automatic int expected_pred;
        automatic bit [INPUT_DATA_WIDTH-1:0] current_img[];

        if (gap_before_image_cycles > 0) begin
            @(negedge clk);
            data_in.tvalid <= 1'b0;
            data_in.tlast  <= 1'b0;
            repeat (gap_before_image_cycles) @(posedge clk);
        end

        dbg_img_idx = tb_img_idx;
        stim.get_vector(stim_idx, current_img);
        compute_image_pixel_range(current_img);
        expected_pred = model.compute_reference(current_img);
        expected_outputs.push_back(expected_pred);

        if (PRINT_THROUGH_IMAGES)
            $display("[%0t] Streaming image %0d.", $realtime, tb_img_idx);
        if (DEBUG && PRINT_THROUGH_IMAGES)
            model.print_inference_trace();

        for (int j = 0; j < current_img.size(); j += INPUTS_PER_CYCLE) begin
            // Forced gap before the last beat
            if (gap_before_last_cycles > 0 && (j + INPUTS_PER_CYCLE >= current_img.size())) begin
                @(negedge clk);
                data_in.tvalid <= 1'b0;
                data_in.tlast  <= 1'b0;
                repeat (gap_before_last_cycles) @(posedge clk);
            end

            // Random mid-image TVALID gaps
            // deassert for one cycle with probability (1 - DATA_IN_VALID_PROBABILITY) before each beat
            while (!chance(DATA_IN_VALID_PROBABILITY)) begin
                @(negedge clk);
                data_in.tvalid <= 1'b0;
                data_in.tlast  <= 1'b0;
                @(posedge clk);
            end

            @(negedge clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                if (j + k < current_img.size()) begin
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= current_img[j+k];
                    data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
                end else begin
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= '0;
                    data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '0;
                end
            end
            data_in.tvalid <= 1'b1;
            data_in.tlast  <= (j + INPUTS_PER_CYCLE >= current_img.size());

            @(posedge clk);
            while (!data_in.tready) @(posedge clk);
        end
    endtask

    task automatic drive_custom_image(
        input int tb_img_idx,
        input bit [INPUT_DATA_WIDTH-1:0] custom_img[],
        input int gap_before_image_cycles,
        input int gap_before_last_cycles
    );
        automatic int expected_pred;

        if (gap_before_image_cycles > 0) begin
            @(negedge clk);
            data_in.tvalid <= 1'b0;
            data_in.tlast  <= 1'b0;
            repeat (gap_before_image_cycles) @(posedge clk);
        end

        dbg_img_idx = tb_img_idx;
        compute_image_pixel_range(custom_img);
        expected_pred = model.compute_reference(custom_img);
        expected_outputs.push_back(expected_pred);

        if (PRINT_THROUGH_IMAGES)
            $display("[%0t] Streaming custom image %0d.", $realtime, tb_img_idx);

        for (int j = 0; j < custom_img.size(); j += INPUTS_PER_CYCLE) begin
            if (gap_before_last_cycles > 0 && (j + INPUTS_PER_CYCLE >= custom_img.size())) begin
                @(negedge clk);
                data_in.tvalid <= 1'b0;
                data_in.tlast  <= 1'b0;
                repeat (gap_before_last_cycles) @(posedge clk);
            end

            while (!chance(DATA_IN_VALID_PROBABILITY)) begin
                @(negedge clk);
                data_in.tvalid <= 1'b0;
                data_in.tlast  <= 1'b0;
                @(posedge clk);
            end

            @(negedge clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                if (j + k < custom_img.size()) begin
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= custom_img[j+k];
                    data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
                end else begin
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= '0;
                    data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '0;
                end
            end

            data_in.tvalid <= 1'b1;
            data_in.tlast  <= (j + INPUTS_PER_CYCLE >= custom_img.size());
            @(posedge clk);
            while (!data_in.tready) @(posedge clk);
        end
    endtask

    initial begin : l_sequencer_and_driver
        automatic int inter_gap_cycles;
        automatic int gap_before_last_cycles;
        automatic int directed_slot;
        automatic int stim_idx;

        $timeformat(-9, 0, " ns", 0);

        passed             = 0;
        failed             = 0;
        output_count       = 0;

        rst              <= 1'b1;
        config_in.tvalid <= 1'b0;
        config_in.tdata  <= '0;
        config_in.tkeep  <= '0;
        config_in.tlast  <= 1'b0;
        data_in.tvalid   <= 1'b0;
        data_in.tdata    <= '0;
        data_in.tkeep    <= '0;
        data_in.tlast    <= 1'b0;
        compute_coverage_init();

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        $display("[%0t] Streaming weights and thresholds.", $realtime);
        send_default_config_and_wait(5);

        if ((DIRECTED_TESTS > 0 || FORCE_BP_DURATION_COVERAGE) && num_tests == 0) begin
            $fatal(1, "Directed coverage tests need at least one loaded image.");
        end

        for (int i = 0; i < num_tests; i++) begin
            if (RESET_EVERY_N_IMAGES > 0) begin
                if (i > 0 && i % RESET_EVERY_N_IMAGES == 0) begin
                    if (PRINT_THROUGH_IMAGES)
                        $display("[%0t] Resetting after image %0d.", $realtime, i);
                    clear_data_input_bus();
                    reset_and_reconfigure(1'b0, 1'b0, 1'b0);
                end
            end

            drive_image(i, i, 0, 0);
        end

        clear_data_input_bus();

        $display("[%0t] Main image sweep done, waiting for outputs.", $realtime);
        wait_for_expected_outputs_to_drain(5);

        if (FORCE_LARGE_CONFIG_GAP || FORCE_LARGE_CONFIG_STALL ||
            DIRECTED_TESTS > 0 || FORCE_BP_DURATION_COVERAGE) begin
            $display("[%0t] Starting directed coverage phase.", $realtime);
        end

        if (FORCE_LARGE_CONFIG_GAP || FORCE_LARGE_CONFIG_STALL) begin
            clear_data_input_bus();
            reset_and_reconfigure(FORCE_LARGE_CONFIG_GAP, FORCE_LARGE_CONFIG_STALL, 1'b0);
        end

        if (THRESHOLD_FIRST_MSG_DIRECTED_TEST) begin
            $display("[%0t] Running directed threshold-first config test.", $realtime);
            clear_data_input_bus();
            reset_and_reconfigure(1'b0, 1'b0, 1'b1);
        end


        for (int d = 0; d < DIRECTED_TESTS; d++) begin
            inter_gap_cycles       = 0;
            gap_before_last_cycles = 0;
            directed_slot          = 0;
            stim_idx               = d % num_tests;

            if (ALT_J_GAP_LEN) begin
                if (d == directed_slot)
                    inter_gap_cycles = DIRECTED_SHORT_GAP_CYCLES;
                else if (d == directed_slot + 1)
                    inter_gap_cycles = DIRECTED_LONG_GAP_CYCLES;
                directed_slot += 2;
            end

            if (FORCE_SHORT_GAP_BEFORE_LAST) begin
                if (d == directed_slot)
                    gap_before_last_cycles = DIRECTED_SHORT_GAP_CYCLES;
                directed_slot++;
            end

            if (FORCE_LONG_GAP_BEFORE_LAST) begin
                if (d == directed_slot)
                    gap_before_last_cycles = DIRECTED_LONG_GAP_CYCLES;
                directed_slot++;
            end

            drive_image(num_tests + d, stim_idx, inter_gap_cycles, gap_before_last_cycles);
        end

        clear_data_input_bus();

        $display("[%0t] All images loaded, waiting for outputs.", $realtime);
        wait_for_expected_outputs_to_drain(5);

        $display("[%0t] Starting directed edge-case tests.", $realtime);

        // partial config interrupted by reset
        begin : dir_partial_config_interrupted_by_reset
            @(negedge clk);
            config_in.tdata  <= config_bus_data_stream[0];
            config_in.tkeep  <= config_bus_keep_stream[0];
            config_in.tlast  <= 1'b0;
            config_in.tvalid <= 1'b1;
            @(posedge clk iff config_in.tready);   // beat accepted
            @(negedge clk);
            config_in.tvalid <= 1'b0;
            @(posedge clk);
            @(negedge clk);
            rst <= 1'b1;   // reset while only part of the config was sent
            clear_expected_outputs();
            repeat (5) @(posedge clk);
            @(negedge clk);
            rst <= 1'b0;
            repeat (5) @(posedge clk);
        end
        send_default_config_and_wait(3);

        // RST_DURING_INPUT
        begin : dir_rst_during_input
            automatic bit [INPUT_DATA_WIDTH-1:0] img_f[];
            stim.get_vector(0, img_f);

            @(negedge clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++)
                data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_f[k];
            data_in.tkeep  <= '1;
            data_in.tvalid <= 1'b1;
            data_in.tlast  <= 1'b0;
            @(posedge clk iff data_in.tready);
            // Keep valid high so data_in.tvalid=1 at posedge rst
            @(negedge clk);
            data_in.tvalid <= 1'b1;
            data_in.tlast  <= 1'b0;
            rst <= 1'b1;
            clear_expected_outputs();
            repeat (5) @(posedge clk);
            @(negedge clk);
            rst <= 1'b0;
            clear_data_input_bus();
            repeat (5) @(posedge clk);
        end
        send_default_config_and_wait(3);

        // RST_DURING_OUTPUT
        begin : dir_rst_during_output
            automatic bit [INPUT_DATA_WIDTH-1:0] img_g[];
            stim.get_vector(0, img_g);

            // Hold tready=0 the whole time so the output just sits there waiting
            // keep it forced low until reset is done.
            force data_out.tready = 1'b0;

            // Send one image so the DUT eventually produces an output on data_out.
            drive_image(total_tests, 0, 0, 0);
            total_tests = total_tests + 1;

            // drive_image leaves tvalid/tlast still high after the last input beat so clear them now so when we reset the coverpoint sees only an output
            @(negedge clk);
            clear_data_input_bus();

            // Wait until the DUT has something on data out then reset
            @(posedge clk iff !rst && data_out.tvalid);
            @(negedge clk);
            rst <= 1'b1;
            clear_expected_outputs();
            total_tests      = total_tests - 1; 
            repeat (6) @(posedge clk);
            @(negedge clk);
            rst            <= 1'b0;
            clear_data_input_bus();
            release data_out.tready;
            repeat (5) @(posedge clk);
        end
        send_default_config_and_wait(3);

        // cp_reset_at_tlast
        begin : dir_rst_at_tlast
            rebuild_default_config_stream();

            for (int ci = 0; ci < config_bus_data_stream.size(); ci++) begin
                @(negedge clk);
                config_in.tdata  <= config_bus_data_stream[ci];
                config_in.tkeep  <= config_bus_keep_stream[ci];
                config_in.tlast  <= config_bus_tlast_stream[ci];
                config_in.tvalid <= 1'b1;
                @(posedge clk iff config_in.tready);

                if (config_bus_tlast_stream[ci] &&
                    ci == config_bus_data_stream.size() - 1) begin
                    // Last tlast so keep valid/last high and reset at next negedge
                    @(negedge clk);
                    config_in.tvalid <= 1'b1;
                    config_in.tlast  <= 1'b1;
                    rst <= 1'b1;
                    clear_expected_outputs();
                    repeat (5) @(posedge clk);
                    @(negedge clk);
                    rst              <= 1'b0;
                    config_in.tvalid <= 1'b0;
                    config_in.tlast  <= 1'b0;
                    repeat (5) @(posedge clk);
                    break;
                end else begin
                    @(negedge clk);
                    config_in.tvalid <= 1'b0;
                    config_in.tlast  <= 1'b0;
                end
            end
        end
        send_default_config_and_wait(3);


        // send only weight packets (type==0), then reset
        begin : dir_reconfig_weights_only
            pulse_reset_and_clear_expected();
            send_config_packets_of_type(8'd0);

            repeat (3) @(posedge clk);
            pulse_reset_and_clear_expected();  
        end

        // send only threshold packets (type==1), then reset
        begin : dir_reconfig_thresh_only
            send_config_packets_of_type(8'd1);

            repeat (3) @(posedge clk);
            pulse_reset_and_clear_expected();  
        end

        // reset immediately 
        begin : dir_reconfig_neither
            pulse_reset_and_clear_expected();
        end

        // explicit idle reset 
        begin : dir_rst_idle_clean
            clear_config_input_bus();
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(2);
            repeat (2) @(posedge clk);
            pulse_reset_and_clear_expected();
        end

        // explicit reset while config valid/ready/tlast are high
        begin : dir_rst_at_tlast_clean
            clear_config_input_bus();
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(2);
            wait (config_in.tready);
            @(negedge clk);
            config_in.tdata  <= config_bus_data_stream[0];
            config_in.tkeep  <= config_bus_keep_stream[0];
            config_in.tlast  <= 1'b1;
            config_in.tvalid <= 1'b1;
            rst <= 1'b1;
            clear_expected_outputs();
            repeat (5) @(posedge clk);
            @(negedge clk);
            rst <= 1'b0;
            config_in.tvalid <= 1'b0;
            config_in.tlast  <= 1'b0;
            repeat (5) @(posedge clk);
        end

        // Restore DUT to fully configured state
        send_default_config_and_wait(5);

        // Directed one-per-class sweep so all 10 output classes because sometimes wouldn't get all 10
        begin : dir_output_all_classes
            $display("[%0t] directed one-per-class output sweep.", $realtime);
            for (int c = 0; c < 10; c++) begin
                if (class_cov_valid[c]) begin
                    drive_custom_image(total_tests, class_cov_img[c], 0, 0);
                    total_tests = total_tests + 1;
                    @(negedge clk);
                    clear_data_input_bus();
                end
            end
            $display("[%0t] Directed class sweep sent, waiting for outputs.", $realtime);
            wait_for_expected_outputs_to_drain(5);
        end

        // test to hit gap_2-10 bin of cg_data_in_inter_image_gap so get that range of idle cycles between one image tlast and before next image tvalid
        begin : dir_data_in_img_gap_2_10_safe
            $display("[%0t] directed data_in inter-image gap_2_10.", $realtime);
            drive_image(total_tests, 0 % num_tests, 0, 0);
            total_tests++;
            drive_image(total_tests, 1 % num_tests, 3, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);
        end

        // fake images to hit uniform/low/high spread bins
        begin : dir_input_diversity_made_up
            automatic bit [INPUT_DATA_WIDTH-1:0] img_uniform[];
            automatic bit [INPUT_DATA_WIDTH-1:0] img_low[];
            automatic bit [INPUT_DATA_WIDTH-1:0] img_high[];

            img_uniform = new[ACTUAL_TOPOLOGY[0]];
            img_low     = new[ACTUAL_TOPOLOGY[0]];
            img_high    = new[ACTUAL_TOPOLOGY[0]];

            for (int i = 0; i < ACTUAL_TOPOLOGY[0]; i++) begin
                img_uniform[i] = 8'd42;
                img_low[i]     = (i % 2) ? 8'd80 : 8'd40;
                img_high[i]    = (i % 2) ? 8'd255 : 8'd0;
            end

            $display("[%0t] directed made-up images input-diversity sweep.", $realtime);

            drive_custom_image(total_tests, img_uniform, 0, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);

            drive_custom_image(total_tests, img_low, 0, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);

            drive_custom_image(total_tests, img_high, 0, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            wait_for_expected_outputs_to_drain(5);
        end

        // cov_config_pattern: lots_stalls bin; force large_stall=1
        begin : dir_lots_stalls
            clear_data_input_bus();
            reset_and_reconfigure(1'b0, 1'b1, 1'b0);
        end

        // cov_config cp_keep partial_word: send a config beat with tkeep != 0xFF
        begin : dir_config_partial_keep
            rebuild_default_config_stream();
            // Force the last beat of the stream to have a partial keep
            config_bus_keep_stream[config_bus_data_stream.size()-1] = 8'h0F;
            for (int ci = 0; ci < config_bus_data_stream.size(); ci++) begin
                @(negedge clk);
                config_in.tdata  <= config_bus_data_stream[ci];
                config_in.tkeep  <= config_bus_keep_stream[ci];
                config_in.tlast  <= config_bus_tlast_stream[ci];
                config_in.tvalid <= 1'b1;
                @(posedge clk iff config_in.tready);
                @(negedge clk);
                config_in.tvalid <= 1'b0;
                config_in.tlast  <= 1'b0;
            end
            wait_for_input_ready(3);
        end

        // cov_data_in cp_keep partial_word: send one data_in beat with tkeep!=0xFF
        begin : dir_data_in_partial_keep
            automatic bit [INPUT_DATA_WIDTH-1:0] img_m[];
            stim.get_vector(0, img_m);

            @(negedge clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++)
                data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_m[k];
            data_in.tkeep  <= 8'h0F;   // only lower 4 bytes valid
            data_in.tvalid <= 1'b1;
            data_in.tlast  <= 1'b0;
            @(posedge clk iff data_in.tready);
            @(negedge clk);
            clear_data_input_bus();
            @(posedge clk);
            pulse_reset_and_clear_expected();
        end
        send_default_config_and_wait(3);

        // cg_config_inter_msg_gap back_to_back bin
        begin : dir_config_back_to_back
            pulse_reset_and_clear_expected();
            rebuild_default_config_stream();
            send_config_stream_back_to_back();
            wait_for_input_ready(3);
        end

        // cg_data_in_inter_image_gap back_to_back bin
        begin : dir_data_in_back_to_back
            drive_image_back_to_back(0);
            drive_image_back_to_back(1 % num_tests);
            total_tests += 2;
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);
        end

        // cg_output_tlast_bp had_bp_at_tlast bin
        begin : dir_output_tlast_bp
            force data_out.tready = 1'b0;
            drive_image(total_tests, 0, 0, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            @(posedge clk iff !rst && data_out.tvalid);
            // prev_data_out_ready=0 here so had_bp_at_tlast goes tru
            @(negedge clk);
            force data_out.tready = 1'b1;
            @(posedge clk iff data_out.tvalid && data_out.tready);
            @(negedge clk);
            release data_out.tready;
            repeat (2) @(posedge clk);
            wait_for_expected_outputs_to_drain(5);
        end

        // cg_data_in cp_burst_run run_513plus with six back-to-back images
        begin : dir_data_in_long_run
            for (int i = 0; i < 6; i++)
                drive_image_back_to_back(i % num_tests);
            total_tests += 6;
            @(negedge clk);
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);
        end

        // cg_data_in long gap bins and last-beat long gap bins
        begin : dir_data_in_long_gaps
            drive_image(total_tests, 0 % num_tests, 30, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            drive_image(total_tests, 1 % num_tests, 200, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            drive_image(total_tests, 2 % num_tests, 0, 30);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            drive_image(total_tests, 3 % num_tests, 0, 200);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            wait_for_expected_outputs_to_drain(5);
        end

        // cg_class repeat bins via a same-class burst
        begin : dir_class_repeat
            automatic int rep_idx;
            rep_idx = select_bp_stim_idx(0);

            for (int i = 0; i < 120; i++) begin
                drive_image(total_tests, rep_idx, 0, 0);
                total_tests++;
                @(negedge clk);
                clear_data_input_bus();
            end

            wait_for_expected_outputs_to_drain(5);
        end

        // cg_output class with backpressure using a stall
        begin : dir_output_class_bp
            for (int c = 0; c < 10; c++) begin
                if (class_cov_valid[c]) begin
                    run_output_hold_case_image(total_tests, class_cov_img[c], 40);
                    total_tests++;
                end
            end
        end

        // cg_output class with long wait timing
        begin : dir_output_class_long_wait
            for (int c = 0; c < 10; c++) begin
                if (class_cov_valid[c]) begin
                    run_output_hold_case_image(total_tests, class_cov_img[c], 150);
                    total_tests++;
                end
            end
        end

        // cg_data_in exact 1-cycle gap cross bins
        begin : dir_data_in_gap1_cross
            drive_image(total_tests, 0 % num_tests, 1, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            drive_image(total_tests, 1 % num_tests, 0, 1);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            wait_for_expected_outputs_to_drain(5);
        end

        // cg_output class with short wait timing
        begin : dir_output_class_wait1
            for (int c = 0; c < 10; c++) begin
                if (class_cov_valid[c]) begin
                    run_output_hold_case_image(total_tests, class_cov_img[c], 1);
                    total_tests++;
                end
            end
        end

        // cg_output class with very long wait timing
        begin : dir_output_class_wait750
            for (int c = 0; c < 10; c++) begin
                if (class_cov_valid[c]) begin
                    run_output_hold_case_image(total_tests, class_cov_img[c], 750);
                    total_tests++;
                end
            end
        end

        // cg_output with 251-500-cycle bp
        begin : dir_output_bp_350
            run_output_hold_case(total_tests, select_bp_stim_idx(0), 350);
            total_tests++;
        end

        // cg_data_in_inter_image_gap extra gap bins
        begin : dir_data_in_img_gap_more
            drive_image(total_tests, 0 % num_tests, 1, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            drive_image(total_tests, 1 % num_tests, 20, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            drive_image(total_tests, 2 % num_tests, 500, 0);
            total_tests++;
            @(negedge clk);
            clear_data_input_bus();

            wait_for_expected_outputs_to_drain(5);
        end

        // cg_scenarios reset_count 11plus
        begin : dir_many_resets
            for (int i = 0; i < 7; i++)
                pulse_reset_and_clear_expected();
            send_default_config_and_wait(3);
        end

        // cx_class_under_bp and cx_class_ready_timing
        begin : dir_class_cross_extra_stalls
            automatic int extra_stalls[4] = '{3, 8, 12, 60};
            $display("[%0t] directed extra per-class stall tests.", $realtime);
            for (int stall_idx = 0; stall_idx < 4; stall_idx++) begin
                for (int c = 0; c < 10; c++) begin
                    if (class_cov_valid[c]) begin
                        run_output_hold_case_image(total_tests, class_cov_img[c],
                                                        extra_stalls[stall_idx]);
                        total_tests++;
                    end
                end
            end
        end

        // cx_handshake_at_beat: valid_before_ready with last_beat
        begin : dir_data_in_last_beat_vbr
            automatic bit [INPUT_DATA_WIDTH-1:0] img_gg[];
            automatic int img_size;
            automatic int last_j;
            automatic int penult_j;

            $display("[%0t] directed valid_before_ready x last_beat test.", $realtime);

            stim.get_vector(0, img_gg);
            img_size = img_gg.size();
            last_j   = (img_size / INPUTS_PER_CYCLE - 1) * INPUTS_PER_CYCLE;
            penult_j = last_j - INPUTS_PER_CYCLE;

            expected_outputs.push_back(model.compute_reference(img_gg));
            total_tests++;

            for (int j = 0; j < penult_j; j += INPUTS_PER_CYCLE) begin
                @(negedge clk);
                for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_gg[j+k];
                    data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
                end
                data_in.tvalid <= 1'b1;
                data_in.tlast  <= 1'b0;
                @(posedge clk iff data_in.tready);
            end

            @(negedge clk);
            data_in.tvalid <= 1'b0;
            data_in.tlast  <= 1'b0;
            @(posedge clk);

            //almost last beat: force tready=0 so valid rises while tready=0
            @(negedge clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_gg[penult_j+k];
                data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
            end
            force data_in.tready = 1'b0;
            data_in.tvalid <= 1'b1;
            data_in.tlast  <= 1'b0;
            @(posedge clk);    
            @(negedge clk);
            release data_in.tready;
            @(posedge clk iff data_in.tready);

            @(negedge clk);
            data_in.tvalid <= 1'b0;
            data_in.tlast  <= 1'b0;
            @(posedge clk);   

            @(negedge clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                if (last_j+k < img_size)
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_gg[last_j+k];
                else
                    data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= '0;
                data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT] <=
                    (last_j+k < img_size) ? '1 : '0;
            end
            data_in.tvalid <= 1'b1;
            data_in.tlast  <= 1'b1;
            @(posedge clk iff data_in.tready);

            @(negedge clk);
            clear_data_input_bus();
            wait_for_expected_outputs_to_drain(5);
        end

        clear_data_input_bus();
        wait_for_expected_outputs_to_drain(5);

        // Final output backpressure sweep
        run_output_backpressure_tests();

        // cg_config_inter_msg_gap higher gap bins
        begin : dir_config_inter_msg_gap_high_bins
            automatic int gap_cases[3] = '{10, 30, 300};

            for (int gap_idx = 0; gap_idx < $size(gap_cases); gap_idx++) begin
                pulse_reset_and_clear_expected();
                rebuild_default_config_stream();
                send_config_stream_with_inter_msg_gap(gap_cases[gap_idx]);
                wait_for_input_ready(3);
            end
        end

        // cg_config_msg_length single_beat_msg bin with cx_len_x_type single_beat cross
        // Sends a one-beat config message for each msg type; header with tlast
        // The DUT treats this as a malformed/empty message so reset and reconfigure after
        begin : dir_single_beat_config_msgs
            $display("[%0t] directed single-beat config messages.", $realtime);

            // Type=0 (weights)
            pulse_reset_and_clear_expected();
            @(negedge clk);
            config_in.tdata  <= 64'h0000_0000_0000_0000;  // msg_type=0 (weights)
            config_in.tkeep  <= '1;
            config_in.tlast  <= 1'b1;
            config_in.tvalid <= 1'b1;
            @(posedge clk iff config_in.tready);
            @(negedge clk);
            config_in.tvalid <= 1'b0;
            config_in.tlast  <= 1'b0;
            pulse_reset_and_clear_expected();
            rebuild_default_config_stream();
            send_default_config_and_wait(3);

            // Type=1 (threshold)
            pulse_reset_and_clear_expected();
            @(negedge clk);
            config_in.tdata  <= 64'h0000_0000_0000_0001;  // msg_type=1 (threshold)
            config_in.tkeep  <= '1;
            config_in.tlast  <= 1'b1;
            config_in.tvalid <= 1'b1;
            @(posedge clk iff config_in.tready);
            @(negedge clk);
            config_in.tvalid <= 1'b0;
            config_in.tlast  <= 1'b0;
            pulse_reset_and_clear_expected();
            rebuild_default_config_stream();
            send_default_config_and_wait(3);
        end

$display("[%0t] Directed coverage phase complete.", $realtime);
        disable generate_clock;
        disable l_timeout;

        if (passed == total_tests)
            $display("[%0t] SUCCESS: all %0d tests completed successfully.", $realtime, total_tests);
        else
            $error("FAILED: %0d out of %0d tests failed.", failed, total_tests);
    end

    initial begin : l_toggle_ready
        data_out.tready <= 1'b1;
        @(posedge clk iff !rst);
        if (TOGGLE_DATA_OUT_READY) begin
            forever begin
                data_out.tready <= $urandom();
                @(posedge clk);
            end
        end else begin
            data_out.tready <= 1'b1;
        end
    end

    initial begin : l_output_monitor
        forever begin
            @(posedge clk iff data_out.tvalid && data_out.tready);
            if (PRINT_THROUGH_IMAGES) begin
                $display("[OUT_HS] t=%0t data=%0h last=%0b",
                         $time, data_out.tdata, data_out.tlast);
            end
            assert (expected_outputs.size() > 0)
            else $fatal(1, "No expected output for actual output");

            if (data_out.tdata == expected_outputs[0]) begin
                if (PRINT_THROUGH_IMAGES) begin
                    $display("[%0t] CORRECT: image %0d -> predicted = %0d, expected = %0d, pending = %0d",
                             $realtime, output_count, data_out.tdata, expected_outputs[0], expected_outputs.size());
                end else begin
                    $display("[%0t] PASSED: image %0d", $realtime, output_count);
                end
                passed++;
            end else begin
                failed++;
                if (PRINT_THROUGH_IMAGES) begin
                    $fatal("[%0t] INCORRECT: image %0d -> actual = %0d, expected = %0d, pending = %0d",
                           $realtime, output_count, data_out.tdata, expected_outputs[0], expected_outputs.size());
                end else begin
                    $fatal("[%0t] FAILED: image %0d", $realtime, output_count);
                end
            end

            sample_output_coverage(int'(data_out.tdata[3:0]));
            void'(expected_outputs.pop_front());
            output_count++;
        end
    end

    initial begin : l_timeout
        #TIMEOUT;
        $fatal(1, $sformatf("Simulation failed due to timeout of %0t.", TIMEOUT));
    end


endmodule
