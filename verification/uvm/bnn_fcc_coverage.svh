`ifndef _BNN_FCC_COVERAGE_SVH_
`define _BNN_FCC_COVERAGE_SVH_

class bnn_fcc_coverage extends uvm_component;
    `uvm_component_utils(bnn_fcc_coverage)

    bnn_fcc_uvm_cfg                              cfg;
    virtual axi4_stream_if #(CONFIG_BUS_WIDTH)   config_vif;
    virtual axi4_stream_if #(INPUT_BUS_WIDTH)    data_in_vif;
    virtual axi4_stream_if #(OUTPUT_BUS_WIDTH)   data_out_vif;

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
    int              pending_img_pixel_range_q[$];
    reset_scenario_e current_reset_scenario;
    bit              reconfig_after_reset;
    int              last_output_class;

    int              config_inter_msg_gap;
    bit              config_msg_gap_pending;
    bit              config_had_first_tlast;
    int              config_beat_in_msg;
    logic            prev_data_in_valid;
    bit              data_in_ready_at_valid_rise;
    int              data_in_inter_image_gap;
    bit              data_in_inter_image_gap_active;
    pixel_t          current_img_q[$];

    covergroup cg_config_bus;
        cp_valid_after_prev_not: coverpoint (prev_config_valid == 1'b0) {
            bins continuous                = {1'b0};
            bins prev_not_valid_then_valid = {1'b1};
        }

        cp_last: coverpoint config_vif.tlast {
            bins middle_of_stream = {1'b0};
            bins end_of_stream    = {1'b1};
        }

        cp_keep: coverpoint config_vif.tkeep {
            bins full_word    = {8'hFF};
            bins partial_word = default;
        }
    endgroup

    covergroup cg_config_msg_ordering;
        cp_msg_type: coverpoint config_vif.tdata[7:0] {
            bins weights   = {8'd0};
            bins threshold = {8'd1};
        }

        cp_prev_msg_type: coverpoint config_cur_msg_type {
            bins prev_weights    = {8'd0};
            bins prev_thresholds = {8'd1};
            bins first_message   = {8'hFF};
        }

        cx_msg_ordering: cross cp_prev_msg_type, cp_msg_type;

        cp_layer_id: coverpoint config_vif.tdata[15:8] {
            bins layer_0 = {8'd0};
            bins layer_1 = {8'd1};
            bins layer_2 = {8'd2};
        }

        cp_layer_order: coverpoint ((config_vif.tdata[15:8] > config_cur_layer_id) ? 2'b01 :
                                    (config_vif.tdata[15:8] < config_cur_layer_id) ? 2'b10 : 2'b00) {
            bins increased  = {2'b01};
            bins decreased  = {2'b10};
            bins same_layer = {2'b00};
        }

        cx_layer_msg: cross cp_layer_id, cp_msg_type {
            ignore_bins output_layer_threshold = binsof(cp_layer_id.layer_2) && binsof(cp_msg_type.threshold);
        }

        cp_dont_care_fields: coverpoint (config_vif.tdata[63:16] != '0) {
            bins nonzero = {1'b1};
        }
    endgroup

    covergroup cg_config_valid_pattern;
        cp_stalls_in_burst: coverpoint config_stalls_at_burst_end {
            bins zero          = {0};
            bins stalls_1_3    = {[1:3]};
            bins stalls_4_10   = {[4:10]};
            bins stalls_11_50  = {[11:50]};
            bins stalls_51_200 = {[51:200]};
        }
    endgroup

    covergroup cg_config_stall_position;
        cp_stall_beat: coverpoint config_beat_in_msg {
            bins header_beat  = {0};
            bins payload_beat = {[1:$]};
        }
    endgroup

    covergroup cg_config_inter_msg_gap;
        cp_gap: coverpoint config_inter_msg_gap {
            bins back_to_back = {0};
            bins gap_1        = {1};
            bins gap_2_5      = {[2:5]};
            bins gap_6_20     = {[6:20]};
            bins gap_21_100   = {[21:100]};
            bins gap_101_500  = {[101:500]};
        }
        cp_next_msg_type: coverpoint config_vif.tdata[7:0] {
            bins weights   = {8'd0};
            bins threshold = {8'd1};
        }
        cx_gap_x_type: cross cp_gap, cp_next_msg_type;
    endgroup

    covergroup cg_config_msg_length;
        cp_single_beat: coverpoint config_vif.tlast {
            bins single_beat_msg = {1'b1};
            bins multi_beat_msg  = {1'b0};
        }
        cp_msg_type: coverpoint config_vif.tdata[7:0] {
            bins weights   = {8'd0};
            bins threshold = {8'd1};
        }
        cx_len_x_type: cross cp_single_beat, cp_msg_type;
    endgroup

    covergroup cg_config_keep_last;
        cp_keep: coverpoint config_vif.tkeep {
            bins full_word    = {8'hFF};
            bins partial_word = default;
        }
        cp_last: coverpoint config_vif.tlast {
            bins not_last = {1'b0};
            bins is_last  = {1'b1};
        }
        cx_keep_x_last: cross cp_keep, cp_last;
    endgroup

    covergroup cg_data_in_bus;
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

        cp_last_beat: coverpoint data_in_vif.tlast {
            bins not_last = {1'b0};
            bins last     = {1'b1};
        }

        cx_gap_at_last: cross cp_gap_len, cp_last_beat {
            ignore_bins common = binsof(cp_gap_len.no_gap) && binsof(cp_last_beat.not_last);
        }

        cp_pixel_content: coverpoint count_zero_bytes(data_in_vif.tdata) {
            bins all_zero = {8};
            bins all_F    = {0};
            bins mixed    = {[1:7]};
        }

        cp_keep: coverpoint data_in_vif.tkeep {
            bins full_word    = {8'hFF};
            bins partial_word = default;
        }
    endgroup

    covergroup cg_output_bus;
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

        cp_output_class: coverpoint data_out_vif.tdata[3:0] {
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

    covergroup cg_output_tlast_bp;
        cp_bp_at_tlast: coverpoint (prev_data_out_ready == 1'b0) {
            bins no_bp_at_last   = {1'b0};
            bins had_bp_at_tlast = {1'b1};
        }
    endgroup

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
            bins one_reset    = {1};
            bins resets_2_4   = {[2:4]};
            bins resets_5_10  = {[5:10]};
            bins resets_11plus = {[11:$]};
        }

        cp_reconfig_type: coverpoint {seen_thresh_after_reset, seen_weight_after_reset} {
            bins neither         = {2'b00};
            bins weights_only    = {2'b01};
            bins thresholds_only = {2'b10};
            bins both            = {2'b11};
        }

        cp_reset_at_tlast: coverpoint (config_vif.tvalid && config_vif.tready && config_vif.tlast) {
            bins not_at_tlast = {1'b0};
            bins at_tlast     = {1'b1};
        }
    endgroup

    covergroup cg_data_in_handshake_order;
        cp_ready_when_valid_rose: coverpoint data_in_ready_at_valid_rise {
            bins ready_before_valid = {1'b1};
            bins valid_before_ready = {1'b0};
        }
        cp_beat_position: coverpoint data_in_vif.tlast {
            bins mid_image = {1'b0};
            bins last_beat = {1'b1};
        }
        cx_handshake_at_beat: cross cp_ready_when_valid_rose, cp_beat_position;
    endgroup

    covergroup cg_data_in_inter_image_gap;
        cp_gap: coverpoint data_in_inter_image_gap {
            bins back_to_back = {0};
            bins gap_1        = {1};
            bins gap_2_10     = {[2:10]};
            bins gap_11_50    = {[11:50]};
            bins gap_51_200   = {[51:200]};
            bins gap_201_1k   = {[201:1000]};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_config_bus            = new();
        cg_config_valid_pattern  = new();
        cg_config_msg_ordering   = new();
        cg_config_stall_position = new();
        cg_config_inter_msg_gap  = new();
        cg_config_msg_length     = new();
        cg_config_keep_last      = new();
        cg_data_in_bus           = new();
        cg_data_in_handshake_order = new();
        cg_data_in_inter_image_gap = new();
        cg_output_bus            = new();
        cg_output_tlast_bp       = new();
        cg_input_diversity       = new();
        cg_scenarios             = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(bnn_fcc_uvm_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("NO_CFG", "Could not get bnn_fcc_uvm_cfg.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(CONFIG_BUS_WIDTH))::get(this, "", "config_vif", config_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get config_vif.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(INPUT_BUS_WIDTH))::get(this, "", "data_in_vif", data_in_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get data_in_vif.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(OUTPUT_BUS_WIDTH))::get(this, "", "data_out_vif", data_out_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get data_out_vif.")
        end
        reset_tracking_state();
        reset_count          = 0;
        reconfig_after_reset = 1'b0;
        img_pixel_range      = 0;
        last_output_class    = -1;
    endfunction

    function automatic int count_zero_bytes(input logic [INPUT_BUS_WIDTH-1:0] d);
        int n;
        n = 0;
        for (int i = 0; i < INPUT_BUS_WIDTH/8; i++) begin
            if (d[i*8+:8] == 8'h00) n++;
        end
        return n;
    endfunction

    function automatic int compute_pixel_range(input int pmin, input int pmax);
        int spread;
        spread = pmax - pmin;
        if (spread < 32) return 0;
        if (spread < 128) return 1;
        return 2;
    endfunction

    function void reset_tracking_state();
        prev_config_valid             = 1'b0;
        prev_tlast_accepted           = 1'b1;
        config_cur_msg_type           = 8'hFF;
        config_cur_layer_id           = 8'hFF;
        prev_data_out_ready           = 1'b1;
        data_out_valid_wait           = 0;
        config_stalls_this_burst      = 0;
        config_stalls_at_burst_end    = 0;
        data_in_burst_run             = 0;
        data_in_gap_len               = 0;
        data_out_stall_count          = 0;
        partial_config_sent           = 1'b0;
        config_load_done              = 1'b0;
        seen_weight_after_reset       = 1'b0;
        seen_thresh_after_reset       = 1'b0;
        config_inter_msg_gap          = 0;
        config_msg_gap_pending        = 1'b0;
        config_had_first_tlast        = 1'b0;
        config_beat_in_msg            = 0;
        prev_data_in_valid            = 1'b0;
        data_in_ready_at_valid_rise   = 1'b0;
        data_in_inter_image_gap       = 0;
        data_in_inter_image_gap_active = 1'b0;
        current_img_q.delete();
        pending_img_pixel_range_q.delete();
    endfunction

    task push_input_pixels_from_beat();
        int pmin;
        int pmax;

        for (int lane = 0; lane < INPUTS_PER_CYCLE; lane++) begin
            if (data_in_vif.tkeep[lane*BYTES_PER_INPUT+:BYTES_PER_INPUT] != '0) begin
                current_img_q.push_back(data_in_vif.tdata[lane*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH]);
            end
        end

        if (data_in_vif.tlast) begin
            pmin = 255;
            pmax = 0;
            foreach (current_img_q[i]) begin
                if (int'(current_img_q[i]) < pmin) pmin = int'(current_img_q[i]);
                if (int'(current_img_q[i]) > pmax) pmax = int'(current_img_q[i]);
            end
            if (current_img_q.size() != 0) begin
                pending_img_pixel_range_q.push_back(compute_pixel_range(pmin, pmax));
            end
            current_img_q.delete();
        end
    endtask

    task sample_output_diversity(input int cur_class);
        last_output_class = cur_class;
        if (pending_img_pixel_range_q.size() != 0) begin
            img_pixel_range = pending_img_pixel_range_q.pop_front();
            cg_input_diversity.sample();
        end
    endtask

    task monitor_reset_assertions();
        forever begin
            @(negedge config_vif.aresetn);
            reset_count = reset_count + 1;

            if (config_vif.tvalid || partial_config_sent) begin
                current_reset_scenario = RST_DURING_CONFIG;
            end else if (data_in_vif.tvalid) begin
                current_reset_scenario = RST_DURING_INPUT;
            end else if (data_out_vif.tvalid) begin
                current_reset_scenario = RST_DURING_OUTPUT;
            end else begin
                current_reset_scenario = RST_IDLE;
            end

            reconfig_after_reset = config_load_done;
            cg_scenarios.sample();
        end
    endtask

    task track_state();
        forever begin
            @(posedge config_vif.aclk);

            if (!config_vif.aresetn) begin
                reset_tracking_state();
                continue;
            end

            if (config_vif.tvalid && !prev_config_valid) begin
                cg_config_valid_pattern.sample();
            end
            if (config_vif.tvalid && !config_vif.tready) begin
                cg_config_stall_position.sample();
            end
            if (config_msg_gap_pending && config_vif.tvalid) begin
                cg_config_inter_msg_gap.sample();
            end
            if (config_vif.tvalid && config_vif.tready) begin
                cg_config_bus.sample();
                cg_config_keep_last.sample();
                if (prev_tlast_accepted) begin
                    cg_config_msg_ordering.sample();
                    cg_config_msg_length.sample();
                end
            end

            if (data_in_vif.tvalid && !prev_data_in_valid) begin
                cg_data_in_handshake_order.sample();
            end
            if (data_in_inter_image_gap_active && data_in_vif.tvalid) begin
                cg_data_in_inter_image_gap.sample();
            end
            if (data_in_vif.tvalid && data_in_vif.tready) begin
                cg_data_in_bus.sample();
            end

            if (data_out_vif.tvalid && data_out_vif.tready) begin
                cg_output_bus.sample();
                cg_output_tlast_bp.sample();
                sample_output_diversity(int'(data_out_vif.tdata[OUTPUT_DATA_WIDTH-1:0]));
            end

            if (data_in_vif.tvalid && data_in_vif.tready) begin
                push_input_pixels_from_beat();
            end

            if (config_vif.tvalid && !config_vif.tready) begin
                config_stalls_this_burst = config_stalls_this_burst + 1;
            end else if (!config_vif.tvalid) begin
                if (prev_config_valid) begin
                    config_stalls_at_burst_end = config_stalls_this_burst;
                end
                config_stalls_this_burst = 0;
            end

            if (config_vif.tvalid && config_vif.tready) begin
                partial_config_sent = ~config_vif.tlast;
                if (config_vif.tlast) config_load_done = 1'b1;
            end

            if (config_vif.tvalid && config_vif.tready) begin
                if (prev_tlast_accepted) begin
                    config_cur_msg_type = config_vif.tdata[7:0];
                    config_cur_layer_id = config_vif.tdata[15:8];
                end
                prev_tlast_accepted = config_vif.tlast;
            end

            if (config_vif.tvalid && config_vif.tready && prev_tlast_accepted) begin
                if (config_vif.tdata[7:0] == 8'd0) seen_weight_after_reset = 1'b1;
                if (config_vif.tdata[7:0] == 8'd1) seen_thresh_after_reset = 1'b1;
            end

            if (data_in_vif.tvalid && data_in_vif.tready) begin
                data_in_burst_run = data_in_burst_run + 1;
                data_in_gap_len   = 0;
            end else if (!data_in_vif.tvalid) begin
                data_in_burst_run = 0;
                data_in_gap_len   = data_in_gap_len + 1;
            end

            if (data_out_vif.tvalid && !data_out_vif.tready) begin
                data_out_stall_count = data_out_stall_count + 1;
                data_out_valid_wait  = data_out_valid_wait + 1;
            end else if (data_out_vif.tvalid && data_out_vif.tready) begin
                data_out_stall_count = 0;
                data_out_valid_wait  = 0;
            end

            if (config_vif.tvalid && config_vif.tready && config_vif.tlast) begin
                config_had_first_tlast = 1'b1;
                if (config_had_first_tlast) begin
                    config_msg_gap_pending = 1'b1;
                    config_inter_msg_gap   = 0;
                end
            end else if (config_msg_gap_pending) begin
                if (!config_vif.tvalid) begin
                    config_inter_msg_gap = config_inter_msg_gap + 1;
                end else begin
                    config_msg_gap_pending = 1'b0;
                end
            end

            if (config_vif.tvalid && config_vif.tready && config_vif.tlast) begin
                config_beat_in_msg = 0;
            end else if (config_vif.tvalid && config_vif.tready) begin
                config_beat_in_msg = config_beat_in_msg + 1;
            end

            if (data_in_vif.tvalid && !prev_data_in_valid) begin
                data_in_ready_at_valid_rise = data_in_vif.tready;
            end

            if (data_in_vif.tvalid && data_in_vif.tready && data_in_vif.tlast) begin
                data_in_inter_image_gap_active = 1'b1;
                data_in_inter_image_gap        = 0;
            end else if (data_in_inter_image_gap_active) begin
                if (!data_in_vif.tvalid) begin
                    data_in_inter_image_gap = data_in_inter_image_gap + 1;
                end else begin
                    data_in_inter_image_gap_active = 1'b0;
                end
            end

            prev_config_valid   = config_vif.tvalid;
            prev_data_out_ready = data_out_vif.tready;
            prev_data_in_valid  = data_in_vif.tvalid;
        end
    endtask

    task run_phase(uvm_phase phase);
        fork
            monitor_reset_assertions();
            track_state();
        join
    endtask
endclass

`endif
