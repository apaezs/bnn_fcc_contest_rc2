`timescale 1ns / 1ps

module Build_W #(
    parameter int PW = 8,
    parameter int TN = 16,

    localparam int W_BYTES_PER_NEURON = (TN + 7) / 8,
    localparam int BEATS              = (TN + PW - 1) / PW,
    localparam int BEAT_W             = (BEATS <= 1) ? 1 : $clog2(BEATS),

    localparam int PW_BYTES           = PW / 8,
    localparam int BASE_BYTE_W        = (W_BYTES_PER_NEURON <= 1) ? 1 : $clog2(W_BYTES_PER_NEURON),
    localparam int LAST_BEAT_BITS     = TN - ((BEATS - 1) * PW)
)(
    input  logic clk,

    input  logic in_valid,
    input  logic [BEAT_W-1:0] beat_idx,
    input  logic [7:0]        neuron_bytes [0:W_BYTES_PER_NEURON-1],
    output logic [PW-1:0] out_data,
    output logic          out_valid
);
    localparam int LOWER_W     = PW / 2;
    localparam int UPPER_W     = PW - LOWER_W;
    localparam int LOWER_BYTES = LOWER_W / 8;
    localparam int UPPER_BYTES = UPPER_W / 8;

    logic [BEAT_W-1:0] beat_idx_s0;
    logic [7:0]        neuron_bytes_s0 [0:W_BYTES_PER_NEURON-1];
    logic              valid_s0;

    logic [BASE_BYTE_W-1:0] base_byte_s1;
    logic [BEAT_W-1:0]      beat_idx_s1;
    logic [7:0]             beat_bytes_s1 [0:PW_BYTES-1];
    logic                   valid_s1;

    logic [LOWER_W-1:0]     lower_half_s2;
    logic [BEAT_W-1:0]      beat_idx_s2;
    logic [7:0]             beat_bytes_s2 [0:PW_BYTES-1];
    logic                   valid_s2;

    logic [LOWER_W-1:0]     lower_half_s3;
    logic [UPPER_W-1:0]     upper_half_s3;
    logic                   valid_s3;

    (* shreg_extract = "no" *) logic [PW-1:0] word_s4;
    logic                      valid_s4;

    function automatic [7:0] get_byte_or_ones(
        input logic [7:0] byte_arr [0:W_BYTES_PER_NEURON-1],
        input int idx
    );
        begin
            if ((idx >= 0) && (idx < W_BYTES_PER_NEURON))
                get_byte_or_ones = byte_arr[idx];
            else
                get_byte_or_ones = 8'hFF;
        end
    endfunction

    function automatic [7:0] apply_last_byte_mask(
        input logic [7:0] in_byte,
        input int         beat_idx_f,
        input int         byte_in_beat
    );
        automatic logic [7:0] masked;
        automatic int abs_byte_idx;
        automatic int bits_before_this_byte;
        automatic int valid_bits_this_byte;
        begin
            masked = in_byte;

            if (beat_idx_f == (BEATS - 1)) begin
                abs_byte_idx          = beat_idx_f * PW_BYTES + byte_in_beat;
                bits_before_this_byte = abs_byte_idx * 8;
                valid_bits_this_byte  = TN - bits_before_this_byte;

                if (valid_bits_this_byte <= 0) begin
                    masked = 8'hFF;
                end
                else if (valid_bits_this_byte < 8) begin
                    case (valid_bits_this_byte)
                        1: masked = {7'b1111111, in_byte[0]};
                        2: masked = {6'b111111,  in_byte[1:0]};
                        3: masked = {5'b11111,   in_byte[2:0]};
                        4: masked = {4'b1111,    in_byte[3:0]};
                        5: masked = {3'b111,     in_byte[4:0]};
                        6: masked = {2'b11,      in_byte[5:0]};
                        7: masked = {1'b1,       in_byte[6:0]};
                        default: masked = in_byte;
                    endcase
                end
            end

            apply_last_byte_mask = masked;
        end
    endfunction

    always_ff @(posedge clk) begin
        integer i;
        beat_idx_s0 <= beat_idx;
        for (i = 0; i < W_BYTES_PER_NEURON; i++) begin
            neuron_bytes_s0[i] <= neuron_bytes[i];
        end
        valid_s0 <= in_valid;
    end

    always_ff @(posedge clk) begin
        integer i;
        integer src_idx;

        base_byte_s1 <= beat_idx_s0 * PW_BYTES;
        beat_idx_s1  <= beat_idx_s0;

        for (i = 0; i < PW_BYTES; i++) begin
            src_idx = (beat_idx_s0 * PW_BYTES) + i;
            beat_bytes_s1[i] <= get_byte_or_ones(neuron_bytes_s0, src_idx);
        end

        valid_s1 <= valid_s0;
    end

    always_ff @(posedge clk) begin
        integer i;

        for (i = 0; i < LOWER_BYTES; i++) begin
            lower_half_s2[i*8 +: 8] <= apply_last_byte_mask(
                beat_bytes_s1[i],
                beat_idx_s1,
                i
            );
        end

        beat_idx_s2 <= beat_idx_s1;
        for (i = 0; i < PW_BYTES; i++) begin
            beat_bytes_s2[i] <= beat_bytes_s1[i];
        end
        valid_s2 <= valid_s1;
    end

    always_ff @(posedge clk) begin
        integer i;

        lower_half_s3 <= lower_half_s2;

        for (i = 0; i < UPPER_BYTES; i++) begin
            upper_half_s3[i*8 +: 8] <= apply_last_byte_mask(
                beat_bytes_s2[LOWER_BYTES + i],
                beat_idx_s2,
                LOWER_BYTES + i
            );
        end

        valid_s3 <= valid_s2;
    end

    always_ff @(posedge clk) begin
        word_s4  <= {upper_half_s3, lower_half_s3};
        valid_s4 <= valid_s3;
    end

    always_ff @(posedge clk) begin
        out_data  <= word_s4;
        out_valid <= valid_s4;
    end

endmodule
