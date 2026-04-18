`timescale 1ns/1ps

module arg_max_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int ACT_W = 10,
    parameter int POPCOUNT_W = 16,
    parameter int OUT_W = 8
);
    localparam int PIPELINE_DEPTH = 5;

    logic                              clk;
    logic                              rst;
    logic                              en;
    logic [ACT_W-1:0][POPCOUNT_W-1:0]  popcount;
    logic [OUT_W-1:0]                  bcc_out;
    logic                              out_valid;

    Arg_MAX #(
        .act_w      (ACT_W),
        .popcount_w (POPCOUNT_W),
        .out_w      (OUT_W)
    ) DUT (
        .*
    );

    function automatic logic [OUT_W-1:0] argmax_ref(
        input logic [ACT_W-1:0][POPCOUNT_W-1:0] popcount_ref_in
    );
        logic [POPCOUNT_W-1:0] best_value;
        logic [OUT_W-1:0]      best_index;
        begin
            best_value = popcount_ref_in[0];
            best_index = '0;

            for (int i = 1; i < ACT_W; i++) begin
                if (popcount_ref_in[i] > best_value) begin
                    best_value = popcount_ref_in[i];
                    best_index = OUT_W'(i);
                end
            end

            return best_index;
        end
    endfunction

    initial begin : generate_clock
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    initial begin
        rst <= 1'b1;
        en  <= 1'b0;
        popcount <= '0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;

        for (int i = 0; i < NUM_TESTS; i++) begin
            en <= $urandom;
            for (int j = 0; j < ACT_W; j++) begin
                popcount[j] <= $urandom;
            end
            @(posedge clk);
        end

        en <= 1'b0;
        popcount <= '0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);

        disable generate_clock;
        $display("Tests Completed.");
    end

    logic [OUT_W-1:0] correct_bcc_out;
    logic             correct_out_valid;
    logic [OUT_W-1:0] model_queue_idx[$];
    logic             model_queue_valid[$];

    // queue model for the pipeline delay
    always_ff @(posedge clk or posedge rst)
        if (rst) begin
            model_queue_idx   = {};
            model_queue_valid = {};
            for (int i = 0; i < PIPELINE_DEPTH; i++) begin
                model_queue_idx.push_back('0);
                model_queue_valid.push_back(1'b0);
            end
            correct_bcc_out   <= '0;
            correct_out_valid <= 1'b0;
        end else begin
            automatic logic [OUT_W-1:0] next_idx;
            automatic logic [OUT_W-1:0] popped_idx;
            automatic logic             popped_valid;

            next_idx = argmax_ref(popcount);

            popped_idx   = model_queue_idx.pop_front();
            popped_valid = model_queue_valid.pop_front();

            model_queue_idx.push_back(next_idx);
            model_queue_valid.push_back(en);

            correct_bcc_out   <= popped_idx;
            correct_out_valid <= popped_valid;
        end

    assert property (@(posedge clk) disable iff (rst) out_valid == correct_out_valid);
    assert property (@(posedge clk) disable iff (rst) out_valid |-> bcc_out == correct_bcc_out);
    assert property (@(posedge clk) disable iff (rst) out_valid |-> bcc_out < ACT_W);

    // make sure we really drive en and get a valid output

    cp_enable :
    cover property (@(posedge clk) !rst && en);
    cp_output_valid :
    cover property (@(posedge clk) !rst && out_valid);

    // also hit a tie and a winner at the last index
    cp_tie_case :
    cover property (@(posedge clk) !rst && en && popcount[0] == popcount[1]);
    cp_last_index_wins :
    cover property (@(posedge clk) !rst && out_valid && bcc_out == ACT_W-1);

endmodule
