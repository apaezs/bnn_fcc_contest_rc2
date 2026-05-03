`timescale 1ns/1ps

module np_no_threshold_tb;

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

  // DUT outputs
  logic [ACC_W-1:0] popcount_total;
  logic             valid_acc;
  logic [AW-1:0]    accumulator_out;

  // loaded weights
  logic [PW-1:0] programmed_weights [0:NW-1];

  int error_count = 0;

  assign accumulator_out = AW'(popcount_total);

  always #5 clk = ~clk;

  NP_UNIT_PopcountOnly #(
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
    .popcount_total(popcount_total),
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

  task automatic clear_inputs();
    begin
      x_valid = 1'b0;
      x_last  = 1'b0;
      x       = '0;
      w       = '0;
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
    input logic [PW-1:0] weights_sv [0:NW-1]
  );
    begin
      for (int i = 0; i < NW; i++) begin
        programmed_weights[i] = weights_sv[i];
      end
    end
  endtask

  task automatic run_inference(
    input  logic [PW-1:0] inputs_sv [0:NW-1],
    output int            accumulator_seen,
    output int            valid_acc_count
  );
    begin
      clear_inputs();
      accumulator_seen = -1;
      valid_acc_count  = 0;

      for (int i = 0; i < NW; i++) begin
        @(negedge clk);
        x_valid = 1'b1;
        x_last  = (i == (NW - 1));
        x       = inputs_sv[i];
        w       = programmed_weights[i];
      end

      @(negedge clk);
      clear_inputs();

      for (int cycle = 0; cycle < RESULT_TIMEOUT; cycle++) begin
        @(posedge clk);

        if (valid_acc) begin
          accumulator_seen = accumulator_out;
          valid_acc_count++;
        end
      end

      if (valid_acc_count == 0) begin
        $fatal(1, "Timeout waiting for NP output.");
      end
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

  task automatic run_case(
    input string         case_name,
    input logic [PW-1:0] inputs_sv  [0:NW-1],
    input logic [PW-1:0] weights_sv [0:NW-1]
  );
    int accumulator_exp;
    int accumulator_seen;
    int valid_acc_count;
    begin
      $display("\n--- %s ---", case_name);

      accumulator_exp = accumulator_ref(inputs_sv, weights_sv);

      program_neuron(weights_sv);
      run_inference(inputs_sv, accumulator_seen, valid_acc_count);

      check_int({case_name, " accumulator"}, accumulator_seen, accumulator_exp);
      check_int({case_name, " valid_acc_count"}, valid_acc_count, 1);
    end
  endtask

  initial begin : test_sequence
    logic [PW-1:0] inputs_sv  [0:NW-1];
    logic [PW-1:0] weights_sv [0:NW-1];

    reset_dut();

    // run 1: all words match
    inputs_sv[0]  = 32'hA5A5_5A5A;
    inputs_sv[1]  = 32'hFFFF_0000;
    inputs_sv[2]  = 32'h0F0F_F0F0;
    inputs_sv[3]  = 32'h1234_5678;
    weights_sv[0] = 32'hA5A5_5A5A;
    weights_sv[1] = 32'hFFFF_0000;
    weights_sv[2] = 32'h0F0F_F0F0;
    weights_sv[3] = 32'h1234_5678;
    run_case("all_words_match", inputs_sv, weights_sv);

    // run 2: mixed match
    inputs_sv[0]  = 32'hFFFF_0000;
    inputs_sv[1]  = 32'h0000_FFFF;
    inputs_sv[2]  = 32'hA5A5_A5A5;
    inputs_sv[3]  = 32'h5A5A_5A5A;
    weights_sv[0] = 32'h0F0F_0F0F;
    weights_sv[1] = 32'hF0F0_F0F0;
    weights_sv[2] = 32'hA5A5_A5A5;
    weights_sv[3] = 32'h3333_CCCC;
    run_case("mixed_similarity", inputs_sv, weights_sv);

    // run 3: one bit off at the end
    inputs_sv[0]  = 32'h3333_3333;
    inputs_sv[1]  = 32'hCCCC_CCCC;
    inputs_sv[2]  = 32'h55AA_55AA;
    inputs_sv[3]  = 32'hF0F0_F00F;
    weights_sv[0] = 32'h3333_3333;
    weights_sv[1] = 32'hCCCC_CCCC;
    weights_sv[2] = 32'h55AA_55AA;
    weights_sv[3] = 32'hF0F0_F0FF;
    run_case("final_word_bit_flip", inputs_sv, weights_sv);

    // run 4: reprogrammed weights
    inputs_sv[0]  = 32'h9696_9696;
    inputs_sv[1]  = 32'h6969_6969;
    inputs_sv[2]  = 32'hF3F3_F3F3;
    inputs_sv[3]  = 32'h0C0C_0C0C;
    weights_sv[0] = 32'h6969_6969;
    weights_sv[1] = 32'h9696_9696;
    weights_sv[2] = 32'hF3F3_F3F3;
    weights_sv[3] = 32'h0C0C_0C0C;
    run_case("reprogrammed_weights", inputs_sv, weights_sv);

    if (error_count == 0) begin
      $display("\nAll NP no-threshold tests passed.");
    end else begin
      $fatal(1, "\nNP no-threshold test failed with %0d errors.", error_count);
    end

    $finish;
  end

endmodule
