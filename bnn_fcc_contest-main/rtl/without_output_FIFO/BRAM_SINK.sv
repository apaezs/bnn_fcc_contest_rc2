`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module BRAM_SINK #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 8,
    localparam int DEPTH = 1 << ADDR_W
)(
    input  logic                 clk,

    input  logic                 wen,
    input  logic [ADDR_W-1:0]    addr,
    input  logic [DATA_W-1:0]    wdata,
    output logic [DATA_W-1:0]    rdata
);

  logic              wen_r;
  logic [ADDR_W-1:0] addr_r;
  logic [DATA_W-1:0] wdata_r;
  always_ff @(posedge clk) begin
    wen_r   <= wen;
    addr_r  <= addr;
    wdata_r <= wdata;
  end

  xpm_memory_spram #(
    .ADDR_WIDTH_A          (ADDR_W),
    .AUTO_SLEEP_TIME       (0),
    .BYTE_WRITE_WIDTH_A    (DATA_W),
    .CASCADE_HEIGHT        (0),
    .ECC_MODE              ("no_ecc"),
    .MEMORY_INIT_FILE      ("none"),
    .MEMORY_INIT_PARAM     (""),
    .MEMORY_OPTIMIZATION   ("true"),
    .MEMORY_PRIMITIVE      ("block"),
    .MEMORY_SIZE           (DEPTH * DATA_W),
    .MESSAGE_CONTROL       (0),
    .READ_DATA_WIDTH_A     (DATA_W),
    .READ_LATENCY_A        (2),
    .READ_RESET_VALUE_A    ("0"),
    .RST_MODE_A            ("SYNC"),
    .SIM_ASSERT_CHK        (0),
    .USE_MEM_INIT          (0),
    .USE_MEM_INIT_MMI      (0),
    .WAKEUP_TIME           ("disable_sleep"),
    .WRITE_DATA_WIDTH_A    (DATA_W),
    .WRITE_MODE_A          ("read_first")
  ) u_xpm_memory_spram (
    .dbiterra             (),
    .douta                (rdata),
    .sbiterra             (),
    .addra                (addr_r),
    .clka                 (clk),
    .dina                 (wdata_r),
    .ena                  (1'b1),
    .injectdbiterra       (1'b0),
    .injectsbiterra       (1'b0),
    .regcea               (1'b1),
    .rsta                 (1'b0),
    .sleep                (1'b0),
    .wea                  (wen_r)
  );

endmodule
