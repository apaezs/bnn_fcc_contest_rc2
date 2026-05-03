`ifndef _BNN_FCC_BASE_TEST_SVH_
`define _BNN_FCC_BASE_TEST_SVH_

class bnn_fcc_base_test extends uvm_test;
    `uvm_component_utils(bnn_fcc_base_test)

    bnn_fcc_env                                 env;
    bnn_fcc_uvm_cfg                             cfg;
    virtual bnn_fcc_ctrl_if                     ctrl_vif;
    virtual axi4_stream_if #(CONFIG_BUS_WIDTH)  config_vif;
    virtual axi4_stream_if #(INPUT_BUS_WIDTH)   data_in_vif;
    virtual axi4_stream_if #(OUTPUT_BUS_WIDTH)  data_out_vif;

    int tb_img_idx_counter;

    function new(string name = "bnn_fcc_base_test", uvm_component parent = null);
        super.new(name, parent);
        tb_img_idx_counter = 0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(bnn_fcc_uvm_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("NO_CFG", "Could not get bnn_fcc_uvm_cfg.")
        end
        if (!uvm_config_db#(virtual bnn_fcc_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get ctrl_vif.")
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

        env = bnn_fcc_env::type_id::create("env", this);
    endfunction

    function automatic bit chance(real p);
        if (p > 1.0 || p < 0.0) begin
            `uvm_fatal("BAD_PROB", $sformatf("Invalid probability %0f", p))
        end
        return ($urandom < (p * (2.0 ** 32)));
    endfunction

    task clear_config_input_bus();
        config_vif.tvalid <= 1'b0;
        config_vif.tlast  <= 1'b0;
        config_vif.tkeep  <= '0;
        config_vif.tdata  <= '0;
    endtask

    task clear_data_input_bus();
        data_in_vif.tvalid <= 1'b0;
        data_in_vif.tlast  <= 1'b0;
        data_in_vif.tkeep  <= '0;
        data_in_vif.tdata  <= '0;
    endtask

    task verify_model();
        BNN_FCC_Stimulus#(INPUT_DATA_WIDTH) stim_verify;
        int                                 python_preds[];
        pixel_t                             current_img[];
        int                                 sv_pred;
        string                              input_path;
        string                              output_path;

        input_path  = $sformatf("%s/%s", cfg.base_dir, cfg.mnist_input_path);
        output_path = $sformatf("%s/%s", cfg.base_dir, cfg.mnist_output_path);

        stim_verify = new(cfg.actual_topology[0]);
        stim_verify.load_from_file(input_path);

        python_preds = new[stim_verify.get_num_vectors()];
        $readmemh(output_path, python_preds);

        for (int i = 0; i < stim_verify.get_num_vectors(); i++) begin
            stim_verify.get_vector(i, current_img);
            sv_pred = cfg.model.compute_reference(current_img);
            if (sv_pred !== python_preds[i]) begin
                `uvm_fatal("MODEL_MISMATCH", $sformatf("Img %0d: SV model=%0d Python=%0d", i, sv_pred, python_preds[i]))
            end
        end

        `uvm_info(get_type_name(), "SV reference model verified against expected_outputs.txt.", UVM_LOW)
    endtask

    task inject_reserved_garbage();
        for (int i = 0; i < cfg.config_bus_data_stream.size(); i++) begin
            if ((i == 0 || cfg.config_bus_tlast_stream[i-1]) && (i + 1 < cfg.config_bus_data_stream.size())) begin
                cfg.config_bus_data_stream[i+1][63:32] = 32'hDEAD_BEEF;
            end
        end
    endtask

    task compute_config_tlast();
        bit [CONFIG_BUS_WIDTH-1:0]   msg_stream[];
        bit [CONFIG_BUS_WIDTH/8-1:0] msg_keep[];
        bit                          msg_tlast[];

        cfg.config_bus_tlast_stream = new[0];
        for (int l = 0; l < cfg.model.num_layers; l++) begin
            cfg.model.get_layer_config(l, 0, msg_stream, msg_keep);
            msg_tlast = new[msg_stream.size()];
            foreach (msg_tlast[i]) msg_tlast[i] = (i == msg_stream.size() - 1);
            cfg.config_bus_tlast_stream = {cfg.config_bus_tlast_stream, msg_tlast};

            if (l < cfg.model.num_layers - 1) begin
                cfg.model.get_layer_config(l, 1, msg_stream, msg_keep);
                msg_tlast = new[msg_stream.size()];
                foreach (msg_tlast[i]) msg_tlast[i] = (i == msg_stream.size() - 1);
                cfg.config_bus_tlast_stream = {cfg.config_bus_tlast_stream, msg_tlast};
            end
        end
    endtask

    task rebuild_default_config_stream();
        cfg.model.encode_configuration(cfg.config_bus_data_stream, cfg.config_bus_keep_stream);
        compute_config_tlast();
        inject_reserved_garbage();
    endtask

    task reorder_config_stream_of_type_first(input bit [7:0] first_type);
        int            chunk_starts[$];
        int            chunk_sizes[$];
        bit [7:0]      chunk_types[$];
        config_word_t  new_data[];
        config_keep_t  new_keep[];
        bit            new_tlast[];
        int            total;
        int            idx;

        total = cfg.config_bus_data_stream.size();
        idx   = 0;

        for (int i = 0; i < total; i++) begin
            if (i == 0 || cfg.config_bus_tlast_stream[i-1]) begin
                chunk_starts.push_back(i);
                chunk_types.push_back(cfg.config_bus_data_stream[i][7:0]);
            end
        end

        for (int c = 0; c < chunk_starts.size(); c++) begin
            int next_start;
            next_start = (c + 1 < chunk_starts.size()) ? chunk_starts[c+1] : total;
            chunk_sizes.push_back(next_start - chunk_starts[c]);
        end

        new_data  = new[total];
        new_keep  = new[total];
        new_tlast = new[total];

        foreach (chunk_starts[c]) begin
            if (chunk_types[c] == first_type) begin
                for (int i = 0; i < chunk_sizes[c]; i++) begin
                    new_data[idx]  = cfg.config_bus_data_stream[chunk_starts[c] + i];
                    new_keep[idx]  = cfg.config_bus_keep_stream[chunk_starts[c] + i];
                    new_tlast[idx] = cfg.config_bus_tlast_stream[chunk_starts[c] + i];
                    idx++;
                end
            end
        end

        foreach (chunk_starts[c]) begin
            if (chunk_types[c] != first_type) begin
                for (int i = 0; i < chunk_sizes[c]; i++) begin
                    new_data[idx]  = cfg.config_bus_data_stream[chunk_starts[c] + i];
                    new_keep[idx]  = cfg.config_bus_keep_stream[chunk_starts[c] + i];
                    new_tlast[idx] = cfg.config_bus_tlast_stream[chunk_starts[c] + i];
                    idx++;
                end
            end
        end

        cfg.config_bus_data_stream  = new_data;
        cfg.config_bus_keep_stream  = new_keep;
        cfg.config_bus_tlast_stream = new_tlast;
    endtask

    task reorder_config_stream_weights_first();
        reorder_config_stream_of_type_first(8'd0);
    endtask

    task reorder_config_stream_threshold_first();
        reorder_config_stream_of_type_first(8'd1);
    endtask

    task build_class_example_index();
        BNN_FCC_Stimulus#(INPUT_DATA_WIDTH) stim_all;
        pixel_t                             sample_img[];
        int                                 pred_class;
        int                                 missing_classes;
        string                              input_path;

        for (int class_id = 0; class_id < 10; class_id++) begin
            cfg.class_example_idx[class_id]   = -1;
            cfg.class_example_valid[class_id] = 1'b0;
            cfg.class_cov_valid[class_id]     = 1'b0;
        end

        for (int stim_idx = 0; stim_idx < cfg.num_tests; stim_idx++) begin
            cfg.stim.get_vector(stim_idx, sample_img);
            pred_class = cfg.model.compute_reference(sample_img);
            if (pred_class >= 0 && pred_class < 10 && !cfg.class_example_valid[pred_class]) begin
                cfg.class_example_idx[pred_class]   = stim_idx;
                cfg.class_example_valid[pred_class] = 1'b1;
                cfg.class_cov_img[pred_class]       = sample_img;
                cfg.class_cov_valid[pred_class]     = 1'b1;
            end
        end

        missing_classes = 0;
        for (int class_id = 0; class_id < 10; class_id++) begin
            if (!cfg.class_cov_valid[class_id]) missing_classes++;
        end

        if (missing_classes > 0 && !cfg.use_custom_topology) begin
            input_path = $sformatf("%s/%s", cfg.base_dir, cfg.mnist_input_path);
            stim_all   = new(cfg.actual_topology[0]);
            stim_all.load_from_file(input_path);

            for (int stim_idx = 0; stim_idx < stim_all.get_num_vectors() && missing_classes > 0; stim_idx++) begin
                stim_all.get_vector(stim_idx, sample_img);
                pred_class = cfg.model.compute_reference(sample_img);
                if (pred_class >= 0 && pred_class < 10 && !cfg.class_cov_valid[pred_class]) begin
                    cfg.class_cov_img[pred_class]   = sample_img;
                    cfg.class_cov_valid[pred_class] = 1'b1;
                    missing_classes--;
                end
            end
        end
    endtask

    function int select_bp_stim_idx(input int slot);
        for (int offset = 0; offset < 10; offset++) begin
            int class_id;
            class_id = (slot + offset) % 10;
            if (cfg.class_example_valid[class_id]) begin
                return cfg.class_example_idx[class_id];
            end
        end
        return (cfg.num_tests > 0) ? (slot % cfg.num_tests) : 0;
    endfunction

    task initialize_model_and_stimulus();
        string path;

        cfg.model = new();
        cfg.stim  = new(cfg.actual_topology[0]);

        if (!cfg.use_custom_topology) begin
            path = $sformatf("%s/%s", cfg.base_dir, cfg.mnist_model_data_path);
            cfg.model.load_from_file(path, cfg.actual_topology);
            if (cfg.verify_model) verify_model();
            rebuild_default_config_stream();

            path = $sformatf("%s/%s", cfg.base_dir, cfg.mnist_input_path);
            cfg.stim.load_from_file(path, cfg.num_test_images);
        end else begin
            cfg.model.create_random(cfg.actual_topology);
            rebuild_default_config_stream();
            cfg.stim.generate_random_vectors(cfg.num_test_images);
        end

        cfg.num_tests   = cfg.stim.get_num_vectors();
        cfg.total_tests = cfg.num_tests + cfg.directed_tests();

        cfg.model.print_summary();
        build_class_example_index();
        if (cfg.debug) cfg.model.print_model();
    endtask

    task pulse_reset();
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b1;
        repeat (5) @(posedge ctrl_vif.clk);
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b0;
        repeat (5) @(posedge ctrl_vif.clk);
    endtask

    task wait_for_input_ready(input int settle_cycles);
        wait (data_in_vif.tready);
        repeat (settle_cycles) @(posedge ctrl_vif.clk);
    endtask

    task wait_for_expected_outputs_to_drain(input int settle_cycles);
        wait (env.scoreboard.get_pending_count() == 0);
        repeat (settle_cycles) @(posedge ctrl_vif.clk);
    endtask

    task start_config_sequence(
        input config_word_t beat_data[],
        input config_keep_t beat_keep[],
        input bit           beat_last[],
        input int           gap_before[]
    );
        bnn_fcc_axi_beat_sequence #(CONFIG_BUS_WIDTH) seq;
        seq            = bnn_fcc_axi_beat_sequence #(CONFIG_BUS_WIDTH)::type_id::create($sformatf("cfg_seq_%0d", $urandom));
        seq.vif        = config_vif;
        seq.beat_data  = beat_data;
        seq.beat_keep  = beat_keep;
        seq.beat_last  = beat_last;
        seq.gap_before = gap_before;
        seq.start(env.config_agent.sequencer);
    endtask

    task start_data_sequence(
        input input_word_t beat_data[],
        input input_keep_t beat_keep[],
        input bit          beat_last[],
        input int          gap_before[]
    );
        bnn_fcc_axi_beat_sequence #(INPUT_BUS_WIDTH) seq;
        seq            = bnn_fcc_axi_beat_sequence #(INPUT_BUS_WIDTH)::type_id::create($sformatf("data_seq_%0d", $urandom));
        seq.vif        = data_in_vif;
        seq.beat_data  = beat_data;
        seq.beat_keep  = beat_keep;
        seq.beat_last  = beat_last;
        seq.gap_before = gap_before;
        seq.start(env.data_in_agent.sequencer);
    endtask

    task send_config_stream(input bit force_large_gap, input bit force_large_stall);
        int gaps[];
        int large_gap_beat;
        int large_stall_tlast;

        gaps = new[cfg.config_bus_data_stream.size()];
        foreach (gaps[i]) gaps[i] = 0;

        large_gap_beat = (force_large_gap && cfg.config_bus_data_stream.size() > 1) ? 1 : -1;
        large_stall_tlast = -1;
        if (force_large_stall) begin
            for (int i = 0; i < cfg.config_bus_data_stream.size() - 1; i++) begin
                if (cfg.config_bus_tlast_stream[i]) begin
                    large_stall_tlast = i;
                    break;
                end
            end
        end

        for (int i = 0; i < cfg.config_bus_data_stream.size(); i++) begin
            int gap_cycles;
            gap_cycles = 0;
            if (i == large_gap_beat) gap_cycles += 15;
            if (i == large_stall_tlast + 1) gap_cycles += 0;
            while (!chance(cfg.config_valid_probability)) gap_cycles++;
            gaps[i] = gap_cycles;
        end

        start_config_sequence(cfg.config_bus_data_stream, cfg.config_bus_keep_stream, cfg.config_bus_tlast_stream, gaps);
    endtask

    task send_default_config_and_wait(input int settle_cycles);
        send_config_stream(1'b0, 1'b0);
        wait_for_input_ready(settle_cycles);
    endtask

    task send_config_stream_back_to_back();
        int gaps[];
        gaps = new[cfg.config_bus_data_stream.size()];
        foreach (gaps[i]) gaps[i] = 0;
        start_config_sequence(cfg.config_bus_data_stream, cfg.config_bus_keep_stream, cfg.config_bus_tlast_stream, gaps);
    endtask

    task send_config_stream_with_inter_msg_gap(input int gap_cycles);
        int gaps[];
        gaps = new[cfg.config_bus_data_stream.size()];
        foreach (gaps[i]) gaps[i] = 0;

        for (int i = 1; i < cfg.config_bus_data_stream.size(); i++) begin
            if (cfg.config_bus_tlast_stream[i-1]) gaps[i] = gap_cycles;
        end

        start_config_sequence(cfg.config_bus_data_stream, cfg.config_bus_keep_stream, cfg.config_bus_tlast_stream, gaps);
    endtask

    task send_config_packets_of_type(input bit [7:0] msg_type);
        int           indices[$];
        config_word_t sel_data[];
        config_keep_t sel_keep[];
        bit           sel_last[];
        int           gaps[];
        int           i;

        i = 0;
        while (i < cfg.config_bus_data_stream.size()) begin
            if (cfg.config_bus_data_stream[i][7:0] == msg_type) begin
                do begin
                    indices.push_back(i);
                end while (!cfg.config_bus_tlast_stream[i++]);
            end else begin
                while (!cfg.config_bus_tlast_stream[i]) i++;
                i++;
            end
        end

        sel_data = new[indices.size()];
        sel_keep = new[indices.size()];
        sel_last = new[indices.size()];
        gaps     = new[indices.size()];

        foreach (indices[k]) begin
            sel_data[k] = cfg.config_bus_data_stream[indices[k]];
            sel_keep[k] = cfg.config_bus_keep_stream[indices[k]];
            sel_last[k] = cfg.config_bus_tlast_stream[indices[k]];
            gaps[k]     = 0;
        end

        start_config_sequence(sel_data, sel_keep, sel_last, gaps);
    endtask

    task build_image_beats(
        input pixel_t     img[],
        input int         gap_before_image_cycles,
        input int         gap_before_last_cycles,
        input bit         use_random_gaps,
        output input_word_t beat_data[],
        output input_keep_t beat_keep[],
        output bit          beat_last[],
        output int          gap_before[]
    );
        int n_beats;

        n_beats     = (img.size() + INPUTS_PER_CYCLE - 1) / INPUTS_PER_CYCLE;
        beat_data   = new[n_beats];
        beat_keep   = new[n_beats];
        beat_last   = new[n_beats];
        gap_before  = new[n_beats];

        for (int beat = 0; beat < n_beats; beat++) begin
            beat_data[beat] = '0;
            beat_keep[beat] = '0;
            beat_last[beat] = (beat == n_beats - 1);
            gap_before[beat] = 0;

            if (beat == 0) gap_before[beat] += gap_before_image_cycles;
            if (beat == n_beats - 1) gap_before[beat] += gap_before_last_cycles;
            if (use_random_gaps) begin
                while (!chance(cfg.data_in_valid_probability)) gap_before[beat]++;
            end

            for (int lane = 0; lane < INPUTS_PER_CYCLE; lane++) begin
                int idx;
                idx = beat * INPUTS_PER_CYCLE + lane;
                if (idx < img.size()) begin
                    beat_data[beat][lane*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] = img[idx];
                    beat_keep[beat][lane*BYTES_PER_INPUT+:BYTES_PER_INPUT]   = '1;
                end
            end
        end
    endtask

    task drive_image(
        input int tb_img_idx,
        input int stim_idx,
        input int gap_before_image_cycles,
        input int gap_before_last_cycles
    );
        pixel_t       current_img[];
        input_word_t  beat_data[];
        input_keep_t  beat_keep[];
        bit           beat_last[];
        int           gap_before[];

        cfg.stim.get_vector(stim_idx, current_img);
        build_image_beats(current_img, gap_before_image_cycles, gap_before_last_cycles, 1'b1, beat_data, beat_keep, beat_last, gap_before);

        if (cfg.print_through_images) begin
            `uvm_info(get_type_name(), $sformatf("Streaming image %0d using stimulus %0d.", tb_img_idx, stim_idx), UVM_LOW)
        end
        start_data_sequence(beat_data, beat_keep, beat_last, gap_before);
    endtask

    task drive_image_back_to_back(input int stim_idx);
        pixel_t       current_img[];
        input_word_t  beat_data[];
        input_keep_t  beat_keep[];
        bit           beat_last[];
        int           gap_before[];

        cfg.stim.get_vector(stim_idx, current_img);
        build_image_beats(current_img, 0, 0, 1'b0, beat_data, beat_keep, beat_last, gap_before);
        start_data_sequence(beat_data, beat_keep, beat_last, gap_before);
    endtask

    task drive_custom_image(
        input int      tb_img_idx,
        input pixel_t  custom_img[],
        input int      gap_before_image_cycles,
        input int      gap_before_last_cycles
    );
        input_word_t beat_data[];
        input_keep_t beat_keep[];
        bit          beat_last[];
        int          gap_before[];

        build_image_beats(custom_img, gap_before_image_cycles, gap_before_last_cycles, 1'b1, beat_data, beat_keep, beat_last, gap_before);

        if (cfg.print_through_images) begin
            `uvm_info(get_type_name(), $sformatf("Streaming custom image %0d.", tb_img_idx), UVM_LOW)
        end
        start_data_sequence(beat_data, beat_keep, beat_last, gap_before);
    endtask

    task reset_and_reconfigure(
        input bit force_large_gap,
        input bit force_large_stall,
        input bit force_threshold_first
    );
        pulse_reset();
        rebuild_default_config_stream();
        if (force_threshold_first) begin
            reorder_config_stream_threshold_first();
        end else if (cfg.alt_config_ordering) begin
            static bit alt_ordering;
            alt_ordering = ~alt_ordering;
            if (alt_ordering) reorder_config_stream_weights_first();
        end
        send_config_stream(force_large_gap, force_large_stall);
        wait_for_input_ready(5);
    endtask

    task run_output_hold_case(input int tb_img_idx, input int stim_idx, input int stall_cycles);
        if (stall_cycles <= 0) begin
            env.ready_ctrl.set_manual_ready(1'b1);
            drive_image(tb_img_idx, stim_idx, 0, 0);
            wait_for_expected_outputs_to_drain(5);
            env.ready_ctrl.release_manual();
            return;
        end

        env.ready_ctrl.set_manual_ready(1'b0);
        drive_image(tb_img_idx, stim_idx, 0, 0);

        @(posedge ctrl_vif.clk iff !ctrl_vif.rst && data_out_vif.tvalid);
        if (stall_cycles > 1) begin
            repeat (stall_cycles - 1) @(posedge ctrl_vif.clk iff !ctrl_vif.rst && data_out_vif.tvalid);
        end

        env.ready_ctrl.set_manual_ready(1'b1);
        wait_for_expected_outputs_to_drain(5);
        env.ready_ctrl.release_manual();
    endtask

    task run_output_hold_case_image(
        input int     tb_img_idx,
        input pixel_t custom_img[],
        input int     stall_cycles
    );
        if (stall_cycles <= 0) begin
            env.ready_ctrl.set_manual_ready(1'b1);
            drive_custom_image(tb_img_idx, custom_img, 0, 0);
            wait_for_expected_outputs_to_drain(5);
            env.ready_ctrl.release_manual();
            return;
        end

        env.ready_ctrl.set_manual_ready(1'b0);
        drive_custom_image(tb_img_idx, custom_img, 0, 0);

        @(posedge ctrl_vif.clk iff !ctrl_vif.rst && data_out_vif.tvalid);
        if (stall_cycles > 1) begin
            repeat (stall_cycles - 1) @(posedge ctrl_vif.clk iff !ctrl_vif.rst && data_out_vif.tvalid);
        end

        env.ready_ctrl.set_manual_ready(1'b1);
        wait_for_expected_outputs_to_drain(5);
        env.ready_ctrl.release_manual();
    endtask

    task run_output_overflow_case(input int base_tb_img_idx, input int first_slot, input int num_imgs, input int stall_cycles);
        bit driver_done;

        driver_done = 1'b0;
        env.ready_ctrl.set_manual_ready(1'b0);

        fork
            begin
                for (int img_idx = 0; img_idx < num_imgs; img_idx++) begin
                    drive_image(base_tb_img_idx + img_idx, select_bp_stim_idx(first_slot + img_idx), 0, 0);
                end
                driver_done = 1'b1;
            end
        join_none

        @(posedge ctrl_vif.clk iff !ctrl_vif.rst && data_out_vif.tvalid);
        if (stall_cycles > 1) begin
            repeat (stall_cycles - 1) @(posedge ctrl_vif.clk iff !ctrl_vif.rst && data_out_vif.tvalid);
        end

        env.ready_ctrl.set_manual_ready(1'b1);
        wait (driver_done);
        wait_for_expected_outputs_to_drain(5);
        env.ready_ctrl.release_manual();
    endtask

    task run_output_backpressure_tests();
        int stall_cycles[10];
        int num_cases;

        stall_cycles = '{0, 1, 4, 8, 20, 40, 75, 150, 350, 750};
        if (!cfg.force_bp_duration_coverage || cfg.num_tests == 0) begin
            return;
        end

        num_cases = cfg.allow_bp_greater_than_100 ? 10 : 7;
        for (int case_idx = 0; case_idx < num_cases; case_idx++) begin
            run_output_hold_case(tb_img_idx_counter, select_bp_stim_idx(case_idx), stall_cycles[case_idx]);
            tb_img_idx_counter++;
        end

        if (cfg.allow_bp_greater_than_100) begin
            run_output_overflow_case(tb_img_idx_counter, 0, 4, 750);
            tb_img_idx_counter += 4;
        end
    endtask

    task run_main_image_sweep();
        for (int i = 0; i < cfg.num_tests; i++) begin
            if (cfg.reset_every_n_images > 0 && i > 0 && i % cfg.reset_every_n_images == 0) begin
                reset_and_reconfigure(1'b0, 1'b0, 1'b0);
            end
            drive_image(i, i, 0, 0);
            tb_img_idx_counter++;
        end
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_gap_directed_tests();
        int inter_gap_cycles;
        int gap_before_last_cycles;
        int directed_slot;
        int stim_idx;

        for (int d = 0; d < cfg.directed_tests(); d++) begin
            inter_gap_cycles       = 0;
            gap_before_last_cycles = 0;
            directed_slot          = 0;
            stim_idx               = d % cfg.num_tests;

            if (cfg.alt_j_gap_len) begin
                if (d == directed_slot) inter_gap_cycles = 2;
                else if (d == directed_slot + 1) inter_gap_cycles = 6;
                directed_slot += 2;
            end

            if (cfg.force_short_gap_before_last) begin
                if (d == directed_slot) gap_before_last_cycles = 2;
                directed_slot++;
            end

            if (cfg.force_long_gap_before_last) begin
                if (d == directed_slot) gap_before_last_cycles = 6;
                directed_slot++;
            end

            drive_image(tb_img_idx_counter, stim_idx, inter_gap_cycles, gap_before_last_cycles);
            tb_img_idx_counter++;
        end
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_manual_partial_config_reset();
        @(negedge ctrl_vif.clk);
        config_vif.tdata  <= cfg.config_bus_data_stream[0];
        config_vif.tkeep  <= cfg.config_bus_keep_stream[0];
        config_vif.tlast  <= 1'b0;
        config_vif.tvalid <= 1'b1;
        @(posedge ctrl_vif.clk iff config_vif.tready);
        @(negedge ctrl_vif.clk);
        config_vif.tvalid <= 1'b0;
        @(posedge ctrl_vif.clk);
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b1;
        repeat (5) @(posedge ctrl_vif.clk);
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b0;
        clear_config_input_bus();
        repeat (5) @(posedge ctrl_vif.clk);
    endtask

    task run_manual_reset_during_input();
        pixel_t img_f[];

        cfg.stim.get_vector(0, img_f);
        @(negedge ctrl_vif.clk);
        for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
            data_in_vif.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_f[k];
        end
        data_in_vif.tkeep  <= '1;
        data_in_vif.tvalid <= 1'b1;
        data_in_vif.tlast  <= 1'b0;
        @(posedge ctrl_vif.clk iff data_in_vif.tready);
        @(negedge ctrl_vif.clk);
        data_in_vif.tvalid <= 1'b1;
        ctrl_vif.rst       <= 1'b1;
        repeat (5) @(posedge ctrl_vif.clk);
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b0;
        clear_data_input_bus();
        repeat (5) @(posedge ctrl_vif.clk);
    endtask

    task run_manual_reset_during_output();
        env.ready_ctrl.set_manual_ready(1'b0);
        drive_image(tb_img_idx_counter, 0, 0, 0);
        @(posedge ctrl_vif.clk iff !ctrl_vif.rst && data_out_vif.tvalid);
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b1;
        repeat (6) @(posedge ctrl_vif.clk);
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b0;
        env.ready_ctrl.release_manual();
        repeat (5) @(posedge ctrl_vif.clk);
    endtask

    task run_class_sweep();
        for (int c = 0; c < 10; c++) begin
            if (cfg.class_cov_valid[c]) begin
                drive_custom_image(tb_img_idx_counter, cfg.class_cov_img[c], 0, 0);
                tb_img_idx_counter++;
            end
        end
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_input_diversity_sweep();
        pixel_t img_uniform[];
        pixel_t img_low[];
        pixel_t img_high[];

        img_uniform = new[cfg.actual_topology[0]];
        img_low     = new[cfg.actual_topology[0]];
        img_high    = new[cfg.actual_topology[0]];

        for (int i = 0; i < cfg.actual_topology[0]; i++) begin
            img_uniform[i] = 8'd42;
            img_low[i]     = (i % 2) ? 8'd80 : 8'd40;
            img_high[i]    = (i % 2) ? 8'd255 : 8'd0;
        end

        drive_custom_image(tb_img_idx_counter, img_uniform, 0, 0);
        tb_img_idx_counter++;
        drive_custom_image(tb_img_idx_counter, img_low, 0, 0);
        tb_img_idx_counter++;
        drive_custom_image(tb_img_idx_counter, img_high, 0, 0);
        tb_img_idx_counter++;
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_data_in_img_gap_2_to_10();
        drive_image(tb_img_idx_counter, 0 % cfg.num_tests, 0, 0);
        tb_img_idx_counter++;
        drive_image(tb_img_idx_counter, 1 % cfg.num_tests, 3, 0);
        tb_img_idx_counter++;
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_config_partial_keep();
        config_keep_t partial_keep;

        rebuild_default_config_stream();
        partial_keep      = '0;
        partial_keep[3:0] = '1;
        cfg.config_bus_keep_stream[cfg.config_bus_keep_stream.size() - 1] = partial_keep;
        send_config_stream_back_to_back();
        wait_for_input_ready(3);
        rebuild_default_config_stream();
    endtask

    task run_data_in_partial_keep();
        pixel_t      img_m[];
        input_keep_t partial_keep;

        cfg.stim.get_vector(0, img_m);
        partial_keep      = '0;
        partial_keep[3:0] = '1;

        @(negedge ctrl_vif.clk);
        for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
            data_in_vif.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_m[k];
        end
        data_in_vif.tkeep  <= partial_keep;
        data_in_vif.tvalid <= 1'b1;
        data_in_vif.tlast  <= 1'b0;
        @(posedge ctrl_vif.clk iff data_in_vif.tready);
        @(negedge ctrl_vif.clk);
        clear_data_input_bus();
        @(posedge ctrl_vif.clk);
        pulse_reset();
        send_default_config_and_wait(3);
    endtask

    task run_output_tlast_bp();
        run_output_hold_case(tb_img_idx_counter, 0 % cfg.num_tests, 1);
        tb_img_idx_counter++;
    endtask

    task run_data_in_long_run();
        for (int i = 0; i < 6; i++) begin
            drive_image_back_to_back(i % cfg.num_tests);
            tb_img_idx_counter++;
        end
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_data_in_long_gaps();
        drive_image(tb_img_idx_counter, 0 % cfg.num_tests, 30, 0);
        tb_img_idx_counter++;
        drive_image(tb_img_idx_counter, 1 % cfg.num_tests, 200, 0);
        tb_img_idx_counter++;
        drive_image(tb_img_idx_counter, 2 % cfg.num_tests, 0, 30);
        tb_img_idx_counter++;
        drive_image(tb_img_idx_counter, 3 % cfg.num_tests, 0, 200);
        tb_img_idx_counter++;
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_class_repeat_burst();
        int rep_idx;

        rep_idx = select_bp_stim_idx(0);
        for (int i = 0; i < 120; i++) begin
            drive_image(tb_img_idx_counter, rep_idx, 0, 0);
            tb_img_idx_counter++;
        end
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_per_class_output_stall(input int stall_cycles);
        for (int c = 0; c < 10; c++) begin
            if (cfg.class_cov_valid[c]) begin
                run_output_hold_case_image(tb_img_idx_counter, cfg.class_cov_img[c], stall_cycles);
                tb_img_idx_counter++;
            end
        end
    endtask

    task run_data_in_gap1_cross();
        drive_image(tb_img_idx_counter, 0 % cfg.num_tests, 1, 0);
        tb_img_idx_counter++;
        drive_image(tb_img_idx_counter, 1 % cfg.num_tests, 0, 1);
        tb_img_idx_counter++;
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_output_bp_350();
        run_output_hold_case(tb_img_idx_counter, select_bp_stim_idx(0), 350);
        tb_img_idx_counter++;
    endtask

    task run_data_in_img_gap_more();
        drive_image(tb_img_idx_counter, 0 % cfg.num_tests, 1, 0);
        tb_img_idx_counter++;
        drive_image(tb_img_idx_counter, 1 % cfg.num_tests, 20, 0);
        tb_img_idx_counter++;
        drive_image(tb_img_idx_counter, 2 % cfg.num_tests, 500, 0);
        tb_img_idx_counter++;
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_many_resets();
        for (int i = 0; i < 7; i++) begin
            pulse_reset();
        end
        send_default_config_and_wait(3);
    endtask

    task run_class_cross_extra_stalls();
        int extra_stalls[4];

        extra_stalls = '{3, 8, 12, 60};
        for (int stall_idx = 0; stall_idx < $size(extra_stalls); stall_idx++) begin
            run_per_class_output_stall(extra_stalls[stall_idx]);
        end
    endtask

    task run_data_in_last_beat_vbr();
        pixel_t img_gg[];
        int     img_size;
        int     last_j;
        int     penult_j;

        cfg.stim.get_vector(0, img_gg);
        img_size = img_gg.size();
        last_j   = (((img_size + INPUTS_PER_CYCLE - 1) / INPUTS_PER_CYCLE) - 1) * INPUTS_PER_CYCLE;
        penult_j = last_j - INPUTS_PER_CYCLE;

        for (int j = 0; j < penult_j; j += INPUTS_PER_CYCLE) begin
            @(negedge ctrl_vif.clk);
            for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                data_in_vif.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_gg[j+k];
                data_in_vif.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
            end
            data_in_vif.tvalid <= 1'b1;
            data_in_vif.tlast  <= 1'b0;
            @(posedge ctrl_vif.clk iff data_in_vif.tready);
        end

        @(negedge ctrl_vif.clk);
        data_in_vif.tvalid <= 1'b0;
        data_in_vif.tlast  <= 1'b0;
        @(posedge ctrl_vif.clk);

        @(negedge ctrl_vif.clk);
        for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
            data_in_vif.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_gg[penult_j+k];
            data_in_vif.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
        end
        if (!uvm_hdl_force("bnn_fcc_uvm_tb.data_in.tready", 1'b0)) begin
            `uvm_fatal(get_type_name(), "Failed to force bnn_fcc_uvm_tb.data_in.tready low.")
        end
        data_in_vif.tvalid <= 1'b1;
        data_in_vif.tlast  <= 1'b0;
        @(posedge ctrl_vif.clk);
        @(negedge ctrl_vif.clk);
        if (!uvm_hdl_release("bnn_fcc_uvm_tb.data_in.tready")) begin
            `uvm_fatal(get_type_name(), "Failed to release bnn_fcc_uvm_tb.data_in.tready.")
        end
        @(posedge ctrl_vif.clk iff data_in_vif.tready);

        @(negedge ctrl_vif.clk);
        data_in_vif.tvalid <= 1'b0;
        data_in_vif.tlast  <= 1'b0;
        @(posedge ctrl_vif.clk);

        @(negedge ctrl_vif.clk);
        for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
            if (last_j + k < img_size) begin
                data_in_vif.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= img_gg[last_j+k];
                data_in_vif.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
            end else begin
                data_in_vif.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= '0;
                data_in_vif.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '0;
            end
        end
        data_in_vif.tvalid <= 1'b1;
        data_in_vif.tlast  <= 1'b1;
        @(posedge ctrl_vif.clk iff data_in_vif.tready);

        @(negedge ctrl_vif.clk);
        clear_data_input_bus();
        tb_img_idx_counter++;
        wait_for_expected_outputs_to_drain(5);
    endtask

    task run_config_inter_msg_gap_high_bins();
        int gap_cases[3];

        gap_cases = '{10, 30, 300};
        for (int gap_idx = 0; gap_idx < $size(gap_cases); gap_idx++) begin
            pulse_reset();
            rebuild_default_config_stream();
            send_config_stream_with_inter_msg_gap(gap_cases[gap_idx]);
            wait_for_input_ready(3);
        end
    endtask

    task send_single_beat_config_msg(input bit [7:0] msg_type);
        config_word_t single_word;
        config_keep_t full_keep;

        single_word      = '0;
        single_word[7:0] = msg_type;
        full_keep        = '1;

        @(negedge ctrl_vif.clk);
        config_vif.tdata  <= single_word;
        config_vif.tkeep  <= full_keep;
        config_vif.tlast  <= 1'b1;
        config_vif.tvalid <= 1'b1;
        @(posedge ctrl_vif.clk iff config_vif.tready);
        @(negedge ctrl_vif.clk);
        config_vif.tvalid <= 1'b0;
        config_vif.tlast  <= 1'b0;
    endtask

    task run_single_beat_config_msgs();
        pulse_reset();
        send_single_beat_config_msg(8'd0);
        pulse_reset();
        rebuild_default_config_stream();
        send_default_config_and_wait(3);

        pulse_reset();
        send_single_beat_config_msg(8'd1);
        pulse_reset();
        rebuild_default_config_stream();
        send_default_config_and_wait(3);
    endtask

    task run_additional_directed_tests();
        if (cfg.force_large_config_gap || cfg.force_large_config_stall) begin
            reset_and_reconfigure(cfg.force_large_config_gap, cfg.force_large_config_stall, 1'b0);
        end

        if (cfg.threshold_first_msg_directed_test) begin
            reset_and_reconfigure(1'b0, 1'b0, 1'b1);
        end

        run_gap_directed_tests();

        run_manual_partial_config_reset();
        send_default_config_and_wait(3);

        run_manual_reset_during_input();
        send_default_config_and_wait(3);

        run_manual_reset_during_output();
        send_default_config_and_wait(3);

        pulse_reset();
        send_config_packets_of_type(8'd0);
        repeat (3) @(posedge ctrl_vif.clk);
        pulse_reset();
        send_default_config_and_wait(3);

        send_config_packets_of_type(8'd1);
        repeat (3) @(posedge ctrl_vif.clk);
        pulse_reset();
        send_default_config_and_wait(3);

        run_class_sweep();
        run_data_in_img_gap_2_to_10();
        run_input_diversity_sweep();
        run_config_partial_keep();
        run_data_in_partial_keep();

        rebuild_default_config_stream();
        send_config_stream_back_to_back();
        wait_for_input_ready(3);

        run_output_tlast_bp();
        run_data_in_long_run();
        run_data_in_long_gaps();
        run_class_repeat_burst();
        run_per_class_output_stall(40);
        run_per_class_output_stall(150);
        run_data_in_gap1_cross();
        run_per_class_output_stall(1);
        run_per_class_output_stall(750);
        run_output_bp_350();
        run_data_in_img_gap_more();
        run_many_resets();
        run_class_cross_extra_stalls();
        run_data_in_last_beat_vbr();
        run_output_backpressure_tests();
        run_config_inter_msg_gap_high_bins();
        run_single_beat_config_msgs();
    endtask

    virtual task run_body();
        initialize_model_and_stimulus();

        ctrl_vif.rst <= 1'b1;
        clear_config_input_bus();
        clear_data_input_bus();

        repeat (5) @(posedge ctrl_vif.clk);
        @(negedge ctrl_vif.clk);
        ctrl_vif.rst <= 1'b0;
        repeat (5) @(posedge ctrl_vif.clk);

        send_default_config_and_wait(5);

        if ((cfg.directed_tests() > 0 || cfg.force_bp_duration_coverage) && cfg.num_tests == 0) begin
            `uvm_fatal(get_type_name(), "Directed coverage tests require at least one loaded image.")
        end

        run_main_image_sweep();
        run_additional_directed_tests();
        wait_for_expected_outputs_to_drain(10);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        $timeformat(-9, 0, " ns", 0);
        run_body();
        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        int passed;
        int failed;

        super.report_phase(phase);
        passed = env.scoreboard.get_passed();
        failed = env.scoreboard.get_failed();

        if (passed == 0 && failed == 0) begin
            `uvm_error(get_type_name(), "TEST FAILED (no outputs were checked).")
        end else if (failed > 0) begin
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "---     TEST FAILED     ---", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
        end else begin
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "---     TEST PASSED     ---", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
        end
    endfunction
endclass

`endif
