`timescale 1ns / 1ps

module Config_Manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS    = 3
)(
    input  logic clk,
    input  logic rst,

    input  logic [BUS_WIDTH-1:0]   config_data_in,
    input  logic                   config_valid,
    input  logic [BUS_WIDTH/8-1:0] config_keep,
    input  logic                   config_last,
    input  logic                        payload_ready,

    output logic                   config_ready,
    output logic                        msg_valid,
    output logic [$clog2(LAYERS)-1:0]   msg_layer,
    output logic                        msg_type,
    output logic                        payload_valid,
    output logic [7:0]                  payload_data
);

    localparam int BUS_BYTES    = BUS_WIDTH / 8;
    localparam int BYTE_IDX_W   = (BUS_BYTES <= 1) ? 1 : $clog2(BUS_BYTES);
    localparam int HEADER_BYTES = 16;

    typedef enum logic [1:0] {
        S_HEADER_FETCH,
        S_HEADER_CONSUME,
        S_PAYLOAD_FETCH,
        S_PAYLOAD_CONSUME
    } state_t;

    (* fsm_encoding = "one-hot" *) state_t state_r, state_next;

    logic [BUS_WIDTH-1:0] beat_data_r;
    logic [BUS_BYTES-1:0] beat_keep_r;
    logic                 beat_valid_r;

    logic [BYTE_IDX_W-1:0] byte_idx_r;

    logic       byte_pipe_valid_r;
    logic [7:0] byte_pipe_data_r;

    logic payload_tag_last_r;

    logic [4:0] header_count_r;

    logic                      msg_valid_r;
    logic                      msg_type_r;
    logic [$clog2(LAYERS)-1:0] msg_layer_r;
    logic [14:0]               payload_bytes_left_r;

    logic       payload_out_valid_r;
    logic [7:0] payload_out_data_r;
    logic       payload_out_last_r;

    logic payload_ready_sink_r;

    logic issue_payload_byte_r;

    logic [BYTE_IDX_W-1:0] byte_select_idx_r;
    logic                  byte_select_is_payload_r;

    logic begin_sel_fire_r;

    logic [7:0] selected_byte_data_c;
    logic       selected_byte_valid_c;

    always_comb begin
        selected_byte_data_c  = beat_data_r[8*byte_select_idx_r +: 8];
        selected_byte_valid_c = beat_keep_r[byte_select_idx_r];
    end

    always_comb begin
        state_next = state_r;

        unique case (state_r)
            S_HEADER_FETCH: begin
                if (beat_valid_r)
                    state_next = S_HEADER_CONSUME;
            end

            S_HEADER_CONSUME: begin
                 if (byte_pipe_valid_r)
                    state_next = S_HEADER_FETCH;
            end

            S_PAYLOAD_FETCH: begin
                if (payload_out_valid_r && payload_ready_sink_r) begin
                    if (payload_out_last_r)
                        state_next = S_HEADER_FETCH;
                end else if (!payload_out_valid_r && beat_valid_r) begin
                    state_next = S_PAYLOAD_CONSUME;
                end
            end

            S_PAYLOAD_CONSUME: begin
                if (payload_out_valid_r && payload_ready_sink_r) begin
                    if (payload_out_last_r)
                        state_next = S_HEADER_FETCH;
                end else if (byte_pipe_valid_r) begin
                    state_next = S_PAYLOAD_FETCH;
                end
            end
            
            default: begin
                state_next = S_HEADER_FETCH;
            end
        endcase
        if (byte_pipe_valid_r && (header_count_r == HEADER_BYTES-1)) 
            state_next = S_PAYLOAD_FETCH;
        
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_r             <= S_HEADER_FETCH;
            beat_valid_r        <= 1'b0;
            byte_pipe_valid_r   <= 1'b0;
            begin_sel_fire_r    <= 1'b0;
            payload_out_valid_r <= 1'b0;
            payload_out_last_r  <= 1'b0;
            payload_tag_last_r  <= 1'b0;
            msg_valid_r         <= 1'b0;
            msg_type_r          <= 1'b0;
        end else begin
            state_r          <= state_next;
            msg_valid_r      <= 1'b0;
            begin_sel_fire_r <= ((state_r == S_HEADER_FETCH) || ((state_r == S_PAYLOAD_FETCH) && !payload_out_valid_r && beat_valid_r));

            if (config_valid && config_ready) begin
                beat_data_r  <= config_data_in;
                beat_keep_r  <= config_keep;
                beat_valid_r <= 1'b1;
                byte_idx_r   <= '0;
            end

            if ((state_r == S_HEADER_FETCH) && !beat_valid_r) begin
                header_count_r           <= '0;
                payload_out_valid_r      <= 1'b0;
                payload_out_last_r       <= 1'b0;
                byte_pipe_valid_r        <= 1'b0;
                payload_tag_last_r       <= 1'b0;
                byte_select_idx_r        <= '0;
                byte_select_is_payload_r <= 1'b0;
            end

            if ((state_r == S_HEADER_FETCH) && beat_valid_r) begin
                byte_select_idx_r        <= byte_idx_r;
                byte_select_is_payload_r <= 1'b0;

                if (byte_idx_r == BYTE_IDX_W'(BUS_BYTES-1)) begin
                    beat_valid_r <= 1'b0;
                    byte_idx_r   <= '0;
                end else begin
                    byte_idx_r <= byte_idx_r + 1'b1;
                end
            end

            if ((state_r == S_PAYLOAD_FETCH) && !payload_out_valid_r && beat_valid_r) begin
                byte_select_idx_r        <= byte_idx_r;
                byte_select_is_payload_r <= 1'b1;

                if (byte_idx_r == BYTE_IDX_W'(BUS_BYTES-1)) begin
                    beat_valid_r <= 1'b0;
                    byte_idx_r   <= '0;
                end else begin
                    byte_idx_r <= byte_idx_r + 1'b1;
                end
            end

            if (begin_sel_fire_r) begin
                byte_pipe_valid_r <= selected_byte_valid_c;

                if (byte_select_is_payload_r)
                    payload_tag_last_r <= (payload_bytes_left_r == 15'd1);
            end

            if ((state_r == S_HEADER_CONSUME) && byte_pipe_valid_r) header_count_r <= header_count_r + 1'b1;
            
            unique case (header_count_r)
                5'd0: msg_type_r <= byte_pipe_data_r[0];
                5'd1: msg_layer_r <= byte_pipe_data_r[$clog2(LAYERS)-1:0];
                5'd8: payload_bytes_left_r[7:0]  <= byte_pipe_data_r;
                5'd9: payload_bytes_left_r[14:8] <= byte_pipe_data_r[6:0];
            default: begin
                end
            endcase
            if (payload_out_valid_r && payload_ready_sink_r) begin
                payload_out_valid_r <= 1'b0;
                payload_out_last_r  <= 1'b0;
            end

            if ((state_r == S_PAYLOAD_CONSUME) && !payload_out_valid_r && byte_pipe_valid_r) begin
                payload_out_valid_r  <= 1'b1;
            end
            payload_out_last_r   <= payload_tag_last_r;

            if (issue_payload_byte_r) payload_bytes_left_r <= payload_bytes_left_r - 15'd1;

            payload_out_data_r <= byte_pipe_data_r;

            if(byte_pipe_valid_r && header_count_r == HEADER_BYTES - 1) begin
                header_count_r      <= '0;
                msg_valid_r         <= 1'b1;
                payload_out_valid_r <= 1'b0;
                payload_out_last_r  <= 1'b0;
                payload_tag_last_r  <= 1'b0; 
            end
            if(byte_pipe_valid_r) begin 
                byte_pipe_valid_r <= '0;
            end
        end
    end

    always_ff @(posedge clk) begin
        payload_ready_sink_r <= payload_ready;
        issue_payload_byte_r <= 1'b0;

        if ((state_r == S_PAYLOAD_CONSUME) && !payload_out_valid_r && byte_pipe_valid_r)
            issue_payload_byte_r <= 1'b1;
    end

    always_ff @(posedge clk) begin
        byte_pipe_data_r <= selected_byte_data_c;
    end

    always_comb begin
        msg_valid     = msg_valid_r;
        msg_layer     = msg_layer_r;
        msg_type      = msg_type_r;

        payload_valid = payload_out_valid_r;
        payload_data  = payload_out_data_r;

        config_ready  = !beat_valid_r;
    end

endmodule
