// Greg Stitt
// Alejandro Paez-Sansonetti
//
// MODULE: bnn_fcc_fashion_tb
//
// DESCRIPTION:
// Testbench for the binary neural net (bnn) fully connected classifier (fcc).
//
// There are two modes for the testbench. If you enable USE_CUSTOM_TOPOLOGY, the testbench
// evaluates the topology specified by CUSTOM_TOPOLOGY using a random model (weights+thresholds).
//
// For USE_CUSTOM_TOPOLOGY=0, this copy of the testbench targets a Fashion-MNIST
// binary model using the same SFC topology (784->256->256->10) from the FINN paper:
// Umuroglu, Y., Fraser, N. J., Gambardella, G., Blott, M., Leong, P., Jahre, M., & Vissers, K. (2017). FINN: A Framework for Fast, Scalable Binarized Neural Network Inference. In Proceedings of the 2017 ACM/SIGDA International Symposium on Field-Programmable Gate Arrays (pp. 65-74). DOI: 10.1145/3020078.3021744
//
// The testbench compares the actual outputs with the expected outputs provided in the BNN_FCC_Model
// class (see bnn_fcc_tb_pkg.sv). That class also contains a variety of functions that you might find
// useful for debugging.
//
// bnn_fcc_tb_pkg.sv also provides a BNN_FCC_Stimulus class that loads images from files (in the
// case of Fashion-MNIST) or randomly generates test images (for USE_CUSTOM_TOPOLOGY=0).
//
//
// PARAMETERS:
// [Testbench Configuration]
// USE_CUSTOM_TOPOLOGY       - Enable user-defined NN topology specified by CUSTOM_TOPOLOGY
//                             instead of the default trained Fashion-MNIST topology.
// CUSTOM_LAYERS             - Total layers (Includes input, hidden, and output) if using a custom topology.
// CUSTOM_TOPOLOGY           - Array defining neurons per layer, with the exception of
//                             CUSTOM_TOPOLOGY[0], which specifies the number of inputs.
// NUM_TEST_IMAGES           - Number of stimulus images for simulation
// VERIFY_MODEL              - Cross-check SV results against Python model 
//                             (only applicable to USE_CUSTOM_TOPOLOGY=1'b0)
// BASE_DIR                  - Path to Python model data and test vectors (must be set relative to
//                             your simulator's working directory)
// TOGGLE_DATA_OUT_READY     - Randomly toggles data_out_ready to simulate back-pressure. Must be enabled
//                             to fully pass tests for contest. Disable to measure throughput and latency.
// CONFIG_VALID_PROBABILITY  - Real value from 0.0 to 1.0 that specifies the probability of the
//                             configuration bus providing valid data while the DUT is ready. Used to
//                             simulate a slow upstream producer. Must be set to a value less than 1.0
//                             to full pass testing, but should be set to 1 to measure performance.
// DATA_IN_VALID_PROBABILITY - Real value from 0.0 to 1.0 that specifies the probability of the
//                             data_in bus providing valid pixels while the DUT is ready. Used to
//                             simulate a slow upstream producer. Must be set to a value less than 1.0
//                             to fully pass testing, but should be set to 1 to measure performance.
// TIMEOUT                   - Realtime value that specifies the maximum amount of time the testbench is
//                             allowed to run before being terminated. Adjust based on the expected 
//                             performance of your design.
// CLK_PERIOD                - Realtime value specifying the clock period.
// DEBUG                     - Set to print model details and an inference trace for each layer.
//
// [Bus Configuration]
// CONFIG_BUS_WIDTH          - Bit-width for configuration bus (AXI streaming)
// INPUT_BUS_WIDTH           - Bit-width for primary input data stream (AXI streaming)
// OUTPUT_BUS_WIDTH          - Bit-width for output (AXI streaming)
//
// [App Configuration]       (Note: changes to the defaults have not been tested, may break classes in bnn_fcc_tb_pkg)
// INPUT_DATA_WIDTH          - Bit-width of individual input elements (8-bit grayscale pixels)
// OUTPUT_DATA_WIDTH         - Bit-width of individual output elements
//
// [DUT Configuration]       (TODO: Adapt to your own DUT if necessary. Feel free to create, ignore, and/or remove parameters)
// PARALLEL_INPUTS           - Number of inputs/weights processed in parallel in the first hidden layer.
// PARALLEL_NEURONS          - Number of neurons processed in parallel in each non-input layer.

