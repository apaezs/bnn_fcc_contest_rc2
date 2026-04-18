`timescale 1ns/1ps

module BRAM_LUT_ALWAYS #(
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

  (* ram_style = "distributed" *) logic [DATA_W-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (wen) mem[addr] <= wdata;
    rdata <= mem[addr];
  end

endmodule
