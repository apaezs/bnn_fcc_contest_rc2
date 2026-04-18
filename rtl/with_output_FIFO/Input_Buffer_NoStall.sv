`timescale 1ns/1ps

module Input_Buffer_NoStall #(
    parameter int LAYER_ID = 0,
    parameter int IB_WIDTH = 8,
    parameter int PW       = 8,
    parameter int TN       = 64,
    localparam int writer_id = LAYER_ID,
    localparam int MEM_NEEDED = (TN + PW - 1) / PW,
    localparam int ADDR_W     = (MEM_NEEDED <= 1) ? 1 : $clog2(MEM_NEEDED)
)(
    input  logic                clk,
    input  logic                rst,

    input  logic                buffer_write,
    input  logic [ADDR_W-1:0]   raddr,
    input  logic                read_bank_sel,
    input  logic                clear_bank0,
    input  logic                clear_bank1,
    input  logic [PW-1:0]       istream,

    output logic [PW-1:0]       ostream,
    output logic                start_allowed_bank0,
    output logic                start_allowed_bank1,
    output logic                write_bank_sel_out
);

    logic              write_bank_sel;
    logic [ADDR_W-1:0] wr_addr_bank0;
    logic [ADDR_W-1:0] wr_addr_bank1;
    logic [ADDR_W:0]   bram_size_bank0;
    logic [ADDR_W:0]   bram_size_bank1;

    logic              bank0_full_r;
    logic              bank1_full_r;

    logic              clear_bank0_reg0;
    logic              clear_bank1_reg0;

    logic              buffer_write_reg0;
    logic [PW-1:0]     istream_reg0;

    logic [ADDR_W-1:0] raddr_reg0;
    logic              read_bank_sel_reg0;
    logic              write_accept_bank0;
    logic              write_accept_bank1;
    logic              bank0_full_write;
    logic              bank1_full_write;
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

    assign write_bank_sel_out   = write_bank_sel;
    assign start_allowed_bank0  = bank0_full_r;
    assign start_allowed_bank1  = bank1_full_r;

    always_ff @(posedge clk) begin
        buffer_write_reg0 <= buffer_write;
        istream_reg0      <= istream;
    end

    always_ff @(posedge clk) begin
        raddr_reg0         <= raddr;
        read_bank_sel_reg0 <= read_bank_sel;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clear_bank0_reg0 <= 1'b0;
            clear_bank1_reg0 <= 1'b0;
        end else begin
            clear_bank0_reg0 <= clear_bank0;
            clear_bank1_reg0 <= clear_bank1;
        end
    end

    assign write_accept_bank0 = buffer_write_reg0 && !write_bank_sel && !bank0_full_r;
    assign write_accept_bank1 = buffer_write_reg0 &&  write_bank_sel && !bank1_full_r;
    assign bank0_full_write = write_accept_bank0 && (bram_size_bank0 == MEM_NEEDED - 1);
    assign bank1_full_write = write_accept_bank1 && (bram_size_bank1 == MEM_NEEDED - 1);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_bank_sel <= 1'b0;
        end else begin
            if (bank0_full_write)
                write_bank_sel <= 1'b1;
            else if (bank1_full_write)
                write_bank_sel <= 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            wr_addr_bank0 <= '0;
        else begin
            if (clear_bank0_reg0)
                wr_addr_bank0 <= '0;
            else if (write_accept_bank0)
                wr_addr_bank0 <= wr_addr_bank0 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            wr_addr_bank1 <= '0;
        else begin
            if (clear_bank1_reg0)
                wr_addr_bank1 <= '0;
            else if (write_accept_bank1)
                wr_addr_bank1 <= wr_addr_bank1 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bram_size_bank0 <= '0;
        else begin
            if (clear_bank0_reg0)
                bram_size_bank0 <= '0;
            else if (write_accept_bank0)
                bram_size_bank0 <= bram_size_bank0 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bram_size_bank1 <= '0;
        else begin
            if (clear_bank1_reg0)
                bram_size_bank1 <= '0;
            else if (write_accept_bank1)
                bram_size_bank1 <= bram_size_bank1 + 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bank0_full_r <= 1'b0;
        else begin
            if (clear_bank0_reg0)
                bank0_full_r <= 1'b0;
            else if (bank0_full_write)
                bank0_full_r <= 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bank1_full_r <= 1'b0;
        else begin
            if (clear_bank1_reg0)
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

    BRAM_LUT_ALWAYS #(
        .DATA_W (PW),
        .ADDR_W (ADDR_W)
    ) u_bram_bank0 (
        .clk   (clk),
        .wen   (bank0_mem_wen_r),
        .addr  (bank0_mem_addr_r),
        .wdata (bank0_mem_wdata_r),
        .rdata (ostream_bank0)
    );

    BRAM_LUT_ALWAYS #(
        .DATA_W (PW),
        .ADDR_W (ADDR_W)
    ) u_bram_bank1 (
        .clk   (clk),
        .wen   (bank1_mem_wen_r),
        .addr  (bank1_mem_addr_r),
        .wdata (bank1_mem_wdata_r),
        .rdata (ostream_bank1)
    );

    always_comb begin
        if (read_bank_sel_reg0)
            ostream = ostream_bank1;
        else
            ostream = ostream_bank0;
    end

endmodule
