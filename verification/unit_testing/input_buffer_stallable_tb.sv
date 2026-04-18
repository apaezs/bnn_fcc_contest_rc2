// input buffer stallable tb
// same basic style as fifo_tb

`timescale 1ns/1ps

module input_buffer_stallable_model #(
    parameter int IB_WIDTH = 8,
    parameter int PW       = 8,
    parameter int TN       = 64,
    localparam int MEM_NEEDED = (TN + PW - 1) / PW,
    localparam int ADDR_W     = (MEM_NEEDED <= 1) ? 1 : $clog2(MEM_NEEDED)
)(
    input  logic              clk,
    input  logic              rst,
    input  logic              buffer_write,
    input  logic [ADDR_W-1:0] raddr,
    input  logic              read_bank_sel,
    input  logic              clear_bank0,
    input  logic              clear_bank1,
    input  logic [PW-1:0]     istream,
    output logic [PW-1:0]     ostream,
    output logic              start_allowed_bank0,
    output logic              start_allowed_bank1,
    output logic              write_bank_sel_out,
    output logic              stall
);
    logic              write_bank_sel;
    logic              pending_switch_bank;
    logic [ADDR_W-1:0] wr_addr_bank0;
    logic [ADDR_W-1:0] wr_addr_bank1;
    logic [ADDR_W:0]   bram_size_bank0;
    logic [ADDR_W:0]   bram_size_bank1;
    logic              bank0_full_r;
    logic              bank1_full_r;
    logic              buffer_write_reg0;
    logic [PW-1:0]     istream_reg0;
    logic [ADDR_W-1:0] raddr_reg0;
    logic              read_bank_sel_reg0;
    logic              write_accept_bank0;
    logic              write_accept_bank1;
    logic              bank0_full_write;
    logic              bank1_full_write;
    logic              bank0_empty;
    logic              bank1_empty;
    logic [PW-1:0]     ostream_bank0;
    logic [PW-1:0]     ostream_bank1;
    logic              bank0_mem_wen;
    logic [ADDR_W-1:0] bank0_mem_addr;
    logic [PW-1:0]     bank0_mem_wdata;
    logic              bank1_mem_wen;
    logic [ADDR_W-1:0] bank1_mem_addr;
    logic [PW-1:0]     bank1_mem_wdata;
    logic              bank0_mem_wen_r;
    logic [ADDR_W-1:0] bank0_mem_addr_r;
    logic [PW-1:0]     bank0_mem_wdata_r;
    logic              bank1_mem_wen_r;
    logic [ADDR_W-1:0] bank1_mem_addr_r;
    logic [PW-1:0]     bank1_mem_wdata_r;
    logic [PW-1:0]     mem_bank0 [0:MEM_NEEDED-1];
    logic [PW-1:0]     mem_bank1 [0:MEM_NEEDED-1];

    assign bank0_empty = (bram_size_bank0 == '0);
    assign bank1_empty = (bram_size_bank1 == '0);
    assign write_bank_sel_out  = write_bank_sel;
    assign start_allowed_bank0 = bank0_full_r;
    assign start_allowed_bank1 = bank1_full_r;

    always_ff @(posedge clk) begin
        buffer_write_reg0  <= buffer_write;
        istream_reg0       <= istream;
        raddr_reg0         <= raddr;
        read_bank_sel_reg0 <= read_bank_sel;
    end

    assign write_accept_bank0 = buffer_write_reg0 && !write_bank_sel && !bank0_full_r;
    assign write_accept_bank1 = buffer_write_reg0 &&  write_bank_sel && !bank1_full_r;
    assign bank0_full_write   = write_accept_bank0 && (bram_size_bank0 == MEM_NEEDED - 1);
    assign bank1_full_write   = write_accept_bank1 && (bram_size_bank1 == MEM_NEEDED - 1);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_bank_sel      <= 1'b0;
            pending_switch_bank <= 1'b0;
            stall               <= 1'b0;
        end else begin
            if (stall) begin
                if ((pending_switch_bank == 1'b0 && bank0_empty) ||
                    (pending_switch_bank == 1'b1 && bank1_empty)) begin
                    write_bank_sel      <= pending_switch_bank;
                    pending_switch_bank <= 1'b0;
                    stall               <= 1'b0;
                end
            end else begin
                if (bank0_full_write) begin
                    if (bank1_empty) begin
                        write_bank_sel      <= 1'b1;
                        pending_switch_bank <= 1'b0;
                    end else begin
                        pending_switch_bank <= 1'b1;
                        stall               <= 1'b1;
                    end
                end else if (bank1_full_write) begin
                    if (bank0_empty) begin
                        write_bank_sel      <= 1'b0;
                        pending_switch_bank <= 1'b0;
                    end else begin
                        pending_switch_bank <= 1'b0;
                        stall               <= 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            wr_addr_bank0 <= '0;
        else begin
            if (clear_bank0)
                wr_addr_bank0 <= '0;
            else if (write_accept_bank0)
                wr_addr_bank0 <= wr_addr_bank0 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            wr_addr_bank1 <= '0;
        else begin
            if (clear_bank1)
                wr_addr_bank1 <= '0;
            else if (write_accept_bank1)
                wr_addr_bank1 <= wr_addr_bank1 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bram_size_bank0 <= '0;
        else begin
            if (clear_bank0)
                bram_size_bank0 <= '0;
            else if (write_accept_bank0)
                bram_size_bank0 <= bram_size_bank0 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bram_size_bank1 <= '0;
        else begin
            if (clear_bank1)
                bram_size_bank1 <= '0;
            else if (write_accept_bank1)
                bram_size_bank1 <= bram_size_bank1 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bank0_full_r <= 1'b0;
        else begin
            if (clear_bank0)
                bank0_full_r <= 1'b0;
            else if (bank0_full_write)
                bank0_full_r <= 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bank1_full_r <= 1'b0;
        else begin
            if (clear_bank1)
                bank1_full_r <= 1'b0;
            else if (bank1_full_write)
                bank1_full_r <= 1'b1;
        end
    end

    assign bank0_mem_wen   = write_accept_bank0;
    assign bank0_mem_addr  = write_accept_bank0 ? wr_addr_bank0 : raddr_reg0;
    assign bank0_mem_wdata = istream_reg0;
    assign bank1_mem_wen   = write_accept_bank1;
    assign bank1_mem_addr  = write_accept_bank1 ? wr_addr_bank1 : raddr_reg0;
    assign bank1_mem_wdata = istream_reg0;

    always_ff @(posedge clk) begin
        bank0_mem_wen_r   <= bank0_mem_wen;
        bank0_mem_addr_r  <= bank0_mem_addr;
        bank0_mem_wdata_r <= bank0_mem_wdata;
        bank1_mem_wen_r   <= bank1_mem_wen;
        bank1_mem_addr_r  <= bank1_mem_addr;
        bank1_mem_wdata_r <= bank1_mem_wdata;
    end

    always_ff @(posedge clk) begin
        if (bank0_mem_wen_r)
            mem_bank0[bank0_mem_addr_r] <= bank0_mem_wdata_r;
        ostream_bank0 <= mem_bank0[bank0_mem_addr_r];

        if (bank1_mem_wen_r)
            mem_bank1[bank1_mem_addr_r] <= bank1_mem_wdata_r;
        ostream_bank1 <= mem_bank1[bank1_mem_addr_r];
    end

    always_comb begin
        if (read_bank_sel_reg0)
            ostream = ostream_bank1;
        else
            ostream = ostream_bank0;
    end
endmodule

module input_buffer_stallable_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int PW = 8,
    parameter int TN = 32
);
    localparam int DEPTH = (TN + PW - 1) / PW;
    localparam int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    logic              clk;
    logic              rst;
    logic              buffer_write;
    logic [ADDR_W-1:0] raddr;
    logic              read_bank_sel;
    logic              clear_bank0;
    logic              clear_bank1;
    logic [PW-1:0]     istream;
    logic [PW-1:0]     ostream_dut;
    logic              start_allowed_bank0_dut;
    logic              start_allowed_bank1_dut;
    logic              write_bank_sel_out_dut;
    logic              stall_dut;
    logic [PW-1:0]     ostream_ref;
    logic              start_allowed_bank0_ref;
    logic              start_allowed_bank1_ref;
    logic              write_bank_sel_out_ref;
    logic              stall_ref;
    logic              check_en;

    Input_Buffer_Stallable #(
        .PW(PW),
        .TN(TN)
    ) DUT (
        .clk                (clk),
        .rst                (rst),
        .buffer_write       (buffer_write),
        .raddr              (raddr),
        .read_bank_sel      (read_bank_sel),
        .clear_bank0        (clear_bank0),
        .clear_bank1        (clear_bank1),
        .istream            (istream),
        .ostream            (ostream_dut),
        .start_allowed_bank0(start_allowed_bank0_dut),
        .start_allowed_bank1(start_allowed_bank1_dut),
        .write_bank_sel_out (write_bank_sel_out_dut),
        .stall              (stall_dut)
    );

    input_buffer_stallable_model #(
        .PW(PW),
        .TN(TN)
    ) REF (
        .clk                (clk),
        .rst                (rst),
        .buffer_write       (buffer_write),
        .raddr              (raddr),
        .read_bank_sel      (read_bank_sel),
        .clear_bank0        (clear_bank0),
        .clear_bank1        (clear_bank1),
        .istream            (istream),
        .ostream            (ostream_ref),
        .start_allowed_bank0(start_allowed_bank0_ref),
        .start_allowed_bank1(start_allowed_bank1_ref),
        .write_bank_sel_out (write_bank_sel_out_ref),
        .stall              (stall_ref)
    );

    initial begin : generate_clock
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    task automatic warmup();
        begin
            clear_bank0   <= 1'b0;
            clear_bank1   <= 1'b0;
            read_bank_sel <= 1'b0;
            raddr         <= '0;
            buffer_write  <= 1'b1;

            for (int i = 0; i < 2*DEPTH + 8; i++) begin
                istream <= PW'(i + 1);
                @(posedge clk);
            end

            clear_bank0  <= 1'b1;
            @(posedge clk);
            clear_bank0  <= 1'b0;
            buffer_write <= 1'b0;
            istream      <= '0;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        rst          <= 1'b1;
        buffer_write <= 1'b0;
        raddr        <= '0;
        read_bank_sel <= 1'b0;
        clear_bank0  <= 1'b0;
        clear_bank1  <= 1'b0;
        istream      <= '0;
        check_en     <= 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;

        warmup();
        check_en <= 1'b1;

        for (int i = 0; i < NUM_TESTS; i++) begin
            buffer_write  <= $urandom;
            raddr         <= $urandom_range(0, DEPTH-1);
            read_bank_sel <= $urandom;
            clear_bank0   <= ($urandom_range(0, 15) == 0);
            clear_bank1   <= ($urandom_range(0, 15) == 0);
            istream       <= $urandom;
            @(posedge clk);
        end

        disable generate_clock;
        $display("Tests Completed.");
    end

    assert property (@(posedge clk) disable iff (rst || !check_en) ostream_dut == ostream_ref);
    assert property (@(posedge clk) disable iff (rst || !check_en) start_allowed_bank0_dut == start_allowed_bank0_ref);
    assert property (@(posedge clk) disable iff (rst || !check_en) start_allowed_bank1_dut == start_allowed_bank1_ref);
    assert property (@(posedge clk) disable iff (rst || !check_en) write_bank_sel_out_dut == write_bank_sel_out_ref);
    assert property (@(posedge clk) disable iff (rst || !check_en) stall_dut == stall_ref);

    cp_write :
    cover property (@(posedge clk) buffer_write);
    cp_clear_bank0 :
    cover property (@(posedge clk) clear_bank0);
    cp_clear_bank1 :
    cover property (@(posedge clk) clear_bank1);
    cp_bank0_full :
    cover property (@(posedge clk) start_allowed_bank0_dut);
    cp_bank1_full :
    cover property (@(posedge clk) start_allowed_bank1_dut);
    cp_stall :
    cover property (@(posedge clk) stall_dut);
    cp_bank_switch :
    cover property (@(posedge clk) write_bank_sel_out_dut != $past(write_bank_sel_out_dut));

endmodule
