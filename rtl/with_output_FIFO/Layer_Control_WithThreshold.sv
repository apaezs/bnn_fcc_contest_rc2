`timescale 1ns / 1ps

module Layer_Control_WithThreshold #(

    parameter int LAYER_ID = 0,
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int TN = 16,
    parameter int N_NEURONS = 16,
    parameter int TW = 32,
    localparam int beats   = (TN + PW - 1) / PW,
    localparam int BEAT_W  = (beats <= 1) ? 1 : $clog2(beats),
    localparam int GROUPS  = (N_NEURONS + PN - 1) / PN,
    localparam int TW_addr = (GROUPS <= 1) ? 1 : $clog2(GROUPS),
    localparam int W_addr  = (beats * GROUPS <= 1) ? 1 : $clog2(beats * GROUPS),
    localparam int GRP_W   = (GROUPS <= 1) ? 1 : $clog2(GROUPS)

)(
    input  logic clk,
    input  logic rst,

    input  logic start_allowed_bank0,
    input  logic start_allowed_bank1,
    input  logic write_bank_sel,

    output logic read_bank_sel,
    output logic clear_bank0,
    output logic clear_bank1,
    output logic [BEAT_W-1:0] buffer_raddr,
    output logic                t_ram_b_ren,
    output logic [W_addr-1:0]   w_ram_b_addr,
    output logic [TW_addr-1:0]  t_ram_b_addr,
    output logic valid_in,
    output logic last_in
);

    logic [BEAT_W-1:0] beat_idx;
    logic [GRP_W-1:0]  group_idx;
    logic active_bank;
    logic stream_active_r;
    logic issue;
    logic last_issue;
    logic issue_d;
    logic last_issue_d;

    logic write_bank_sel_reg0;

    logic               t_ram_b_ren_c;
    logic [W_addr-1:0]  w_ram_b_addr_c;
    logic [TW_addr-1:0] t_ram_b_addr_c;
    logic               valid_in_c;
    logic               last_in_c;

    logic               t_ram_b_ren_reg0;
    logic [W_addr-1:0]  w_ram_b_addr_reg0;
    logic [TW_addr-1:0] t_ram_b_addr_reg0;

    logic               t_ram_b_ren_reg1;
    logic [W_addr-1:0]  w_ram_b_addr_reg1;
    logic [TW_addr-1:0] t_ram_b_addr_reg1;
    logic bank_ready;
    logic start_fire;
    logic stream_fire;
    logic last_beat_fire;
    logic last_group_fire;
    logic group_advance_fire;
    logic done_fire;

    int local_weight_addr;

    assign read_bank_sel = active_bank;
    assign bank_ready          = (write_bank_sel_reg0 == 1'b0) ? start_allowed_bank1 : start_allowed_bank0;

    assign start_fire          = !stream_active_r && bank_ready;
    assign stream_fire         = stream_active_r;
    assign last_group_fire     = (group_idx == GROUPS - 1);
    assign last_beat_fire      = (beat_idx == beats - 1);
    assign done_fire           = last_beat_fire && last_group_fire;
    assign issue      = stream_fire;
    assign last_issue = (beat_idx == beats - 1);

    assign clear_bank0 = (beat_idx == beats-2) && (group_idx == GROUPS-1) && (active_bank == 1'b0);

    assign clear_bank1 = (beat_idx == beats-2) && (group_idx == GROUPS-1) && (active_bank == 1'b1);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            beat_idx            <= '0;
            group_idx           <= '0;
            active_bank         <= 1'b0;
            stream_active_r     <= 1'b0;
            issue_d             <= 1'b0;
            write_bank_sel_reg0 <= 1'b0;

        end else begin
            write_bank_sel_reg0 <= write_bank_sel;
            issue_d             <= issue;

            if (start_fire) begin
                active_bank     <= ~write_bank_sel_reg0;
                stream_active_r <= 1'b1;
            end 
            
            if (stream_fire)
                beat_idx <= beat_idx + 1;
                
            if (last_beat_fire) begin
                beat_idx  <= '0;
                group_idx <= group_idx + 1;
            end

            if (done_fire) begin
                stream_active_r <= 1'b0;
                beat_idx        <= '0;
                group_idx       <= '0;
             end
        end
    end

    always_ff @(posedge clk) begin
        last_issue_d <= last_issue;
    end

    Delay #(
        .DWIDTH(1),
        .DELAY(3)
    ) u_valid_in_delay (
        .clk (clk),
        .rst (rst),
        .din (valid_in_c),
        .dout(valid_in)
    );

    Delay_ALWAYS #(
        .DWIDTH(1),
        .DELAY(3)
    ) u_last_in_delay (
        .clk (clk),
        .din (last_in_c),
        .dout(last_in)
    );

    always_ff @(posedge clk) begin
        buffer_raddr <= beat_idx;
        t_ram_b_ren_reg0  <= t_ram_b_ren_c;
        w_ram_b_addr_reg0 <= w_ram_b_addr_c;
        t_ram_b_addr_reg0 <= t_ram_b_addr_c;
        t_ram_b_ren_reg1  <= t_ram_b_ren_reg0;
        w_ram_b_addr_reg1 <= w_ram_b_addr_reg0;
        t_ram_b_addr_reg1 <= t_ram_b_addr_reg0;
        t_ram_b_ren  <= t_ram_b_ren_reg1;
        w_ram_b_addr <= w_ram_b_addr_reg1;
        t_ram_b_addr <= t_ram_b_addr_reg1;
    end

    always_comb begin
        t_ram_b_ren_c  = 1'b0;
        w_ram_b_addr_c = '0;
        t_ram_b_addr_c = '0;

        if (last_beat_fire) begin
            t_ram_b_ren_c  = issue;
        end

        t_ram_b_addr_c = group_idx;
        local_weight_addr = group_idx * beats + beat_idx;
        w_ram_b_addr_c    = local_weight_addr[W_addr-1:0];
    end

    always_comb begin
        valid_in_c = issue_d;
        last_in_c  = last_issue_d;
    end

endmodule
