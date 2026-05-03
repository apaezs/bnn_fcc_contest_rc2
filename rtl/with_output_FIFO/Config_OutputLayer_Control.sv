`timescale 1ns / 1ps

module Config_OutputLayer_Control #(
    parameter int LAYER_ID  = 0,
    parameter int LAYER_W   = 1,
    parameter int PN        = 8,
    parameter int PW        = 8,
    parameter int TN        = 16,
    parameter int N_NEURONS = 16,

    localparam int BEATS    = (TN + PW - 1) / PW,
    localparam int GROUPS   = (N_NEURONS + PN - 1) / PN,
    localparam int W_ADDR_W = (GROUPS * BEATS <= 1) ? 1 : $clog2(GROUPS * BEATS),
    localparam int BANK_W   = (PN <= 1) ? 1 : $clog2(PN),
    localparam int TOTAL_W_WORDS = N_NEURONS * BEATS,
    localparam int WCOUNT_W = (TOTAL_W_WORDS <= 1) ? 1 : $clog2(TOTAL_W_WORDS + 1),
    localparam int BEAT_W   = (BEATS <= 1) ? 1 : $clog2(BEATS),
    localparam int W_BYTES_PER_NEURON = (TN + 7) / 8,
    localparam int BYTE_PIPE_DELAY    = 3

)(
    input  logic clk,
    input  logic rst,

    input  logic               msg_valid,
    input  logic [LAYER_W-1:0] msg_layer,
    input  logic               msg_type,
    input  logic               payload_valid,
    input  logic [7:0]         payload_data,

    output logic               payload_ready,
    output logic                w_cfg_valid,
    output logic [BANK_W-1:0]   w_cfg_bank,
    output logic [W_ADDR_W-1:0] w_cfg_addr,
    output logic [PW-1:0]       w_cfg_data,
    output logic cfg_done
);

    logic                          msg_ready;

    logic [WCOUNT_W-1:0]           w_word_count_r;
    logic                          w_word_count_bump_r, w_word_count_bump_next;

    logic                          cfg_done_r, cfg_done_next;
    logic                          have_weights_r, have_weights_next;

    logic                          w_start_r, w_start_next;
    logic                          w_done_r,  w_done_next;
    logic                          w_active_r;
    logic                          w_fill_active_r;

    logic [BEAT_W-1:0]             w_beat_idx_r;
    logic [BANK_W-1:0]             w_bank_idx_r;
    logic [W_ADDR_W-1:0]           w_addr_base_r;
    logic [W_ADDR_W-1:0]           w_addr_base_inc_r;

    logic                          byte_valid_r, byte_valid_next;
    logic [7:0]                    w_launch_byte_r;
    logic [7:0]                    w_delayed_byte;

    logic                          w_adv_last_beat_r;
    logic                          w_adv_last_word_r;
    logic                          w_adv_bump_base_r;

    logic [7:0]                    w_neuron_bytes_r [0:W_BYTES_PER_NEURON-1];

    logic                          w_prep_valid_r;
    logic [BANK_W-1:0]             w_prep_bank_r;
    logic [W_ADDR_W-1:0]           w_prep_addr_r;
    logic [PW-1:0]                 w_prep_data_r;

    logic                          w_issue_valid_r;
    logic [BANK_W-1:0]             w_issue_bank_r;
    logic [W_ADDR_W-1:0]           w_issue_addr_r;
    logic [PW-1:0]                 w_issue_data_r;

    logic                          payload_sink_valid_r, payload_sink_valid_next;
    logic [7:0]                    payload_sink_data_r;

    logic                          msg_sink_valid_r, msg_sink_valid_next;
    logic [LAYER_W-1:0]            msg_sink_layer_r;


    logic                          build_w_in_valid_r;
    logic                          build_w_in_valid_next;
    logic                          build_w_out_valid;
    logic [PW-1:0]                 build_w_out_data;

    logic                          w_byte_write_valid;
    logic [W_BYTES_PER_NEURON-1:0] w_byte_write_en;
    logic                          w_byte_write_full;

    logic msg_sink_push_fire;
    logic payload_sink_push_fire;
    logic msg_match_fire;

    logic w_launch_fire;
    logic run_launch_fire;

    assign w_launch_fire = w_fill_active_r && payload_sink_valid_r;

    Build_W #(
        .PW(PW),
        .TN(TN)
    ) u_build_w (
        .clk         (clk),
        .in_valid    (build_w_in_valid_r),
        .beat_idx    (w_beat_idx_r),
        .neuron_bytes(w_neuron_bytes_r),
        .out_data    (build_w_out_data),
        .out_valid   (build_w_out_valid)
    );

    Byte_Index #(
        .N_SLOTS(W_BYTES_PER_NEURON)
    ) u_byte_index (
        .clk        (clk),
        .valid_in   (byte_valid_r),
        .clear      (w_start_r),
        .rst        (rst),
        .write_valid(w_byte_write_valid),
        .write_en   (w_byte_write_en),
        .write_full (w_byte_write_full)
    );

    Delay_ALWAYS #(
        .DWIDTH(8),
        .DELAY (BYTE_PIPE_DELAY)
    ) u_weight_byte_delay (
        .clk (clk),
        .din (w_launch_byte_r),
        .dout(w_delayed_byte)
    );

    assign run_launch_fire       = msg_sink_valid_r && !w_active_r;
    assign msg_match_fire         = (msg_layer == LAYER_ID[LAYER_W-1:0]);
    assign msg_sink_push_fire     = msg_valid && msg_ready;
    assign payload_sink_push_fire = payload_valid && payload_ready;

    always_comb begin
        cfg_done_next           = cfg_done_r;
        have_weights_next       = have_weights_r;

        w_start_next            = 1'b0;
        w_done_next             = 1'b0;

        build_w_in_valid_next   = 1'b0;
        w_word_count_bump_next  = 1'b0;
        byte_valid_next         = 1'b0;

        payload_sink_valid_next = payload_sink_valid_r;
        msg_sink_valid_next     = msg_sink_valid_r;

        w_cfg_valid             = w_issue_valid_r;
        w_cfg_bank              = w_issue_bank_r;
        w_cfg_addr              = w_issue_addr_r;
        w_cfg_data              = w_issue_data_r;

        msg_ready               = !msg_sink_valid_r && msg_match_fire;
        payload_ready           = !payload_sink_valid_r;
        cfg_done                = cfg_done_r;

        if (msg_sink_push_fire)
            msg_sink_valid_next = 1'b1;

        if (run_launch_fire) begin
            msg_sink_valid_next = 1'b0;
            cfg_done_next       = 1'b0;
            w_start_next        = 1'b1;
        end

        if (payload_sink_push_fire)
            payload_sink_valid_next = 1'b1;

        if (w_launch_fire) begin
            byte_valid_next         = 1'b1;
            payload_sink_valid_next = 1'b0;
        end

        if (w_byte_write_valid && w_byte_write_full)
            build_w_in_valid_next = 1'b1;
        else if (w_prep_valid_r && !w_adv_last_beat_r)
            build_w_in_valid_next = 1'b1;

        if (w_issue_valid_r)
            w_word_count_bump_next = 1'b1;

        if (w_adv_last_word_r) begin
            have_weights_next = 1'b1;
            w_done_next       = 1'b1;
            cfg_done_next     = 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cfg_done_r     <= 1'b0;
            have_weights_r <= 1'b0;
            msg_sink_valid_r     <= 1'b0;
            payload_sink_valid_r <= 1'b0;
            w_active_r           <= 1'b0;
            w_fill_active_r      <= 1'b0;
        end else begin
            cfg_done_r     <= cfg_done_next;
            have_weights_r <= have_weights_next;
            msg_sink_valid_r     <= msg_sink_valid_next;
            payload_sink_valid_r <= payload_sink_valid_next;

            if (w_done_r)
                w_active_r <= 1'b0;
            else if (w_start_r)
                w_active_r <= 1'b1;

            if (w_start_r)
                w_fill_active_r <= 1'b1;
            else if (w_byte_write_full)
                w_fill_active_r <= 1'b0;
            else if (w_prep_valid_r) begin
                if (!w_adv_last_beat_r)
                    w_fill_active_r <= 1'b0;
                else if (w_adv_last_word_r)
                    w_fill_active_r <= 1'b0;
                else
                    w_fill_active_r <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        w_start_r <= w_start_next;
        w_done_r  <= w_done_next;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            build_w_in_valid_r  <= 1'b0;
            w_word_count_bump_r <= 1'b0;
            byte_valid_r        <= 1'b0;
            w_launch_byte_r     <= '0;
        end else begin
            build_w_in_valid_r  <= build_w_in_valid_next;
            w_word_count_bump_r <= w_word_count_bump_next;
            byte_valid_r        <= byte_valid_next;

            if (w_launch_fire)
                w_launch_byte_r <= payload_sink_data_r;
        end
    end

    always_ff @(posedge clk) begin
        if (msg_sink_push_fire) begin
            msg_sink_layer_r <= msg_layer;
        end

        if (payload_sink_push_fire)
            payload_sink_data_r <= payload_data;
    end

    always_ff @(posedge clk) begin
        if (w_start_r)
            w_addr_base_r <= '0;
        else if (w_prep_valid_r && w_adv_bump_base_r)
            w_addr_base_r <= w_addr_base_inc_r;
    end

    always_ff @(posedge clk) begin
        if (w_start_r)
            w_bank_idx_r <= '0;
        else if (w_prep_valid_r && w_adv_last_beat_r)
            w_bank_idx_r <= w_bank_idx_r + 1'b1;
    end

    always_ff @(posedge clk) begin
        if (w_start_r)
            w_beat_idx_r <= '0;
        else if (w_prep_valid_r) begin
            if (!w_adv_last_beat_r)
                w_beat_idx_r <= w_beat_idx_r + 1'b1;
            else
                w_beat_idx_r <= '0;
        end
    end

    always_ff @(posedge clk) begin
        if (w_start_r)
            w_word_count_r <= '0;
        else
            w_word_count_r <= w_word_count_r + w_word_count_bump_r;
    end

    always_ff @(posedge clk) begin
        integer i;
            for (i = 0; i < W_BYTES_PER_NEURON; i++) begin
                if (w_byte_write_en[i])
                    w_neuron_bytes_r[i] <= w_delayed_byte;
            end
        
    end

    always_ff @(posedge clk) begin
        w_addr_base_inc_r <= w_addr_base_r + BEATS;

        w_adv_last_beat_r <= (w_beat_idx_r == BEATS-1);
        w_adv_last_word_r <= (w_word_count_r + 1'b1 == TOTAL_W_WORDS);
        w_adv_bump_base_r <= (w_beat_idx_r == BEATS-1) && (w_bank_idx_r == PN-1) && !((w_word_count_r + 1'b1) == TOTAL_W_WORDS);

        w_prep_valid_r <= build_w_out_valid;
        w_prep_bank_r  <= w_bank_idx_r;
        w_prep_addr_r  <= w_addr_base_r + w_beat_idx_r;
        w_prep_data_r  <= build_w_out_data;

        w_issue_valid_r <= w_prep_valid_r;
        w_issue_bank_r  <= w_prep_bank_r;
        w_issue_addr_r  <= w_prep_addr_r;
        w_issue_data_r  <= w_prep_data_r;
    end

endmodule