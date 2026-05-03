module NP_Pop_unit #(
    parameter int iwidth = 8,
    parameter int owidth = 8
)(
    input  logic                    clk,

    input  logic [iwidth - 1:0]     x,
    (* shreg_extract = "no" *) output logic [owidth - 1:0] count
);

    localparam int STAGES = (iwidth <= 1) ? 1 : $clog2(iwidth);

    localparam int CUT1 = (STAGES <= 1) ? 1 : ((STAGES + 4) / 5);
    localparam int CUT2 = (STAGES <= 2) ? STAGES : ((2 * STAGES + 4) / 5);
    localparam int CUT3 = (STAGES <= 3) ? STAGES : ((3 * STAGES + 4) / 5);
    localparam int CUT4 = (STAGES <= 4) ? STAGES : ((4 * STAGES + 4) / 5);

    localparam int ELEMS1 = (iwidth + (1 << CUT1) - 1) >> CUT1;
    localparam int ELEMS2 = (iwidth + (1 << CUT2) - 1) >> CUT2;
    localparam int ELEMS3 = (iwidth + (1 << CUT3) - 1) >> CUT3;
    localparam int ELEMS4 = (iwidth + (1 << CUT4) - 1) >> CUT4;

    logic [owidth - 1:0] count_next;
    (* shreg_extract = "no" *) logic [owidth - 1:0] count_pre;
    (* shreg_extract = "no" *) logic [owidth - 1:0] count_mid;

    logic [owidth - 1:0] stage_a [0:CUT1][0:iwidth-1];
    logic [owidth - 1:0] reg1 [0:ELEMS1-1];
    logic [owidth - 1:0] stage_b [CUT1:CUT2][0:iwidth-1];
    logic [owidth - 1:0] reg2 [0:ELEMS2-1];
    logic [owidth - 1:0] stage_c [CUT2:CUT3][0:iwidth-1];
    logic [owidth - 1:0] reg3 [0:ELEMS3-1];
    logic [owidth - 1:0] stage_d [CUT3:CUT4][0:iwidth-1];
    logic [owidth - 1:0] reg4 [0:ELEMS4-1];
    logic [owidth - 1:0] stage_e [CUT4:STAGES][0:iwidth-1];

    always_comb begin
        integer s_a;
        integer k_a;
        integer elems_a;
        integer pairs_a;

        for (s_a = 0; s_a <= CUT1; s_a++) begin
            for (k_a = 0; k_a < iwidth; k_a++) begin
                stage_a[s_a][k_a] = '0;
            end
        end

        for (k_a = 0; k_a < iwidth; k_a++) begin
            stage_a[0][k_a] = {{(owidth-1){1'b0}}, x[k_a]};
        end

        for (s_a = 0; s_a < CUT1; s_a++) begin
            elems_a = (iwidth + (1 << s_a) - 1) >> s_a;
            pairs_a = elems_a >> 1;

            for (k_a = 0; k_a < pairs_a; k_a++) begin
                stage_a[s_a+1][k_a] = stage_a[s_a][2*k_a] + stage_a[s_a][2*k_a + 1];
            end

            if (elems_a[0]) begin
                stage_a[s_a+1][pairs_a] = stage_a[s_a][elems_a - 1];
            end
        end
    end

    always_ff @(posedge clk) begin
        integer k_r1;
        for (k_r1 = 0; k_r1 < ELEMS1; k_r1++) begin
            reg1[k_r1] <= stage_a[CUT1][k_r1];
        end
    end

    always_comb begin
        integer s_b;
        integer k_b;
        integer elems_b;
        integer pairs_b;

        for (s_b = CUT1; s_b <= CUT2; s_b++) begin
            for (k_b = 0; k_b < iwidth; k_b++) begin
                stage_b[s_b][k_b] = '0;
            end
        end

        for (k_b = 0; k_b < ELEMS1; k_b++) begin
            stage_b[CUT1][k_b] = reg1[k_b];
        end

        for (s_b = CUT1; s_b < CUT2; s_b++) begin
            elems_b = (iwidth + (1 << s_b) - 1) >> s_b;
            pairs_b = elems_b >> 1;

            for (k_b = 0; k_b < pairs_b; k_b++) begin
                stage_b[s_b+1][k_b] = stage_b[s_b][2*k_b] + stage_b[s_b][2*k_b + 1];
            end

            if (elems_b[0]) begin
                stage_b[s_b+1][pairs_b] = stage_b[s_b][elems_b - 1];
            end
        end
    end

    always_ff @(posedge clk) begin
        integer k_r2;
        for (k_r2 = 0; k_r2 < ELEMS2; k_r2++) begin
            reg2[k_r2] <= stage_b[CUT2][k_r2];
        end
    end

    always_comb begin
        integer s_c;
        integer k_c;
        integer elems_c;
        integer pairs_c;

        for (s_c = CUT2; s_c <= CUT3; s_c++) begin
            for (k_c = 0; k_c < iwidth; k_c++) begin
                stage_c[s_c][k_c] = '0;
            end
        end

        for (k_c = 0; k_c < ELEMS2; k_c++) begin
            stage_c[CUT2][k_c] = reg2[k_c];
        end

        for (s_c = CUT2; s_c < CUT3; s_c++) begin
            elems_c = (iwidth + (1 << s_c) - 1) >> s_c;
            pairs_c = elems_c >> 1;

            for (k_c = 0; k_c < pairs_c; k_c++) begin
                stage_c[s_c+1][k_c] = stage_c[s_c][2*k_c] + stage_c[s_c][2*k_c + 1];
            end

            if (elems_c[0]) begin
                stage_c[s_c+1][pairs_c] = stage_c[s_c][elems_c - 1];
            end
        end
    end

    always_ff @(posedge clk) begin
        integer k_r3;
        for (k_r3 = 0; k_r3 < ELEMS3; k_r3++) begin
            reg3[k_r3] <= stage_c[CUT3][k_r3];
        end
    end

    always_comb begin
        integer s_d;
        integer k_d;
        integer elems_d;
        integer pairs_d;

        for (s_d = CUT3; s_d <= CUT4; s_d++) begin
            for (k_d = 0; k_d < iwidth; k_d++) begin
                stage_d[s_d][k_d] = '0;
            end
        end

        for (k_d = 0; k_d < ELEMS3; k_d++) begin
            stage_d[CUT3][k_d] = reg3[k_d];
        end

        for (s_d = CUT3; s_d < CUT4; s_d++) begin
            elems_d = (iwidth + (1 << s_d) - 1) >> s_d;
            pairs_d = elems_d >> 1;

            for (k_d = 0; k_d < pairs_d; k_d++) begin
                stage_d[s_d+1][k_d] = stage_d[s_d][2*k_d] + stage_d[s_d][2*k_d + 1];
            end

            if (elems_d[0]) begin
                stage_d[s_d+1][pairs_d] = stage_d[s_d][elems_d - 1];
            end
        end
    end

    always_ff @(posedge clk) begin
        integer k_r4;
        for (k_r4 = 0; k_r4 < ELEMS4; k_r4++) begin
            reg4[k_r4] <= stage_d[CUT4][k_r4];
        end
    end

    always_comb begin
        integer s_e;
        integer k_e;
        integer elems_e;
        integer pairs_e;

        for (s_e = CUT4; s_e <= STAGES; s_e++) begin
            for (k_e = 0; k_e < iwidth; k_e++) begin
                stage_e[s_e][k_e] = '0;
            end
        end

        for (k_e = 0; k_e < ELEMS4; k_e++) begin
            stage_e[CUT4][k_e] = reg4[k_e];
        end

        for (s_e = CUT4; s_e < STAGES; s_e++) begin
            elems_e = (iwidth + (1 << s_e) - 1) >> s_e;
            pairs_e = elems_e >> 1;

            for (k_e = 0; k_e < pairs_e; k_e++) begin
                stage_e[s_e+1][k_e] = stage_e[s_e][2*k_e] + stage_e[s_e][2*k_e + 1];
            end

            if (elems_e[0]) begin
                stage_e[s_e+1][pairs_e] = stage_e[s_e][elems_e - 1];
            end
        end

        count_next = stage_e[STAGES][0];
    end

    always_ff @(posedge clk) begin
        count_pre <= count_next;
    end

    always_ff @(posedge clk) begin
        count_mid <= count_pre;
    end

    always_ff @(posedge clk) begin
        count <= count_mid;
    end

endmodule
