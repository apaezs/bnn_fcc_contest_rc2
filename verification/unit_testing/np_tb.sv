`timescale 1ns/1ps

module np_tb;

  localparam int PW                = 32;
  localparam int NW                = 4;
  localparam int TOTAL_BITS_NEURON = PW * NW;
  localparam int ACC_W             = $clog2(TOTAL_BITS_NEURON + 1);
  localparam int LAT               = 14;
  localparam int AW                = 32;
  localparam int RESULT_TIMEOUT    = 80;

  // clock/reset
  logic clk = 1'b0;
  logic rst = 1'b1;

  // inputs
  logic          x_valid;
  logic          x_last;
  logic [PW-1:0] x;
  logic [PW-1:0] w;
  logic [ACC_W-1:0] threshold;

  // DUT outputs
  logic [ACC_W-1:0] popcount_total;
  logic             y_bit;
  logic             y_valid;
  logic             valid_acc;
  logic [AW-1:0]    accumulator_out;

  // loaded weights/threshold
  logic [PW-1:0] programmed_weights [0:NW-1];
  logic [ACC_W-1:0] programmed_threshold;

  int error_count = 0;

  assign accumulator_out = AW'(popcount_total);

  always #5 clk = ~clk;

  NP_UNIT_WithThreshold #(
    .PW               (PW),
    .TOTAL_BITS_NEURON(TOTAL_BITS_NEURON),
    .LAT              (LAT)
  ) dut (
    .clk           (clk),
    .rst           (rst),
    .valid_in      (x_valid),
    .last_in       (x_last),
    .x             (x),
    .w             (w),
    .threshold     (threshold),
    .popcount_total(popcount_total),
    .y             (y_bit),
    .valid_out     (y_valid),
    .valid_acc     (valid_acc)
  );

  // simple ref model
  function automatic int popcount_ref(input logic [PW-1:0] value);
    int count;
    begin
      count = 0;
      for (int i = 0; i < PW; i++) begin
        count += value[i];
      end
      return count;
    end
  endfunction

  function automatic int accumulator_ref(
    input logic [PW-1:0] inputs_sv  [0:NW-1],
    input logic [PW-1:0] weights_sv [0:NW-1]
  );
    logic [PW-1:0] xnor_bits;
    int total;
    begin
      total = 0;
      for (int i = 0; i < NW; i++) begin
        xnor_bits = ~(inputs_sv[i] ^ weights_sv[i]);
        total += popcount_ref(xnor_bits);
      end
      return total;
    end
  endfunction

  function automatic logic neuron_ref(
    input int accumulator_sv,
    input int threshold_sv
  );
    begin
      return (accumulator_sv >= threshold_sv);
    end
  endfunction

  task automatic clear_inputs();
    begin
      x_valid   = 1'b0;
      x_last    = 1'b0;
      x         = '0;
      w         = '0;
      threshold = '0;
    end
  endtask

  task automatic reset_dut();
    begin
      clear_inputs();
      rst = 1'b1;
      repeat (4) @(posedge clk);
      rst = 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic program_neuron(
    input logic [PW-1:0] weights_sv [0:NW-1],
    input int            threshold_sv
  );
    begin
      for (int i = 0; i < NW; i++) begin
        programmed_weights[i] = weights_sv[i];
      end
      programmed_threshold = ACC_W'(threshold_sv);
    end
  endtask

  task automatic run_inference(
    input  logic [PW-1:0] inputs_sv [0:NW-1],
    output int            accumulator_seen,
    output logic          y_seen
  );
    bit got_result;
    begin
      clear_inputs();
      accumulator_seen = -1;
      y_seen           = 1'b0;
      got_result       = 1'b0;

      for (int i = 0; i < NW; i++) begin
        @(negedge clk);
        x_valid   = 1'b1;
        x_last    = (i == (NW - 1));
        x         = inputs_sv[i];
        w         = programmed_weights[i];
        threshold = programmed_threshold;
      end

      @(negedge clk);
      x_valid   = 1'b0;
      x_last    = 1'b0;
      x         = '0;
      w         = '0;
      threshold = programmed_threshold;

      for (int cycle = 0; cycle < RESULT_TIMEOUT; cycle++) begin
        @(posedge clk);

        if (valid_acc) begin
          accumulator_seen = accumulator_out;
        end

        if (y_valid) begin
          if (accumulator_seen < 0) begin
            accumulator_seen = accumulator_out;
          end
          y_seen     = y_bit;
          got_result = 1'b1;
          break;
        end
      end

      if (!got_result) begin
        $fatal(1, "Timeout waiting for NP output.");
      end

      clear_inputs();
    end
  endtask

  task automatic check_int(
    input string label,
    input int    got,
    input int    exp
  );
    begin
      if (got !== exp) begin
        error_count++;
        $display("FAIL %s: got=%0d exp=%0d", label, got, exp);
      end else begin
        $display("PASS %s: %0d", label, got);
      end
    end
  endtask

  task automatic check_bit(
    input string label,
    input logic  got,
    input logic  exp
  );
    begin
      if (got !== exp) begin
        error_count++;
        $display("FAIL %s: got=%0b exp=%0b", label, got, exp);
      end else begin
        $display("PASS %s: %0b", label, got);
      end
    end
  endtask

  task automatic run_case(
    input string         case_name,
    input logic [PW-1:0] inputs_sv  [0:NW-1],
    input logic [PW-1:0] weights_sv [0:NW-1],
    input int            threshold_sv
  );
    int   accumulator_exp;
    int   accumulator_seen;
    logic y_exp;
    logic y_seen;
    begin
      $display("\n--- %s ---", case_name);

      accumulator_exp = accumulator_ref(inputs_sv, weights_sv);
      y_exp           = neuron_ref(accumulator_exp, threshold_sv);

      program_neuron(weights_sv, threshold_sv);
      run_inference(inputs_sv, accumulator_seen, y_seen);

      check_int({case_name, " accumulator"}, accumulator_seen, accumulator_exp);
      check_bit({case_name, " y"}, y_seen, y_exp);
    end
  endtask

  initial begin : test_sequence
    logic [PW-1:0] inputs_sv  [0:NW-1];
    logic [PW-1:0] weights_sv [0:NW-1];
    int            threshold_sv;
    int            accumulator_sv;

    reset_dut();

    // run 1: exact threshold
    inputs_sv[0]  = 32'hA5A5_5A5A;
    inputs_sv[1]  = 32'hFFFF_0000;
    inputs_sv[2]  = 32'h0F0F_F0F0;
    inputs_sv[3]  = 32'h1234_5678;
    weights_sv[0] = 32'hA5A5_5A5A;
    weights_sv[1] = 32'hFFFF_0000;
    weights_sv[2] = 32'h0F0F_F0F0;
    weights_sv[3] = 32'h1234_5678;
    threshold_sv  = accumulator_ref(inputs_sv, weights_sv);
    run_case("exact_threshold_hit", inputs_sv, weights_sv, threshold_sv);

    // run 2: below threshold
    inputs_sv[0]  = 32'hFFFF_0000;
    inputs_sv[1]  = 32'h0000_FFFF;
    inputs_sv[2]  = 32'hA5A5_A5A5;
    inputs_sv[3]  = 32'h5A5A_5A5A;
    weights_sv[0] = 32'h0F0F_0F0F;
    weights_sv[1] = 32'hF0F0_F0F0;
    weights_sv[2] = 32'hA5A5_A5A5;
    weights_sv[3] = 32'h3333_CCCC;
    accumulator_sv = accumulator_ref(inputs_sv, weights_sv);
    threshold_sv   = accumulator_sv + 1;
    run_case("below_threshold", inputs_sv, weights_sv, threshold_sv);

    // run 3: above threshold
    inputs_sv[0]  = 32'h3333_3333;
    inputs_sv[1]  = 32'hCCCC_CCCC;
    inputs_sv[2]  = 32'h55AA_55AA;
    inputs_sv[3]  = 32'hF0F0_F00F;
    weights_sv[0] = 32'h3333_3333;
    weights_sv[1] = 32'hCCCC_CCCC;
    weights_sv[2] = 32'h55AA_55AA;
    weights_sv[3] = 32'hF0F0_F0FF;
    accumulator_sv = accumulator_ref(inputs_sv, weights_sv);
    threshold_sv   = accumulator_sv - 3;
    run_case("above_threshold", inputs_sv, weights_sv, threshold_sv);

    // run 4: reprogrammed weights
    inputs_sv[0]  = 32'h9696_9696;
    inputs_sv[1]  = 32'h6969_6969;
    inputs_sv[2]  = 32'hF3F3_F3F3;
    inputs_sv[3]  = 32'h0C0C_0C0C;
    weights_sv[0] = 32'h6969_6969;
    weights_sv[1] = 32'h9696_9696;
    weights_sv[2] = 32'hF3F3_F3F3;
    weights_sv[3] = 32'h0C0C_0C0C;
    accumulator_sv = accumulator_ref(inputs_sv, weights_sv);
    threshold_sv   = accumulator_sv;
    run_case("reprogrammed_weights", inputs_sv, weights_sv, threshold_sv);

    if (error_count == 0) begin
      $display("\nAll NP tests passed.");
    end else begin
      $fatal(1, "\nNP test failed with %0d errors.", error_count);
    end

    $finish;
  end

endmodule
