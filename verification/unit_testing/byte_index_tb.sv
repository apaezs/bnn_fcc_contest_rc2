`timescale 1ns/1ps

module byte_index_tb #(
    parameter int NUM_TESTS = 5000,
    parameter int N_SLOTS   = 4
);
    localparam int COUNT_W  = (N_SLOTS <= 1) ? 1 : $clog2(N_SLOTS);
    localparam logic [COUNT_W-1:0] MAX_VALUE = COUNT_W'(N_SLOTS - 1);

    logic               clk;
    logic               valid_in;
    logic               clear;
    logic               write_valid;
    logic [N_SLOTS-1:0] write_en;
    logic               write_full;

    Byte_Index #(.N_SLOTS(N_SLOTS)) DUT (.*);

    initial begin : generate_clock
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    initial begin
        valid_in <= 1'b0;
        clear    <= 1'b0;
        repeat (5) @(posedge clk);

        for (int i = 0; i < NUM_TESTS; i++) begin
            @(negedge clk);
            valid_in <= $urandom_range(0, 1);
            clear    <= $urandom_range(0, 1);
            @(posedge clk);
        end

        @(negedge clk);
        valid_in <= 1'b0;
        clear    <= 1'b0;
        repeat (10) @(posedge clk);

        disable generate_clock;
        $display("Tests completed.");
    end

    // Software model - mirrors the 4-stage pipeline 
    logic [COUNT_W-1:0] m_pos_r   = '0;
    logic [COUNT_W-1:0] m_pos_s1  = '0;
    logic               m_valid_s0, m_valid_s1, m_valid_s3;
    logic               m_clear_s0;
    logic [N_SLOTS-1:0] m_write_en_s2;
    logic               m_write_full_s2;
    logic [N_SLOTS-1:0] m_write_en_s3;
    logic               m_write_full_s3;
    logic               m_write_valid;
    logic [N_SLOTS-1:0] m_write_en;
    logic               m_write_full;

    // stage 2 is combinational
    always_comb begin
        m_write_en_s2   = '0;
        m_write_full_s2 = 1'b0;
        for (int i = 0; i < N_SLOTS; i++)
            if (m_pos_s1 == COUNT_W'(i))
                m_write_en_s2[i] = 1'b1;
        if (m_pos_s1 == MAX_VALUE)
            m_write_full_s2 = 1'b1;
    end

    always_ff @(posedge clk) begin
        // stage 0
        m_valid_s0 <= valid_in;
        m_clear_s0 <= clear;

        // stage 1
        m_valid_s1 <= m_valid_s0;
        if (m_valid_s0) begin
            if (m_clear_s0) begin
                m_pos_s1 <= '0;
                m_pos_r  <= (N_SLOTS <= 1) ? '0 : COUNT_W'(1);
            end else begin
                m_pos_s1 <= m_pos_r;
                m_pos_r  <= (m_pos_r == MAX_VALUE) ? '0 : m_pos_r + 1'b1;
            end
        end else if (m_clear_s0) begin
            m_pos_r <= '0;
        end

        // stage 3
        m_valid_s3      <= m_valid_s1;
        m_write_en_s3   <= m_write_en_s2;
        m_write_full_s3 <= m_write_full_s2;

        // stage 4 
        m_write_valid <= m_valid_s3;
        m_write_en    <= m_write_en_s3;
        m_write_full  <= m_write_full_s3;
    end


    assert property (@(posedge clk) write_valid    == m_write_valid);
    assert property (@(posedge clk) write_en       == m_write_en);
    assert property (@(posedge clk) write_full     == m_write_full);

    // write_en must be one-hot whenever an output is valid
    assert property (@(posedge clk) write_valid |-> $onehot(write_en));

    // write_full must agree with the last slot being selected
    assert property (@(posedge clk) write_valid && write_full  |-> write_en[N_SLOTS-1]);
    assert property (@(posedge clk) write_valid && !write_full |-> !write_en[N_SLOTS-1]);


endmodule
