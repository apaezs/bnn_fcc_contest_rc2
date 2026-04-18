`timescale 1ns/1ps

module NP_Layer_PopcountOnly #(
    parameter int LAYER_ID = 0,
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int TN = 16,
    parameter int N  = 16,
    parameter int LAT = 4,
    localparam int beats       = (TN + PW - 1) / PW,
    localparam int GROUPS      = (N + PN - 1) / PN,
    localparam int W_addr      = (beats * GROUPS <= 1) ? 1 : $clog2(beats * GROUPS),
    localparam int POP_W       = $clog2(TN+1),
    localparam int BANK_W      = (PN <= 1) ? 1 : $clog2(PN),
    localparam int CLUSTERS_RAW = (LAYER_ID == 0) ? 8 : (LAYER_ID == 1) ? 8 : 2,
    localparam int CLUSTERS = (PN < CLUSTERS_RAW) ? PN : CLUSTERS_RAW,
    localparam int LANES_PER_CLUSTER = (PN + CLUSTERS - 1) / CLUSTERS
)(
    input  logic clk,
    input  logic rst,

    input  logic [PW-1:0] input_buffer,

    input  logic                w_cfg_valid,
    input  logic [BANK_W-1:0]   w_cfg_bank,
    input  logic [W_addr-1:0]   w_cfg_addr,
    input  logic [PW-1:0]       w_cfg_data,
    input  logic [W_addr-1:0]   w_ram_b_addr,

    input  logic                valid_in,
    input  logic                last_in,

    output logic [PN-1:0][POP_W-1:0] pop_out,
    output logic [PN-1:0]            valid_acc
);

  logic [PN-1:0][POP_W-1:0] raw_pop_out;
  logic                w_cfg_valid_reg_0;
  logic [BANK_W-1:0]   w_cfg_bank_reg_0;
  logic [W_addr-1:0]   w_cfg_addr_reg_0;
  logic [PW-1:0]       w_cfg_data_reg_0;
  logic [PN-1:0][PW-1:0]      w_ram_a_data_local;
  logic [PN-1:0][W_addr-1:0]  w_ram_a_addr_local;
  logic [PN-1:0]              w_ram_wen_a_local;

  logic [CLUSTERS-1:0] valid_tree;

  logic [CLUSTERS-1:0] last_tree;

  logic [CLUSTERS-1:0][W_addr-1:0] w_addr_tree;
  logic [CLUSTERS-1:0][PW-1:0]     input_buffer_tree;

  integer k;

  always_ff @(posedge clk) begin
    w_cfg_valid_reg_0 <= w_cfg_valid;
    w_cfg_bank_reg_0  <= w_cfg_bank;
    w_cfg_addr_reg_0  <= w_cfg_addr;
    w_cfg_data_reg_0  <= w_cfg_data;
  end

  always_comb begin
    for (k = 0; k < PN; k++) begin
      w_ram_wen_a_local[k]  = w_cfg_valid_reg_0 && (w_cfg_bank_reg_0 == k[BANK_W-1:0]);
      w_ram_a_addr_local[k] = w_cfg_addr_reg_0;
      w_ram_a_data_local[k] = w_cfg_data_reg_0;
    end
  end

  fanout_tree #(
    .DWIDTH  (1),
    .CLUSTERS(CLUSTERS)
  ) u_valid_tree (
    .clk (clk),
    .rst (rst),
    .din (valid_in),
    .dout(valid_tree)
  );

  fanout_tree_ALWAYS #(
    .DWIDTH  (1),
    .CLUSTERS(CLUSTERS)
  ) u_last_tree (
    .clk (clk),
    .din (last_in),
    .dout(last_tree)
  );

  fanout_tree_ALWAYS #(
    .DWIDTH  (W_addr),
    .CLUSTERS(CLUSTERS)
  ) u_w_addr_tree (
    .clk (clk),
    .din (w_ram_b_addr),
    .dout(w_addr_tree)
  );

  fanout_tree_ALWAYS #(
    .DWIDTH  (PW),
    .CLUSTERS(CLUSTERS)
  ) u_input_tree (
    .clk (clk),
    .din (input_buffer),
    .dout(input_buffer_tree)
  );

  assign pop_out = raw_pop_out;

  genvar i;
  generate
    for (i = 0; i < PN; i++) begin : GEN_NP
      localparam int CL_IDX_RAW = i / LANES_PER_CLUSTER;
      localparam int CL_IDX     = (CL_IDX_RAW >= CLUSTERS) ? (CLUSTERS - 1) : CL_IDX_RAW;

      NP_MEM_PopcountOnly #(
        .LAYER_ID          (LAYER_ID),
        .LANE_ID           (i),
        .PW                (PW),
        .TOTAL_BITS_NEURON (TN),
        .W_ADDR_W          (W_addr),
        .LAT               (LAT)
      ) u_np_mem (
        .clk           (clk),
        .rst           (rst),

        .valid_in      (valid_tree[CL_IDX]),
        .last_in       (last_tree[CL_IDX]),
        .x_in          (input_buffer_tree[CL_IDX]),
        .w_ram_b_addr  (w_addr_tree[CL_IDX]),
        .w_ram_ren_a   (1'b0),
        .w_ram_wen_a   (w_ram_wen_a_local[i]),
        .w_ram_a_addr  (w_ram_a_addr_local[i]),
        .w_ram_a_data  (w_ram_a_data_local[i]),
        .w_ram_a_rdata (),
        .popcount_total(raw_pop_out[i]),
        .valid_acc     (valid_acc[i])
      );
    end
  endgenerate

endmodule