`timescale 1ns / 100ps

module bnn_fcc_fashion_tb #(
    // Testbench configuration
    parameter int      USE_CUSTOM_TOPOLOGY                      = 1'b0,
    parameter int      CUSTOM_LAYERS                            = 4,
    parameter int      CUSTOM_TOPOLOGY          [CUSTOM_LAYERS] = '{8, 8, 8, 8},
    parameter int      NUM_TEST_IMAGES                          = 50,
    parameter bit      VERIFY_MODEL                             = 1,
    parameter string   BASE_DIR                                 = "../python/fashion_mnist",
    parameter bit      TOGGLE_DATA_OUT_READY                    = 1'b1,
    parameter real     CONFIG_VALID_PROBABILITY                 = 1.0,
    parameter real     DATA_IN_VALID_PROBABILITY                = 1.0,
    parameter realtime TIMEOUT                                  = 100ms,
    parameter realtime CLK_PERIOD                               = 10ns,
    parameter bit      DEBUG                                    = 1'b0,

    // Bus configuration
    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int INPUT_BUS_WIDTH  = 64,
    parameter int OUTPUT_BUS_WIDTH = 8,

    // App configuration
    parameter  int INPUT_DATA_WIDTH  = 8,
    localparam int INPUTS_PER_CYCLE  = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH,
    localparam int BYTES_PER_INPUT   = INPUT_DATA_WIDTH / 8,
    parameter  int OUTPUT_DATA_WIDTH = 4,

    // Should not be changed
    localparam int TRAINED_LAYERS = 4,
    localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10},

    // DUT configuration (can be modified or extended for your own DUT)        
    localparam int NON_INPUT_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS - 1 : TRAINED_LAYERS - 1,
    parameter int PARALLEL_INPUTS = 8,
    parameter int LAYER_PARALLEL_INPUTS[NON_INPUT_LAYERS] = '{64, 32, 32},

    parameter int PARALLEL_NEURONS[NON_INPUT_LAYERS] = '{32, 32, 10}
);
    import bnn_fcc_tb_pkg::*;

    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS;
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] = USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY;

    localparam string FASHION_MNIST_TEST_VECTOR_INPUT_PATH  = "test_vectors/inputs.hex";
    localparam string FASHION_MNIST_TEST_VECTOR_OUTPUT_PATH = "test_vectors/expected_outputs.txt";
    localparam string FASHION_MNIST_GROUND_TRUTH_PATH       = "test_vectors/fashion_ground_truth.txt";
    localparam string FASHION_MNIST_MODEL_DATA_PATH         = "model_data";
    localparam string FASHION_MNIST_METADATA_PATH           = "fashion_mnist_metadata.json";

    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

    initial begin
        assert (INPUT_DATA_WIDTH == 8)
        else $fatal(1, "TB ERROR: INPUT_DATA_WIDTH must be 8. Sub-byte or multi-byte packing logic not yet implemented.");
    end

    // Returns 1 with probability p, 0 with probability 1-p.
    function automatic bit chance(real p);
        if (p > 1.0 || p < 0.0) $fatal(1, "Invalid probability in chance()");
        return ($urandom < (p * (2.0 ** 32)));
    endfunction

    function automatic string fashion_mnist_class_name(int class_idx);
        case (class_idx)
            0: return "T-shirt/top";
            1: return "Trouser";
            2: return "Pullover";
            3: return "Dress";
            4: return "Coat";
            5: return "Sandal";
            6: return "Shirt";
            7: return "Sneaker";
            8: return "Bag";
            9: return "Ankle boot";
            default: return $sformatf("Unknown(%0d)", class_idx);
        endcase
    endfunction

    function automatic bit file_exists(string path);
        int fd;
        fd = $fopen(path, "r");
        if (fd == 0) begin
            return 1'b0;
        end
        $fclose(fd);
        return 1'b1;
    endfunction

    function automatic string join_path(string base, string relative_path);
        if (base.len() == 0) begin
            return relative_path;
        end
        return $sformatf("%s/%s", base, relative_path);
    endfunction

    function automatic bit candidate_has_fashion_assets(string candidate_base);
        string metadata_path;
        string label_path;
        string model_path;
        string input_path;
        begin
            metadata_path = join_path(candidate_base, FASHION_MNIST_METADATA_PATH);
            label_path    = join_path(candidate_base, FASHION_MNIST_GROUND_TRUTH_PATH);
            model_path    = join_path(candidate_base, $sformatf("%s/l0_weights.txt", FASHION_MNIST_MODEL_DATA_PATH));
            input_path    = join_path(candidate_base, FASHION_MNIST_TEST_VECTOR_INPUT_PATH);
            candidate_has_fashion_assets =
                file_exists(metadata_path) &&
                file_exists(label_path) &&
                file_exists(model_path) &&
                file_exists(input_path);
        end
    endfunction

    function automatic bit candidate_has_generic_assets(string candidate_base);
        string model_path;
        string input_path;
        begin
            model_path = join_path(candidate_base, $sformatf("%s/l0_weights.txt", FASHION_MNIST_MODEL_DATA_PATH));
            input_path = join_path(candidate_base, FASHION_MNIST_TEST_VECTOR_INPUT_PATH);
            candidate_has_generic_assets = file_exists(model_path) && file_exists(input_path);
        end
    endfunction

    function automatic string resolve_dataset_base_dir();
        string candidate;
        begin
            candidate = BASE_DIR;
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "../python/fashion_mnist";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "python/fashion_mnist";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "./python/fashion_mnist";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "../../python/fashion_mnist";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "../fashion_mnist_port/python";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "fashion_mnist_port/python";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "./fashion_mnist_port/python";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "../../fashion_mnist_port/python";
            if (candidate_has_fashion_assets(candidate)) return candidate;

            candidate = "python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "../python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "../../python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "./python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = BASE_DIR;
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "../python/fashion_mnist";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "python/fashion_mnist";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "./python/fashion_mnist";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "../../python/fashion_mnist";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "../fashion_mnist_port/python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "fashion_mnist_port/python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "./fashion_mnist_port/python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            candidate = "../../fashion_mnist_port/python";
            if (candidate_has_generic_assets(candidate)) return candidate;

            return BASE_DIR;
        end
    endfunction

    BNN_FCC_Model #(CONFIG_BUS_WIDTH) model;
    BNN_FCC_Stimulus #(INPUT_DATA_WIDTH) stim;
    LatencyTracker latency;
    ThroughputTracker throughput;

    typedef bit [CONFIG_BUS_WIDTH-1:0] config_bus_word_t;
    typedef config_bus_word_t config_bus_data_stream_t[];

    localparam CONFIG_KEEP_WIDTH = CONFIG_BUS_WIDTH / 8;
    typedef bit [CONFIG_KEEP_WIDTH-1:0] config_bus_keep_t;
    typedef config_bus_keep_t config_keep_stream_t[];

    bit [CONFIG_BUS_WIDTH-1:0] config_bus_data_stream[];
    bit [CONFIG_BUS_WIDTH/8-1:0] config_bus_keep_stream[];

    int num_tests;
    int passed;
    int failed;
    int model_matches_truth;
    int dut_matches_truth;
    int ground_truth_labels[$];
    bit have_ground_truth_labels;
    string resolved_base_dir;

    function automatic int get_truth_label(int image_idx);
        if (have_ground_truth_labels && image_idx < ground_truth_labels.size()) begin
            return ground_truth_labels[image_idx];
        end

        return -1;
    endfunction

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
        .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
        .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
        .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH),
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .TOTAL_LAYERS     (ACTUAL_TOTAL_LAYERS),
        .TOPOLOGY         (ACTUAL_TOPOLOGY),
        .PARALLEL_INPUTS  (PARALLEL_INPUTS),
        .PARALLEL_NEURONS (PARALLEL_NEURONS),
        .LAYER_PARALLEL_INPUTS (LAYER_PARALLEL_INPUTS)

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

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task verify_model();
        int python_preds[];
        bit [INPUT_DATA_WIDTH-1:0] current_img[];
        string input_path;
        string output_path;
        input_path  = join_path(resolved_base_dir, FASHION_MNIST_TEST_VECTOR_INPUT_PATH);
        output_path = join_path(resolved_base_dir, FASHION_MNIST_TEST_VECTOR_OUTPUT_PATH);

        // Load stimulus images
        stim.load_from_file(input_path);
        num_tests = stim.get_num_vectors();

        // Load Python predictions (i.e. truth)
        python_preds = new[num_tests];
        $readmemh(output_path, python_preds);

        for (int i = 0; i < num_tests; i++) begin
            int sv_pred;
            stim.get_vector(i, current_img);
            sv_pred = model.compute_reference(current_img);  // SV calculates result            

            // Self-check the SV model.
            if (sv_pred !== python_preds[i]) begin
                $error("TB LOGIC ERROR: Img %0d. SV Model says %0d, Python says %0d", i, sv_pred, python_preds[i]);
                $finish;  // Stop immediately, the testbench is broken
                /*end else begin
                $display("Img %0d: Class %0d (Matched Python)", i, sv_pred);*/
            end
        end

        $display("SV model successfully verified.");
    endtask

    task load_ground_truth_labels(string filename, int max_labels = -1);
        int fd;
        int label;
        int code;

        ground_truth_labels = {};
        have_ground_truth_labels = 1'b0;

        fd = $fopen(filename, "r");
        if (fd == 0) begin
            $warning("Could not open optional Fashion-MNIST label file %s", filename);
            return;
        end

        while (!$feof(fd)) begin
            if (max_labels != -1 && ground_truth_labels.size() >= max_labels) break;
            code = $fscanf(fd, "%d\n", label);
            if (code == 1) begin
                ground_truth_labels.push_back(label);
            end
        end
        $fclose(fd);

        have_ground_truth_labels = (ground_truth_labels.size() > 0);
        $display("Loaded %0d Fashion-MNIST ground-truth labels from %s", ground_truth_labels.size(), filename);
    endtask

    // ===========================================================================
    // Initialize model and config memory
    // ===========================================================================
    initial begin : l_init_model
        string path;
        model = new();
        stim = new(ACTUAL_TOPOLOGY[0]);
        latency = new(CLK_PERIOD);
        throughput = new(CLK_PERIOD);
        have_ground_truth_labels = 1'b0;
        model_matches_truth = 0;
        dut_matches_truth   = 0;
        resolved_base_dir   = resolve_dataset_base_dir();

        if (!USE_CUSTOM_TOPOLOGY) begin
            // Load Weights & Configure Memory
            $display("--- Loading Trained Model ---");
            path = join_path(resolved_base_dir, FASHION_MNIST_METADATA_PATH);
            if (candidate_has_fashion_assets(resolved_base_dir)) begin
                $display("Resolved dataset base directory: %s", resolved_base_dir);
                $display("Resolved Fashion-MNIST metadata: %s", path);
            end else begin
                $warning("Resolved dataset base directory %s does not contain Fashion-MNIST metadata; using best available assets.", resolved_base_dir);
            end

            path = join_path(resolved_base_dir, FASHION_MNIST_MODEL_DATA_PATH);
            model.load_from_file(path, ACTUAL_TOPOLOGY);
            if (VERIFY_MODEL) verify_model();
            model.encode_configuration(config_bus_data_stream, config_bus_keep_stream);
            $display("--- Configuration created: %0d words (%0d-bit wide) ---", config_bus_data_stream.size(), CONFIG_BUS_WIDTH);

            // Load input images
            $display("--- Loading Test Vectors ---");
            path = join_path(resolved_base_dir, FASHION_MNIST_TEST_VECTOR_INPUT_PATH);
            stim.load_from_file(path, NUM_TEST_IMAGES);
            path = join_path(resolved_base_dir, FASHION_MNIST_GROUND_TRUTH_PATH);
            load_ground_truth_labels(path, stim.get_num_vectors());
        end else begin
            $display("--- Loading Randomized Model ---");
            model.create_random(ACTUAL_TOPOLOGY);
            model.encode_configuration(config_bus_data_stream, config_bus_keep_stream);
            $display("--- Configuration created: %0d words (%0d-bit wide) ---", config_bus_data_stream.size(), CONFIG_BUS_WIDTH);

            $display("--- Generating Random Test Vectors ---");
            stim.generate_random_vectors(NUM_TEST_IMAGES);
        end

        num_tests = stim.get_num_vectors();
        model.print_summary();

        if (DEBUG) model.print_model();

        // NOTE: You can also debug by looking at the model's weights, thresholds, and layer ouputs. 
        // For example, this prints the model for all neurons in the first hidden layer:
        // for (int i = 0; i < ACTUAL_TOPOLOGY[1]; i++) model.print_neuron(0, i);      
        //
        // where the parameters specify the layer and neuron. This loop iterates over all
        // neurons in the first hidden layer. Note that the parameters treat the first hidden layer
        // as layer 0, essentially excluding the input layer since it has no neurons.
        //
        // Weights are accessible via model.weight[][][], where the dimensions are:
        // [layer][neuron][bit]
        //
        // thresholds are accessible via model.threshold[][], where the dimensions are:
        // [layer][neuron]
    end

    logic [OUTPUT_DATA_WIDTH-1:0] expected_outputs[$];

    assign config_in.tstrb = config_in.tkeep;
    assign data_in.tstrb   = data_in.tkeep;

    initial begin : l_sequencer_and_driver
        $timeformat(-9, 0, " ns", 0);

        rst              <= 1'b1;
        config_in.tvalid <= 1'b0;
        config_in.tdata  <= '0;
        config_in.tkeep  <= '0;
        config_in.tlast  <= 1'b0;
        config_in.tuser  <= '0;
        config_in.tid    <= '0;
        config_in.tdest  <= '0;
        data_in.tvalid   <= 1'b0;
        data_in.tdata    <= '0;
        data_in.tkeep    <= '0;
        data_in.tlast    <= 1'b0;
        data_in.tuser    <= '0;
        data_in.tid      <= '0;
        data_in.tdest    <= '0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        // Stream in weights and thresholds.
        $display("[%0t] Streaming weights and thresholds.", $realtime);
        for (int i = 0; i < config_bus_data_stream.size(); i++) begin

            // Simulate gaps on configuration bus.
            while (!chance(
                CONFIG_VALID_PROBABILITY
            )) begin
                config_in.tvalid <= 1'b0;
                @(posedge clk iff config_in.tready);
            end

            config_in.tvalid <= 1'b1;
            config_in.tdata  <= config_bus_data_stream[i];
            config_in.tlast  <= i == config_bus_data_stream.size() - 1;
            config_in.tkeep  <= config_bus_keep_stream[i];
            @(posedge clk iff config_in.tready);
        end
        config_in.tvalid <= 1'b0;
        config_in.tlast  <= 1'b0;

        wait (data_in.tready);
        repeat (5) @(posedge clk);

        for (int i = 0; i < num_tests; i++) begin
            int expected_pred;
            int truth_label;
            bit expected_bit;
            bit [INPUT_DATA_WIDTH-1:0] current_img[];

            // Fetch stimulus image i (pre-created by either stim.load_from_file() or stim.generate_random_vectors())
            stim.get_vector(i, current_img);

            // Compute expected output for current image. This also generates references for each layer's
            // outputs, which can be accessed via model.layer_outputs[layer][neuron] for deeper verification.
            expected_pred = model.compute_reference(current_img);
            expected_outputs.push_back(expected_pred);

            // Stream image into DUT.
            truth_label = get_truth_label(i);
            if (truth_label >= 0 && expected_pred == truth_label) begin
                model_matches_truth++;
            end
            if (truth_label >= 0) begin
                $display("[%0t] Streaming image %0d: truth=%0s expected=%0s.", $realtime, i, fashion_mnist_class_name(truth_label), fashion_mnist_class_name(expected_pred));
            end else begin
                $display("[%0t] Streaming image %0d: expected=%0s.", $realtime, i, fashion_mnist_class_name(expected_pred));
            end
            if (DEBUG) model.print_inference_trace();

            for (int j = 0; j < current_img.size(); j += INPUTS_PER_CYCLE) begin

                // Pack multiple pixels into a single AXI beat.
                for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
                    if (j + k < current_img.size()) begin
                        data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= current_img[j+k];
                        data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '1;
                    end else begin
                        data_in.tdata[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= '0;
                        data_in.tkeep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   <= '0;
                    end
                end

                // Simulate gaps on data_in bus.
                while (!chance(
                    DATA_IN_VALID_PROBABILITY
                )) begin
                    data_in.tvalid <= 1'b0;
                    @(posedge clk iff data_in.tready);
                end
                data_in.tvalid <= 1'b1;
                data_in.tlast  <= (j + INPUTS_PER_CYCLE >= current_img.size());
                @(posedge clk iff data_in.tready);

                // Start the throughput timer after the first beat of the first image has been accepted.                
                if (i == 0 && j == 0) throughput.start_test();

                // Start the latency timer after the first beat of each image has been accepted.                
                if (j == 0) latency.start_event(i);
            end

            data_in.tvalid <= 1'b0;
            data_in.tlast  <= 1'b0;
            data_in.tkeep  <= '0;
            @(posedge clk);
        end

        $display("[%0t] All images loaded, waiting for outputs.", $realtime);
        wait (expected_outputs.size() == 0);
        repeat (5) @(posedge clk);

        disable generate_clock;
        disable l_timeout;
        if (passed == num_tests) $display("[%0t] SUCCESS: all %0d tests completed successfully.", $realtime, num_tests);
        else $error("FAILED: %0d out of %0d tests failed.", failed, num_tests);

        $display("\nStats:");
        $display("Avg latency (cycles) per image: %0.1f cycles", latency.get_avg_cycles());
        $display("Avg latency (time) per image: %0.1f ns", latency.get_avg_time());
        $display("Avg throughput (outputs/sec): %0.1f", throughput.get_outputs_per_sec(NUM_TEST_IMAGES));
        $display("Avg throughput (cycles/output): %0.1f", throughput.get_avg_cycles_per_output(NUM_TEST_IMAGES));
        if (num_tests > 0) begin
            $display("DUT vs model match: %0.2f%% (%0d/%0d)", 100.0 * passed / num_tests, passed, num_tests);
        end
        if (have_ground_truth_labels) begin
            $display("Model vs ground truth match: %0.2f%% (%0d/%0d)", 100.0 * model_matches_truth / num_tests, model_matches_truth, num_tests);
            $display("DUT vs ground truth match: %0.2f%% (%0d/%0d)", 100.0 * dut_matches_truth / num_tests, dut_matches_truth, num_tests);
        end
    end

    initial begin : l_toggle_ready
        data_out.tready <= 1'b1;
        @(posedge clk iff !rst);
        if (TOGGLE_DATA_OUT_READY) begin
            forever begin
                data_out.tready <= $urandom();
                @(posedge clk);
            end
        end else data_out.tready <= 1'b1;
    end

    initial begin : l_output_monitor
        automatic int output_count = 0;
        forever begin
            int expected_pred;
            int actual_pred;
            int truth_label;
            @(posedge clk iff data_out.tvalid && data_out.tready);
            assert (expected_outputs.size() > 0)
            else $fatal(1, "No expected output for actual output");
            expected_pred = int'(expected_outputs[0]);
            actual_pred   = int'(data_out.tdata[OUTPUT_DATA_WIDTH-1:0]);
            truth_label   = get_truth_label(output_count);

            assert (actual_pred == expected_pred) begin
                passed++;
                if (truth_label >= 0) begin
                    $display("[%0t] PASS image %0d: truth=%0s expected=%0s actual=%0s", $realtime, output_count, fashion_mnist_class_name(truth_label), fashion_mnist_class_name(expected_pred), fashion_mnist_class_name(actual_pred));
                end else begin
                    $display("[%0t] PASS image %0d: expected=%0s actual=%0s", $realtime, output_count, fashion_mnist_class_name(expected_pred), fashion_mnist_class_name(actual_pred));
                end
            end else begin
                if (truth_label >= 0) begin
                    $error("Output incorrect for image %0d: truth=%0s actual=%0s vs expected=%0s", output_count, fashion_mnist_class_name(truth_label), fashion_mnist_class_name(actual_pred), fashion_mnist_class_name(expected_pred));
                end else begin
                    $error("Output incorrect for image %0d: actual=%0s vs expected=%0s", output_count, fashion_mnist_class_name(actual_pred), fashion_mnist_class_name(expected_pred));
                end
                failed++;
            end
            if (truth_label >= 0 && actual_pred == truth_label) begin
                dut_matches_truth++;
            end
            void'(expected_outputs.pop_front());
            latency.end_event(output_count);
            if (output_count == NUM_TEST_IMAGES - 1) throughput.sample_end();
            output_count++;
        end
    end

    initial begin : l_timeout
        #TIMEOUT;
        $fatal(1, $sformatf("Simulation failed due to timeout of %0t.", TIMEOUT));
    end

endmodule

