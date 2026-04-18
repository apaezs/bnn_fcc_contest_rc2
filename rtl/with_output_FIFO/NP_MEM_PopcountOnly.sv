`timescale 1ns/1ps

module NP_MEM_PopcountOnly #(
    parameter int LAYER_ID           = 0,
    parameter int LANE_ID            = 0,
    parameter int PW                 = 32,
    parameter int TOTAL_BITS_NEURON  = 64,
    parameter int W_ADDR_W           = 8,
    parameter int LAT                = 4,
    localparam int ACC_W             = $clog2(TOTAL_BITS_NEURON+1)
)(
    input  logic clk,
    input  logic rst,

    input  logic                valid_in,
    input  logic                last_in,
    input  logic [PW-1:0]       x_in,
    input  logic [W_ADDR_W-1:0] w_ram_b_addr,

    input  logic                w_ram_ren_a,
    input  logic                w_ram_wen_a,
    input  logic [W_ADDR_W-1:0] w_ram_a_addr,
    input  logic [PW-1:0]       w_ram_a_data,
    output logic [PW-1:0]       w_ram_a_rdata,

    output logic [ACC_W-1:0]    popcount_total,
    output logic                valid_acc
);

  logic                valid_in_r;
  logic                last_in_r;
  logic [PW-1:0]       x_in_r;
  logic [W_ADDR_W-1:0] w_ram_b_addr_r;
  logic                valid_in_np;
  logic                last_in_np;
  logic [PW-1:0]       x_in_np;
  logic                valid_in_np2;
  logic                last_in_np2;
  logic [PW-1:0]       x_in_np2;
  logic                w_ram_ren_a_r;
  logic                w_ram_wen_a_r;
  logic [W_ADDR_W-1:0] w_ram_a_addr_r;
  logic [PW-1:0]       w_ram_a_data_r;
  logic [PW-1:0]       w_ram_b_rdata;
  logic                w_mem_wen;
  logic [W_ADDR_W-1:0] w_mem_addr;
  logic [PW-1:0]       w_mem_wdata;
  logic [PW-1:0]       w_mem_rdata;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      valid_in_r <= 1'b0;
    end else begin
      valid_in_r <= valid_in;
    end
  end

  always_ff @(posedge clk) begin
    x_in_r         <= x_in;
    w_ram_b_addr_r <= w_ram_b_addr;
    last_in_r      <= last_in;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      valid_in_np <= 1'b0;
      last_in_np  <= 1'b0;
    end else begin
      valid_in_np <= valid_in_r;
      last_in_np  <= last_in_r;
    end
  end

  always_ff @(posedge clk) begin
    x_in_np <= x_in_r;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      valid_in_np2 <= 1'b0;
      last_in_np2  <= 1'b0;
    end else begin
      valid_in_np2 <= valid_in_np;
      last_in_np2  <= last_in_np;
    end
  end

  always_ff @(posedge clk) begin
    x_in_np2 <= x_in_np;
  end

  always_ff @(posedge clk) begin
    w_ram_ren_a_r  <= w_ram_ren_a;
    w_ram_wen_a_r  <= w_ram_wen_a;
    w_ram_a_addr_r <= w_ram_a_addr;
    w_ram_a_data_r <= w_ram_a_data;
  end

  assign w_mem_wen   = w_ram_wen_a_r;
  assign w_mem_addr  = w_ram_wen_a_r ? w_ram_a_addr_r : w_ram_b_addr_r;
  assign w_mem_wdata = w_ram_a_data_r;

  (* keep_hierarchy = "yes" *)
  BRAM_SINK #(
    .DATA_W(PW),
    .ADDR_W(W_ADDR_W)
  ) u_w_ram (
    .clk   (clk),
    .wen   (w_mem_wen),
    .addr  (w_mem_addr),
    .wdata (w_mem_wdata),
    .rdata (w_mem_rdata)
  );

  assign w_ram_a_rdata = w_mem_rdata;
  assign w_ram_b_rdata = w_mem_rdata;

  NP_UNIT_PopcountOnly #(
    .LAYER_ID          (LAYER_ID),
    .LANE_ID           (LANE_ID),
    .PW                (PW),
    .TOTAL_BITS_NEURON (TOTAL_BITS_NEURON),
    .LAT               (LAT)
  ) u_np (
    .clk           (clk),
    .rst           (rst),
    .valid_in      (valid_in_np2),
    .last_in       (last_in_np2),
    .x             (x_in_np2),
    .w             (w_ram_b_rdata),
    .popcount_total(popcount_total),
    .valid_acc     (valid_acc)
  );

endmodule
