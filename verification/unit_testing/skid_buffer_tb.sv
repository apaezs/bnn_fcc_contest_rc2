`timescale 1ns/1ps

module skid_buffer_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int DATA_W = 64,
    parameter int KEEP_W = DATA_W / 8
);
    typedef struct packed {
        logic [DATA_W-1:0] data;
        logic [KEEP_W-1:0] keep;
        logic              last;
    } beat_t;

    logic              clk;
    logic              rst;
    logic              s_valid;
    logic              s_ready;
    logic [DATA_W-1:0] s_data;
    logic [KEEP_W-1:0] s_keep;
    logic              s_last;
    logic              m_valid;
    logic              m_ready;
    logic [DATA_W-1:0] m_data;
    logic [KEEP_W-1:0] m_keep;
    logic              m_last;

    Skid_Buffer #(
        .DATA_W(DATA_W),
        .KEEP_W(KEEP_W)
    ) DUT (
        .*
    );

    function automatic beat_t random_beat();
        automatic beat_t beat;
        begin
            beat.data = $urandom;
            if (DATA_W > 32)
                beat.data[DATA_W-1:32] = $urandom;

            beat.keep = $urandom;
            beat.last = $urandom;
            return beat;
        end
    endfunction

    initial begin : generate_clock
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    logic accepted_src = 1'b0;
    beat_t current_src_beat;
    beat_t model_queue[$];
    bit src_busy;
    int launched_count;

    initial begin
        rst          <= 1'b1;
        s_valid      <= 1'b0;
        s_data       <= '0;
        s_keep       <= '0;
        s_last       <= 1'b0;
        m_ready      <= 1'b0;
        src_busy     = 1'b0;
        launched_count = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;

        while (launched_count < NUM_TESTS || src_busy || model_queue.size() > 0 || m_valid) begin
            m_ready <= $urandom;

            if (src_busy && accepted_src)
                src_busy = 1'b0;

            if (!src_busy && launched_count < NUM_TESTS && $urandom_range(0, 1)) begin
                current_src_beat = random_beat();
                s_valid          <= 1'b1;
                s_data           <= current_src_beat.data;
                s_keep           <= current_src_beat.keep;
                s_last           <= current_src_beat.last;
                src_busy         = 1'b1;
                launched_count++;
            end else if (!src_busy) begin
                s_valid <= 1'b0;
                s_data  <= '0;
                s_keep  <= '0;
                s_last  <= 1'b0;
            end

            @(posedge clk);
        end

        disable generate_clock;
        $display("Tests Completed.");
    end

    always_ff @(posedge clk or posedge rst)
        if (rst) accepted_src <= 1'b0;
        else accepted_src <= s_valid && s_ready;

    // tiny queue model
    always_ff @(posedge clk or posedge rst)
        if (rst) model_queue = {};
        else begin
            automatic int size = model_queue.size();

            if (m_valid && m_ready) begin
                if (size == 0) begin
                    $error("Read occurred when the model queue was empty.");
                end else begin
                    automatic beat_t correct_beat = model_queue.pop_front();
                    if (m_data !== correct_beat.data ||
                        m_keep !== correct_beat.keep ||
                        m_last !== correct_beat.last)
                        $error("Output mismatch: got data=%h keep=%h last=%0b exp data=%h keep=%h last=%0b",
                               m_data, m_keep, m_last,
                               correct_beat.data, correct_beat.keep, correct_beat.last);
                end
            end

            if (s_valid && s_ready)
                model_queue.push_back('{data : s_data, keep : s_keep, last : s_last});
        end

    assert property (@(posedge clk) disable iff (rst) model_queue.size() <= 1);

    assert property (@(posedge clk) disable iff (rst) m_valid && !m_ready
                     |=> m_valid && $stable(m_data) && $stable(m_keep) && $stable(m_last));

    // make sure we really hit input and output handshakes
    cp_input_handshake :
    cover property (@(posedge clk) disable iff (rst) s_valid && s_ready);
    cp_output_handshake :
    cover property (@(posedge clk) disable iff (rst) m_valid && m_ready);

    // also hit backpressure and an input stall
    cp_output_backpressure :
    cover property (@(posedge clk) disable iff (rst) m_valid && !m_ready);
    cp_input_stall :
    cover property (@(posedge clk) disable iff (rst) s_valid && !s_ready);

    // real skid case: take one beat, hold it, then drain it
    cp_skid_capture :
    cover property (@(posedge clk) disable iff (rst) s_valid && s_ready && !m_ready);
    cp_simultaneous_replace :
    cover property (@(posedge clk) disable iff (rst) s_valid && s_ready && m_valid && m_ready);

endmodule
