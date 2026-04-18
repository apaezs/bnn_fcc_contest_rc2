`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module BRAM_LUT_SINK #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 8,
    localparam int DEPTH = 1 << ADDR_W
)(
    input  logic                 clk,
    input  logic                 ren,
    input  logic                 wen,
    input  logic [ADDR_W-1:0]    addr,
    input  logic [DATA_W-1:0]    wdata,
    output logic [DATA_W-1:0]    rdata
);

  (* ram_style = "distributed" *) logic [DATA_W-1:0] mem [0:DEPTH-1];

  logic              ren_reg_0;
  logic              wen_reg_0;
  logic [ADDR_W-1:0] addr_reg_0;
  logic [DATA_W-1:0] wdata_reg_0;

  always_ff @(posedge clk) begin
    ren_reg_0   <= ren;
    wen_reg_0   <= wen;
    addr_reg_0  <= addr;
    wdata_reg_0 <= wdata;
  end

  always_ff @(posedge clk) begin
    if (wen_reg_0)
      mem[addr_reg_0] <= wdata_reg_0;

    if (ren_reg_0)
      rdata <= mem[addr_reg_0];
  end

endmodule
