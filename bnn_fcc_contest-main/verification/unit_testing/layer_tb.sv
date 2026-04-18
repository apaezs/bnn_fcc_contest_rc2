`timescale 1ns/1ps

module layer #(
    parameter int NUM_NEURONS       = 8,
    parameter int NUM_WEIGHTS       = 4,
    parameter int PW                = 8,
    parameter int THRESHOLD_WIDTH   = 10,
    parameter int ACCUMULATOR_WIDTH = 16,
    parameter int LAT               = 14,
    localparam int TN               = NUM_WEIGHTS * PW,
    localparam int BEAT_W           = (NUM_WEIGHTS <= 1) ? 1 : $clog2(NUM_WEIGHTS),
    localparam int BANK_W           = (NUM_NEURONS <= 1) ? 1 : $clog2(NUM_NEURONS),
    localparam int W_ADDR_W         = (NUM_WEIGHTS <= 1) ? 1 : $clog2(NUM_WEIGHTS),
    localparam int TW_ADDR_W        = 1
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [PW-1:0] x,
    input  logic x_valid,
    input  logic x_last,
    output logic [NUM_NEURONS-1:0] y_bits,
    output logic done,
    output logic busy,
    input  logic weight_we,
    input  logic [BANK_W-1:0] neuron_id,
    input  logic [W_ADDR_W-1:0] weight_addr,
    input  logic [PW-1:0] weight_data,
    input  logic threshold_we,
    input  logic [BANK_W-1:0] threshold_neuron_id,
    input  logic [THRESHOLD_WIDTH-1:0] threshold_data
);

    logic start_allowed_bank0;
    logic start_allowed_bank1;
    logic write_bank_sel_out;

    logic read_bank_sel;
    logic clear_bank0;
    logic clear_bank1;
    logic [BEAT_W-1:0] buffer_raddr;

    logic [NUM_NEURONS-1:0] out_int;
    logic [NUM_NEURONS-1:0][$clog2(TN+1)-1:0] pop_out_int;
    logic [NUM_NEURONS-1:0] valid_acc_int;
    logic [NUM_NEURONS-1:0] valid_out_int;

    logic [PW-1:0] input_buffer_word;

    Input_Buffer_NoStall #(
        .IB_WIDTH (PW),
        .PW       (PW),
        .TN       (TN)
    ) dut_input_buffer (
        .clk                 (clk),
        .rst                 (rst),
        .buffer_write        (x_valid),
        .raddr               (buffer_raddr),
        .read_bank_sel       (read_bank_sel),
        .clear_bank0         (clear_bank0),
        .clear_bank1         (clear_bank1),
        .istream             (x),
        .ostream             (input_buffer_word),
        .start_allowed_bank0 (start_allowed_bank0),
        .start_allowed_bank1 (start_allowed_bank1),
        .write_bank_sel_out  (write_bank_sel_out)
    );

    Layer_WithThreshold #(
        .PN        (NUM_NEURONS),
        .PW        (PW),
        .TN        (TN),
        .N_NEURONS (NUM_NEURONS),
        .TW        (THRESHOLD_WIDTH),
        .LAT       (LAT)
    ) dut_layer (
        .clk                 (clk),
        .rst                 (rst),
        .start_allowed_bank0 (start_allowed_bank0),
        .start_allowed_bank1 (start_allowed_bank1),
        .write_bank_sel      (write_bank_sel_out),
        .read_bank_sel       (read_bank_sel),
        .clear_bank0         (clear_bank0),
        .clear_bank1         (clear_bank1),
        .buffer_raddr        (buffer_raddr),
        .input_buffer        (input_buffer_word),
        .w_cfg_valid         (weight_we),
        .w_cfg_bank          (neuron_id),
        .w_cfg_addr          (weight_addr),
        .w_cfg_data          (weight_data),
        .t_cfg_valid         (threshold_we),
        .t_cfg_bank          (threshold_neuron_id),
        .t_cfg_addr          ('0),
        .t_cfg_data          (threshold_data),
        .out                 (out_int),
        .pop_out             (pop_out_int),
        .valid_acc           (valid_acc_int),
        .valid_out           (valid_out_int)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            y_bits              <= '0;
            done                <= 1'b0;
            busy                <= 1'b0;
        end else begin
            done                <= 1'b0;

            if (start) begin
                busy <= 1'b1;
            end

            if (&valid_out_int) begin
                y_bits <= out_int;
                done   <= 1'b1;
                busy   <= 1'b0;
            end
        end
    end

endmodule

module layer_tb;

    localparam int NN  = 8;   // NUM_NEURONS
    localparam int NW  = 4;   // NUM_WEIGHTS
    localparam int PW  = 8;
    localparam int TW  = 10;
    localparam int AW  = 16;
    localparam real CLK_PERIOD = 10.0;

    // test data
    logic [PW-1:0] weights    [NN][NW];  // [neuron][word]
    logic [PW-1:0] x_in  [NW];
    logic [TW-1:0] thresholds [NN];

    // ref model
    function automatic logic [NN-1:0] expected_ybits();
        automatic logic [NN-1:0] result = '0;
        for (int n = 0; n < NN; n++) begin
            automatic int acc = 0;
            for (int w = 0; w < NW; w++)
                for (int b = 0; b < PW; b++)
                    if (x_in[w][b] == weights[n][w][b]) acc++;
            result[n] = (acc >= int'(thresholds[n]));
        end
        return result;
    endfunction

    task automatic randomise_stim();
        for (int n = 0; n < NN; n++) begin
            thresholds[n] = TW'(PW*NW/4 + ($urandom % (PW*NW/2 + 1)));
            for (int w = 0; w < NW; w++)
                weights[n][w] = $urandom;
        end
        for (int w = 0; w < NW; w++)
            x_in[w] = $urandom;
    endtask

    // DUT side
    logic          clk = 0;
    logic          rst;
    logic          start;
    logic [PW-1:0] x;
    logic          x_valid;
    logic          x_last;
    logic [NN-1:0] y_bits;
    logic          done;
    logic          busy;
    logic          weight_we;
    logic [$clog2(NN)-1:0] neuron_id;
    logic [$clog2(NW)-1:0] weight_addr;
    logic [PW-1:0]         weight_data;
    logic          threshold_we;
    logic [$clog2(NN)-1:0] threshold_neuron_id;
    logic [TW-1:0]         threshold_data;

    layer #(.NUM_NEURONS(NN), .NUM_WEIGHTS(NW), .PW(PW),
            .THRESHOLD_WIDTH(TW), .ACCUMULATOR_WIDTH(AW)) dut (.*);

    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // load all weights and thresholds
    task automatic program_layer();
        for (int n = 0; n < NN; n++) begin
            for (int w = 0; w < NW; w++) begin
                @(posedge clk); #1;
                weight_we   <= 1;
                neuron_id   <= n[$clog2(NN)-1:0];
                weight_addr <= w[$clog2(NW)-1:0];
                weight_data <= weights[n][w];
            end
        end
        @(posedge clk); #1;
        weight_we <= 0;

        for (int n = 0; n < NN; n++) begin
            @(posedge clk); #1;
            threshold_we        <= 1;
            threshold_neuron_id <= n[$clog2(NN)-1:0];
            threshold_data      <= thresholds[n];
        end
        @(posedge clk); #1;
        threshold_we <= 0;
    endtask

    task automatic run_inference();
        @(posedge clk); #1;
        start   <= 1;
        x_valid <= 0;

        @(posedge clk); #1;
        start <= 0;

        @(posedge clk); #1;
        x       <= x_in[0];
        x_valid <= 1;
        x_last  <= (NW == 1);

        for (int w = 1; w < NW; w++) begin
            @(posedge clk); #1;
            x       <= x_in[w];
            x_valid <= 1;
            x_last  <= (w == NW-1);
        end

        @(posedge clk); #1;
        x_valid <= 0;
        x_last  <= 0;
        x       <= '0;

        @(posedge clk iff (done === 1'b1));
    endtask

    // check
    function void check(input string label);
        automatic logic [NN-1:0] exp = expected_ybits();
        if (y_bits !== exp)
            $error("[FAIL] %s: y_bits got=%04b exp=%04b", label, y_bits, exp);
        else
            $display("[PASS] %s: y_bits=%04b", label, y_bits);
    endfunction

    // test
    initial begin
        rst <= 1;
        start <= 0;
        x <= '0;
        x_valid <= 0;
        x_last <= 0;
        weight_we <= 0;
        neuron_id <= '0;
        weight_addr <= '0;
        weight_data <= '0;
        threshold_we <= 0;
        threshold_neuron_id <= '0;
        threshold_data <= '0;

        repeat(4) @(posedge clk);
        rst <= 0;
        @(posedge clk); #1;

        // run 1
        randomise_stim();
        program_layer();
        run_inference();
        check("run1");

        // run 2
        randomise_stim();
        program_layer();
        run_inference();
        check("run2");

        $finish;
    end

    initial begin
        #(CLK_PERIOD * 500);
        $fatal(1, "TIMEOUT");
    end

endmodule
