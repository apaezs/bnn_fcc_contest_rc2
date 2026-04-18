`timescale 1ns / 1ps

module Byte_Index #(
    parameter int N_SLOTS = 4,
    localparam int COUNT_W = (N_SLOTS <= 1) ? 1 : $clog2(N_SLOTS)
)(
    input  logic               clk,
    input  logic               rst,

    input  logic               valid_in,
    input  logic               clear,
    output logic               write_valid,
    output logic [N_SLOTS-1:0] write_en,
    output logic               write_full
);

    localparam logic [COUNT_W-1:0] MAX_VALUE = N_SLOTS - 1'b1;

    logic valid_s0;
    logic clear_s0;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_s0 <= 1'b0;
        end
        else begin
            valid_s0 <= valid_in;
            clear_s0 <= clear;
        end
    end

    logic [COUNT_W-1:0] pos_r;
    logic [COUNT_W-1:0] pos_s1;
    logic               valid_s1;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_s1 <= 1'b0;
            pos_r    <= '0;
        end
        else begin
            valid_s1 <= valid_s0;

            if (valid_s0) begin
                if (clear_s0) begin
                    pos_s1 <= '0;

                    if (N_SLOTS <= 1)
                        pos_r <= '0;
                    else
                        pos_r <= COUNT_W'(1);
                end
                else begin
                    pos_s1 <= pos_r;

                    if (pos_r == MAX_VALUE)
                        pos_r <= '0;
                    else
                        pos_r <= pos_r + 1'b1;
                end
            end
            else if (clear_s0) begin
                pos_r <= '0;
            end
        end
    end

    logic [N_SLOTS-1:0] write_en_next_s2;
    logic               write_full_next_s2;
    integer i;
    always_comb begin
        write_en_next_s2   = '0;
        write_full_next_s2 = 1'b0;

        for (i = 0; i < N_SLOTS; i++) begin
            if (pos_s1 == COUNT_W'(i))
                write_en_next_s2[i] = 1'b1;
        end

        if (pos_s1 == MAX_VALUE)
            write_full_next_s2 = 1'b1;
    end

    logic [N_SLOTS-1:0] write_en_s3;
    logic               write_full_s3;
    logic               valid_s3;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_s3 <= 1'b0;
        end
        else begin
            valid_s3      <= valid_s1;
            write_en_s3   <= write_en_next_s2;
            write_full_s3 <= write_full_next_s2;
        end
    end

    always_ff @(posedge clk) begin
        write_valid <= valid_s3;
        write_en    <= valid_s3 ? write_en_s3   : '0;
        write_full  <= valid_s3 ? write_full_s3 : 1'b0;
    end

endmodule
