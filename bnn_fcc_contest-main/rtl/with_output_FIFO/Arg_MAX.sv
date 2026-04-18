`timescale 1ns / 1ps

module Arg_MAX #(
    parameter int act_w      = 10,
    parameter int popcount_w = 9,
    parameter int out_w      = 8
)(
    input  logic clk,
    input  logic rst,

    input  logic en,
    input  logic [act_w-1:0][popcount_w-1:0] popcount,

    output logic [out_w-1:0] bcc_out,
    output logic             out_valid
);

    logic [act_w-1:0][popcount_w-1:0] popcount_s;
    logic                             en_s;

    (* shreg_extract = "no" *) logic [4:0]                    r1_sel;
    (* shreg_extract = "no" *) logic [4:0][popcount_w-1:0]   r1s_val0;
    (* shreg_extract = "no" *) logic [4:0][popcount_w-1:0]   r1s_val1;
    (* shreg_extract = "no" *) logic [4:0][out_w-1:0]        r1s_idx0;
    (* shreg_extract = "no" *) logic [4:0][out_w-1:0]        r1s_idx1;

    (* shreg_extract = "no" *) logic [4:0][popcount_w-1:0]   r1_val;
    (* shreg_extract = "no" *) logic [4:0][out_w-1:0]        r1_idx;

    (* shreg_extract = "no" *) logic                         r2_sel_0;
    (* shreg_extract = "no" *) logic                         r2_sel_1;

    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r2s0_val0;
    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r2s0_val1;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r2s0_idx0;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r2s0_idx1;

    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r2s1_val0;
    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r2s1_val1;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r2s1_idx0;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r2s1_idx1;

    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r2_pass_val;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r2_pass_idx;

    (* shreg_extract = "no" *) logic [2:0][popcount_w-1:0]  r2_val;
    (* shreg_extract = "no" *) logic [2:0][out_w-1:0]       r2_idx;

    (* shreg_extract = "no" *) logic                         r3_sel;
    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r3s_val0;
    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r3s_val1;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r3s_idx0;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r3s_idx1;

    (* shreg_extract = "no" *) logic [1:0][popcount_w-1:0]  r3_val;
    (* shreg_extract = "no" *) logic [1:0][out_w-1:0]       r3_idx;

    (* shreg_extract = "no" *) logic                         r4_sel;
    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r4s_val0;
    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r4s_val1;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r4s_idx0;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r4s_idx1;

    (* shreg_extract = "no" *) logic [popcount_w-1:0]       r4_val;
    (* shreg_extract = "no" *) logic [out_w-1:0]            r4_idx;

    logic [4:0]                    r1_sel_next;
    logic [4:0][popcount_w-1:0]    r1s_val0_next;
    logic [4:0][popcount_w-1:0]    r1s_val1_next;
    logic [4:0][out_w-1:0]         r1s_idx0_next;
    logic [4:0][out_w-1:0]         r1s_idx1_next;

    logic [4:0][popcount_w-1:0]    r1_val_next;
    logic [4:0][out_w-1:0]         r1_idx_next;

    logic                          r2_sel_0_next;
    logic                          r2_sel_1_next;

    logic [popcount_w-1:0]         r2s0_val0_next;
    logic [popcount_w-1:0]         r2s0_val1_next;
    logic [out_w-1:0]              r2s0_idx0_next;
    logic [out_w-1:0]              r2s0_idx1_next;

    logic [popcount_w-1:0]         r2s1_val0_next;
    logic [popcount_w-1:0]         r2s1_val1_next;
    logic [out_w-1:0]              r2s1_idx0_next;
    logic [out_w-1:0]              r2s1_idx1_next;

    logic [popcount_w-1:0]         r2_pass_val_next;
    logic [out_w-1:0]              r2_pass_idx_next;

    logic [2:0][popcount_w-1:0]    r2_val_next;
    logic [2:0][out_w-1:0]         r2_idx_next;

    logic                          r3_sel_next;
    logic [popcount_w-1:0]         r3s_val0_next;
    logic [popcount_w-1:0]         r3s_val1_next;
    logic [out_w-1:0]              r3s_idx0_next;
    logic [out_w-1:0]              r3s_idx1_next;

    logic [1:0][popcount_w-1:0]    r3_val_next;
    logic [1:0][out_w-1:0]         r3_idx_next;

    logic                          r4_sel_next;
    logic [popcount_w-1:0]         r4s_val0_next;
    logic [popcount_w-1:0]         r4s_val1_next;
    logic [out_w-1:0]              r4s_idx0_next;
    logic [out_w-1:0]              r4s_idx1_next;

    logic [popcount_w-1:0]         r4_val_next;
    logic [out_w-1:0]              r4_idx_next;

    logic en_reg_0;
    logic en_reg_1;
    logic en_reg_2;
    logic en_reg_3;
    logic en_reg_4;
    logic en_reg_5;
    logic en_reg_6;
    logic en_reg_7;

    integer i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            en_s <= 1'b0;
        end else begin
            en_s <= en;
        end

        for (i = 0; i < act_w; i = i + 1) begin
            popcount_s[i] <= popcount[i];
        end
    end

    always_comb begin
        r1_sel_next[0]   = (popcount_s[1] > popcount_s[0]);
        r1s_val0_next[0] = popcount_s[0];
        r1s_val1_next[0] = popcount_s[1];
        r1s_idx0_next[0] = out_w'(0);
        r1s_idx1_next[0] = out_w'(1);

        r1_sel_next[1]   = (popcount_s[3] > popcount_s[2]);
        r1s_val0_next[1] = popcount_s[2];
        r1s_val1_next[1] = popcount_s[3];
        r1s_idx0_next[1] = out_w'(2);
        r1s_idx1_next[1] = out_w'(3);

        r1_sel_next[2]   = (popcount_s[5] > popcount_s[4]);
        r1s_val0_next[2] = popcount_s[4];
        r1s_val1_next[2] = popcount_s[5];
        r1s_idx0_next[2] = out_w'(4);
        r1s_idx1_next[2] = out_w'(5);

        r1_sel_next[3]   = (popcount_s[7] > popcount_s[6]);
        r1s_val0_next[3] = popcount_s[6];
        r1s_val1_next[3] = popcount_s[7];
        r1s_idx0_next[3] = out_w'(6);
        r1s_idx1_next[3] = out_w'(7);

        r1_sel_next[4]   = (popcount_s[9] > popcount_s[8]);
        r1s_val0_next[4] = popcount_s[8];
        r1s_val1_next[4] = popcount_s[9];
        r1s_idx0_next[4] = out_w'(8);
        r1s_idx1_next[4] = out_w'(9);
    end

    always_comb begin
        for (int j = 0; j < 5; j = j + 1) begin
            if (r1_sel[j]) begin
                r1_val_next[j] = r1s_val1[j];
                r1_idx_next[j] = r1s_idx1[j];
            end else begin
                r1_val_next[j] = r1s_val0[j];
                r1_idx_next[j] = r1s_idx0[j];
            end
        end
    end

    always_comb begin
        r2_sel_0_next = (r1_val[1] > r1_val[0]);
        r2_sel_1_next = (r1_val[3] > r1_val[2]);

        r2s0_val0_next = r1_val[0];
        r2s0_val1_next = r1_val[1];
        r2s0_idx0_next = r1_idx[0];
        r2s0_idx1_next = r1_idx[1];

        r2s1_val0_next = r1_val[2];
        r2s1_val1_next = r1_val[3];
        r2s1_idx0_next = r1_idx[2];
        r2s1_idx1_next = r1_idx[3];

        r2_pass_val_next = r1_val[4];
        r2_pass_idx_next = r1_idx[4];
    end

    always_comb begin
        if (r2_sel_0) begin
            r2_val_next[0] = r2s0_val1;
            r2_idx_next[0] = r2s0_idx1;
        end else begin
            r2_val_next[0] = r2s0_val0;
            r2_idx_next[0] = r2s0_idx0;
        end

        if (r2_sel_1) begin
            r2_val_next[1] = r2s1_val1;
            r2_idx_next[1] = r2s1_idx1;
        end else begin
            r2_val_next[1] = r2s1_val0;
            r2_idx_next[1] = r2s1_idx0;
        end

        r2_val_next[2] = r2_pass_val;
        r2_idx_next[2] = r2_pass_idx;
    end

    always_comb begin
        r3_sel_next   = (r2_val[1] > r2_val[0]);
        r3s_val0_next = r2_val[0];
        r3s_val1_next = r2_val[1];
        r3s_idx0_next = r2_idx[0];
        r3s_idx1_next = r2_idx[1];
    end

    always_comb begin
        if (r3_sel) begin
            r3_val_next[0] = r3s_val1;
            r3_idx_next[0] = r3s_idx1;
        end else begin
            r3_val_next[0] = r3s_val0;
            r3_idx_next[0] = r3s_idx0;
        end

        r3_val_next[1] = r2_val[2];
        r3_idx_next[1] = r2_idx[2];
    end

    always_comb begin
        r4_sel_next   = (r3_val[1] > r3_val[0]);
        r4s_val0_next = r3_val[0];
        r4s_val1_next = r3_val[1];
        r4s_idx0_next = r3_idx[0];
        r4s_idx1_next = r3_idx[1];
    end

    always_comb begin
        if (r4_sel) begin
            r4_val_next = r4s_val1;
            r4_idx_next = r4s_idx1;
        end else begin
            r4_val_next = r4s_val0;
            r4_idx_next = r4s_idx0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            en_reg_0  <= 1'b0;
            en_reg_1  <= 1'b0;
            en_reg_2  <= 1'b0;
            en_reg_3  <= 1'b0;
            en_reg_4  <= 1'b0;
            en_reg_5  <= 1'b0;
            en_reg_6  <= 1'b0;
            en_reg_7  <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            en_reg_0  <= en_s;
            en_reg_1  <= en_reg_0;
            en_reg_2  <= en_reg_1;
            en_reg_3  <= en_reg_2;
            en_reg_4  <= en_reg_3;
            en_reg_5  <= en_reg_4;
            en_reg_6  <= en_reg_5;
            en_reg_7  <= en_reg_6;
            out_valid <= en_reg_7;
        end
    end

    always_ff @(posedge clk) begin
        r1_sel   <= r1_sel_next;
        r1s_val0 <= r1s_val0_next;
        r1s_val1 <= r1s_val1_next;
        r1s_idx0 <= r1s_idx0_next;
        r1s_idx1 <= r1s_idx1_next;

        r1_val <= r1_val_next;
        r1_idx <= r1_idx_next;

        r2_sel_0 <= r2_sel_0_next;
        r2_sel_1 <= r2_sel_1_next;

        r2s0_val0 <= r2s0_val0_next;
        r2s0_val1 <= r2s0_val1_next;
        r2s0_idx0 <= r2s0_idx0_next;
        r2s0_idx1 <= r2s0_idx1_next;

        r2s1_val0 <= r2s1_val0_next;
        r2s1_val1 <= r2s1_val1_next;
        r2s1_idx0 <= r2s1_idx0_next;
        r2s1_idx1 <= r2s1_idx1_next;

        r2_pass_val <= r2_pass_val_next;
        r2_pass_idx <= r2_pass_idx_next;

        r2_val <= r2_val_next;
        r2_idx <= r2_idx_next;

        r3_sel   <= r3_sel_next;
        r3s_val0 <= r3s_val0_next;
        r3s_val1 <= r3s_val1_next;
        r3s_idx0 <= r3s_idx0_next;
        r3s_idx1 <= r3s_idx1_next;

        r3_val <= r3_val_next;
        r3_idx <= r3_idx_next;

        r4_sel   <= r4_sel_next;
        r4s_val0 <= r4s_val0_next;
        r4s_val1 <= r4s_val1_next;
        r4s_idx0 <= r4s_idx0_next;
        r4s_idx1 <= r4s_idx1_next;

        r4_val <= r4_val_next;
        r4_idx <= r4_idx_next;

        bcc_out <= r4_idx;
    end

endmodule
