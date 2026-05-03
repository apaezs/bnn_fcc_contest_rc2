`timescale 1ns/1ps

module fanout_tree_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int DWIDTH = 8,
    parameter int CLUSTERS = 8
);
    localparam int STAGES = (CLUSTERS <= 1) ? 1 : $clog2(CLUSTERS) + 1;

    logic                       clk;
    logic                       rst;
    logic [DWIDTH-1:0]          din;
    logic [CLUSTERS-1:0][DWIDTH-1:0] dout;

    fanout_tree #(
        .DWIDTH  (DWIDTH),
        .CLUSTERS(CLUSTERS)
    ) DUT (
        .*
    );

    initial begin : generate_clock
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    initial begin
        rst <= 1'b1;
        din <= '0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;

        for (int i = 0; i < NUM_TESTS; i++) begin
            din <= $urandom;
            @(posedge clk);
        end

        disable generate_clock;
        $display("Tests Completed.");
    end

    logic [DWIDTH-1:0] correct_dout;
    logic [DWIDTH-1:0] model_queue[$];

    // queue model for the tree latency
    always_ff @(posedge clk or posedge rst)
        if (rst) begin
            model_queue = {};
            for (int i = 0; i < STAGES; i++)
                model_queue.push_back('0);
            correct_dout <= '0;
        end else begin
            automatic logic [DWIDTH-1:0] unused;
            unused = model_queue.pop_front();
            model_queue.push_back(din);
            correct_dout <= model_queue[0];
        end

    generate
        for (genvar i = 0; i < CLUSTERS; i++) begin : GEN_ASSERTS
            assert property (@(posedge clk) dout[i] == correct_dout);
        end
    endgenerate

    // make sure we drove real values and saw them come out

    cp_input_nonzero :
    cover property (@(posedge clk) !rst && din != '0);
    cp_output_nonzero :
    cover property (@(posedge clk) !rst && dout[0] != '0);

    // also hit reset and check all outputs line up
    cp_reset :
    cover property (@(posedge clk) rst);
    cp_all_outputs_match :
    cover property (@(posedge clk) !rst && (dout == {CLUSTERS{correct_dout}}));

endmodule
