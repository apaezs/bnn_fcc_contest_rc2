`timescale 1ns/1ps

// bnn no-parser testbench

module bnn_core_no_config_parser #(
    parameter int INPUT_DATA_WIDTH = 8,
    parameter int INPUT_BUS_WIDTH  = 64,
    parameter int TOTAL_LAYERS = 4,
    parameter int TOPOLOGY[0:TOTAL_LAYERS-1] = '{0:784, 1:256, 2:256, 3:10, default:0},
    parameter int LAYER_PARALLEL_INPUTS[0:TOTAL_LAYERS-2] = '{0:64, 1:32, 2:32, default:8},
    parameter int PARALLEL_NEURONS[0:TOTAL_LAYERS-2] = '{0:32, 1:32, 2:10, default:8},
    parameter int THRESHOLD_WIDTH = 32,
    parameter int LAYER_LATENCY[0:TOTAL_LAYERS-2] = '{default:14},
    localparam int LAYERS = TOTAL_LAYERS - 1,
    localparam int LAYER_W = (LAYERS <= 1) ? 1 : $clog2(LAYERS),
    localparam int CLASS_W = (TOPOLOGY[LAYERS] <= 1) ? 1 : $clog2(TOPOLOGY[LAYERS]),
    localparam int POP_W = $clog2(TOPOLOGY[LAYERS-1] + 1)
)(
    input  logic clk,
    input  logic rst,

    input  logic               msg_valid,
    output logic               msg_ready,
    input  logic [LAYER_W-1:0] msg_layer,
    input  logic [7:0]         msg_type,
    input  logic [31:0]        msg_total_bytes,

    input  logic               payload_valid,
    output logic               payload_ready,
    input  logic [7:0]         payload_data,

    input  logic                         data_in_valid,
    output logic                        data_in_ready,
    input  logic [INPUT_BUS_WIDTH-1:0]  data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0] data_in_keep,
    input  logic                        data_in_last,

    output logic [POP_W-1:0]   class_scores [0:TOPOLOGY[LAYERS]-1],
    output logic               output_valid,
    output logic [CLASS_W-1:0] predicted_class,
    output logic               busy,
    output logic               all_cfg_done
);
    logic [LAYERS-1:0] cfg_done_arr;
    logic              h0_input_buffer_stall;
    logic [LAYERS-1:0] write_bank_sel_arr;
    logic [LAYER_PARALLEL_INPUTS[0]-1:0] first_layer_bits;
    logic                                first_layer_write;

    logic [PARALLEL_NEURONS[LAYERS-1]-1:0]                  final_valid_acc;
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0][POP_W-1:0]       final_pop_out;

    logic [CLASS_W-1:0] predicted_class_r;
    logic               argmax_valid;

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

        .fifo_full             (),
        .fifo_empty            ()
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
        .msg_ready             (msg_ready),
        .msg_layer             (msg_layer),
        .msg_type              (msg_type),
        .msg_total_bytes       (msg_total_bytes),

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

    Arg_MAX #(
        .act_w      (PARALLEL_NEURONS[LAYERS-1]),
        .popcount_w (POP_W),
        .out_w      (CLASS_W)
    ) u_argmax (
        .clk       (clk),
        .rst       (rst),
        .en        (|final_valid_acc),
        .popcount  (final_pop_out),
        .bcc_out   (predicted_class_r),
        .out_valid (argmax_valid)
    );

    assign all_cfg_done    = &cfg_done_arr;
    assign busy            = !all_cfg_done;
    assign output_valid    = argmax_valid;
    assign predicted_class = predicted_class_r;

    generate
        genvar g;
        for (g = 0; g < TOPOLOGY[LAYERS]; g++) begin : GEN_CLASS_SCORES
            assign class_scores[g] = final_pop_out[g];
        end
    endgenerate

endmodule

module bnn_top_pipelined_tb();

    // parameters matching the current bnn shape
    localparam int INPUT_SIZE         = 784;
    localparam int TOTAL_LAYERS       = 4;
    localparam int INPUT_DATA_WIDTH   = 8;
    localparam int INPUT_BUS_WIDTH    = 64;
    localparam int TOPOLOGY[0:TOTAL_LAYERS-1] = '{0:784, 1:256, 2:256, 3:10, default:0};
    localparam int LAYER_PARALLEL_INPUTS[0:TOTAL_LAYERS-2] = '{0:64, 1:32, 2:32, default:8};
    localparam int PARALLEL_NEURONS[0:TOTAL_LAYERS-2] = '{0:32, 1:32, 2:10, default:8};
    localparam int THRESHOLD_WIDTH   = 32;
    localparam int ACCUMULATOR_WIDTH = $clog2(TOPOLOGY[TOTAL_LAYERS-2] + 1);
    localparam real CLK_PERIOD       = 5.0; // 200 MHz

    // derived sizes
    localparam int INPUTS_PER_BEAT = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH;
    localparam int INPUT_CYCLES    = INPUT_SIZE / INPUTS_PER_BEAT;
    localparam int L1_NEURONS  = TOPOLOGY[1];
    localparam int L2_NEURONS  = TOPOLOGY[2];
    localparam int L3_NEURONS  = TOPOLOGY[3];
    localparam int NUM_VECTORS = 100;
    localparam int TIMEOUT_CYC = 4000; // max cycles waiting for one output_valid
    localparam int LAYER_W     = $clog2(TOTAL_LAYERS - 1);

    // config bus into the no-parser wrapper
    logic               msg_valid;
    logic               msg_ready;
    logic [LAYER_W-1:0] msg_layer;
    logic [7:0]         msg_type;
    logic [31:0]        msg_total_bytes;

    logic               payload_valid;
    logic               payload_ready;
    logic [7:0]         payload_data;

    // raw image input into the first layer unit
    logic                        data_in_valid;
    logic                        data_in_ready;
    logic [INPUT_BUS_WIDTH-1:0]  data_in_data;
    logic [INPUT_BUS_WIDTH/8-1:0] data_in_keep;
    logic                        data_in_last;

    // DUT ports
    logic clk, rst;
    logic [ACCUMULATOR_WIDTH-1:0] class_scores [9:0];
    logic                         output_valid;
    logic [3:0]                   predicted_class;
    logic                         busy;
    logic                         all_cfg_done;

    // DUT
    bnn_core_no_config_parser #(
        .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
        .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
        .TOTAL_LAYERS     (TOTAL_LAYERS),
        .TOPOLOGY         (TOPOLOGY),
        .LAYER_PARALLEL_INPUTS (LAYER_PARALLEL_INPUTS),
        .PARALLEL_NEURONS (PARALLEL_NEURONS),
        .THRESHOLD_WIDTH  (THRESHOLD_WIDTH)
    ) dut (
        .clk             (clk),
        .rst             (rst),

        .msg_valid       (msg_valid),
        .msg_ready       (msg_ready),
        .msg_layer       (msg_layer),
        .msg_type        (msg_type),
        .msg_total_bytes (msg_total_bytes),

        .payload_valid   (payload_valid),
        .payload_ready   (payload_ready),
        .payload_data    (payload_data),

        .data_in_valid   (data_in_valid),
        .data_in_ready   (data_in_ready),
        .data_in_data    (data_in_data),
        .data_in_keep    (data_in_keep),
        .data_in_last    (data_in_last),

        .class_scores    (class_scores),
        .output_valid    (output_valid),
        .predicted_class (predicted_class),
        .busy            (busy),
        .all_cfg_done    (all_cfg_done)
    );

    // clock
    initial clk = 0;
    always #(CLK_PERIOD/2.0) clk = ~clk;

    // test data
    string  weight_strings [0:2][256]; // [layer 1 / layer 2 / layer 3][neuron #] binary weight string
    int     thresholds     [0:2][256]; // [layer 1 / layer 2 / layer 3][neuron]
    logic [7:0] test_inputs [NUM_VECTORS][INPUT_SIZE];
    int         expected    [NUM_VECTORS];

    // captured results from receiver thread
    int captured_pred [NUM_VECTORS];

    // load all weight/threshold/input files
    task automatic load_files(); // with automatic each call gets its own clean copies

        integer fh; // integer to hold file handle
        string  line; // string to hold one line of text from a file

        // weights: one binary string per neuron per layer
        begin
            string fnames [3] = '{
                "python/model_data/l0_weights.txt",
                "python/model_data/l1_weights.txt",
                "python/model_data/l2_weights.txt"
            };

            int ncounts[3] = '{L1_NEURONS, L2_NEURONS, L3_NEURONS};

            for (int l = 0; l < 3; l++) begin
                fh = $fopen(fnames[l], "r");
                if (fh == 0) $fatal(1, "Cannot open %s", fnames[l]);

                for (int n = 0; n < ncounts[l]; n++) begin
                    string clean_line;
                    void'($fgets(line, fh));
                    clean_line = "";

                    for (int i = 0; i < line.len(); i++) begin
                        if (line.getc(i) == "0" || line.getc(i) == "1")
                            clean_line = {clean_line, line.getc(i)};
                    end

                    weight_strings[l][n] = clean_line;
                end

                $fclose(fh);
            end
        end

        // thresholds: one int per neuron per layer
        begin
            string fnames [3] = '{
                "python/model_data/l0_thresholds.txt",
                "python/model_data/l1_thresholds.txt",
                "python/model_data/l2_thresholds.txt"
            };

            int ncounts[3] = '{L1_NEURONS, L2_NEURONS, L3_NEURONS};

            for (int l = 0; l < 3; l++) begin
                fh = $fopen(fnames[l], "r");
                if (fh == 0) $fatal(1, "Cannot open %s", fnames[l]);

                for (int n = 0; n < ncounts[l]; n++) begin
                    void'($fscanf(fh, "%d ", thresholds[l][n]));
                end

                $fclose(fh);
            end
        end

        // inputs: hex-encoded, 1568 chars per line (2 chars per pixel)
        fh = $fopen("python/test_vectors/inputs.hex", "r");
        if (fh == 0) $fatal(1, "Cannot open python/test_vectors/inputs.hex");

        for (int img = 0; img < NUM_VECTORS; img++) begin
            void'($fgets(line, fh));

            for (int px = 0; px < INPUT_SIZE; px++) begin
                string hex2;
                hex2 = {line[px*2], line[px*2+1]};
                test_inputs[img][px] = hex2.atohex();
            end
        end
        $fclose(fh);

        // expected labels: one int per line
        fh = $fopen("python/test_vectors/expected_outputs.txt", "r");
        if (fh == 0) $fatal(1, "Cannot open python/test_vectors/expected_outputs.txt");

        for (int i = 0; i < NUM_VECTORS; i++)
            void'($fscanf(fh, "%d ", expected[i]));

        $fclose(fh);

        $display("Files loaded.");
    endtask

    task automatic send_message_header(
        input int layer_idx,
        input bit [7:0] kind,
        input int total_bytes
    );
        begin
            @(posedge clk);
            msg_valid       <= 1'b1;
            msg_layer       <= layer_idx[LAYER_W-1:0];
            msg_type        <= kind;
            msg_total_bytes <= total_bytes[31:0];

            while (!msg_ready) @(posedge clk);

            @(posedge clk);
            msg_valid       <= 1'b0;
            msg_layer       <= '0;
            msg_type        <= '0;
            msg_total_bytes <= '0;
        end
    endtask

    task automatic send_payload_byte(input logic [7:0] byte_val);
        begin
            @(posedge clk);
            payload_valid <= 1'b1;
            payload_data  <= byte_val;

            while (!payload_ready) @(posedge clk);

            @(posedge clk);
            payload_valid <= 1'b0;
            payload_data  <= '0;
        end
    endtask

    // program one layer's weights
    task automatic program_weights(
        input int layer_idx,
        input int num_neurons,
        input int fan_in
    );
        automatic int bytes_per_neuron;
        automatic int total_bytes;
        begin
            bytes_per_neuron = (fan_in + 7) / 8;
            total_bytes      = bytes_per_neuron * num_neurons;

            send_message_header(layer_idx, 8'h00, total_bytes);

            for (int n = 0; n < num_neurons; n++) begin
                for (int b = 0; b < bytes_per_neuron; b++) begin
                    logic [7:0] byte_val;
                    byte_val = '0;

                    for (int k = 0; k < 8; k++) begin
                        int c;
                        c = b*8 + k;
                        if (c < weight_strings[layer_idx][n].len())
                            byte_val[k] = (weight_strings[layer_idx][n].getc(c) == "1");
                        else
                            byte_val[k] = 1'b1;
                    end

                    send_payload_byte(byte_val);
                end
            end
        end
    endtask

    // program one layer's thresholds
    task automatic program_thresholds(input int layer_idx, input int num_neurons);
        begin
            if (layer_idx >= TOTAL_LAYERS - 2)
                return;

            send_message_header(layer_idx, 8'h01, 4 * num_neurons);

            for (int n = 0; n < num_neurons; n++) begin
                logic [31:0] t_word;
                t_word = thresholds[layer_idx][n];

                for (int b = 0; b < 4; b++) begin
                    send_payload_byte(t_word[b*8 +: 8]);
                end
            end
        end
    endtask

    task automatic send_image(input int img_idx);
        begin
            while (busy) @(posedge clk);

            for (int beat = 0; beat < INPUT_CYCLES; beat++) begin
                logic [INPUT_BUS_WIDTH-1:0] packed_data;
                packed_data = '0;

                for (int i = 0; i < INPUTS_PER_BEAT; i++) begin
                    packed_data[i*INPUT_DATA_WIDTH +: INPUT_DATA_WIDTH] =
                        test_inputs[img_idx][beat*INPUTS_PER_BEAT + i];
                end

                while (!data_in_ready) @(posedge clk);

                @(posedge clk);
                data_in_valid <= 1'b1;
                data_in_data  <= packed_data;
                data_in_keep  <= '1;
                data_in_last  <= (beat == INPUT_CYCLES - 1);
            end

            @(posedge clk);
            data_in_valid <= 1'b0;
            data_in_data  <= '0;
            data_in_keep  <= '0;
            data_in_last  <= 1'b0;
        end
    endtask

    // main
    initial begin
        automatic int passed = 0;
        automatic int failed = 0;
        automatic int timeout_cyc;

        rst           <= 1'b1;
        msg_valid     <= 1'b0;
        msg_layer     <= '0;
        msg_type      <= '0;
        msg_total_bytes <= '0;
        payload_valid <= 1'b0;
        payload_data  <= '0;
        data_in_valid <= 1'b0;
        data_in_data  <= '0;
        data_in_keep  <= '0;
        data_in_last  <= 1'b0;

        for (int i = 0; i < NUM_VECTORS; i++)
            captured_pred[i] = -1;

        repeat(10) @(posedge clk);
        rst <= 1'b0;
        repeat(5) @(posedge clk);

        load_files();

        $display("Programming weights and thresholds start...");
        program_weights(0, L1_NEURONS, INPUT_SIZE);
        program_thresholds(0, L1_NEURONS);
        program_weights(1, L2_NEURONS, L1_NEURONS);
        program_thresholds(1, L2_NEURONS);
        program_weights(2, L3_NEURONS, L2_NEURONS);

        wait (all_cfg_done);
        repeat (10) @(posedge clk);

        $display("Programming weights and thresholds...DONE");
        $display("Running %0d pipelined inferences...", NUM_VECTORS);

        fork

            begin : sender
                automatic int t;
                for (t = 0; t < NUM_VECTORS; t++) begin
                    send_image(t);
                end
            end

            begin : receiver
                automatic int t;

                for (t = 0; t < NUM_VECTORS; t++) begin
                    timeout_cyc = 0;

                    while (!output_valid) begin
                        @(posedge clk);

                        if (++timeout_cyc >= TIMEOUT_CYC) begin
                            $display("TIMEOUT waiting for output %0d", t);
                            disable receiver;
                        end
                    end

                    captured_pred[t] = int'(predicted_class);
                    while (output_valid) @(posedge clk);
                end
            end

        join

        // check results
        for (int t = 0; t < NUM_VECTORS; t++) begin
            if (captured_pred[t] == expected[t]) begin
                $display("Test%3d PASS  pred=%0d  exp=%0d", t, captured_pred[t], expected[t]);
                passed++;
            end else begin
                $display("Test%3d FAIL  pred=%0d  exp=%0d", t, captured_pred[t], expected[t]);
                failed++;
            end
        end

        $display("---");
        $display("Passed %0d / %0d  (%.1f%%)", passed, NUM_VECTORS,
                 100.0 * passed / NUM_VECTORS);
        if (failed == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TESTS FAILED", failed);

        $finish;
    end

    // watchdog
    initial begin
        #500ms;
        $fatal(1, "GLOBAL TIMEOUT: simulation exceeded 500 ms");
    end

endmodule
