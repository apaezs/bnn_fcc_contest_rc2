`timescale 1ns/1ps

module FIFO #(
  parameter int W_WIDTH      = 8,
  parameter int R_WIDTH      = 32,
  parameter int DEPTH        = 256
)(
  input  logic                 clk,
  input  logic                 rst,

  input  logic                 wr_en,
  input  logic                 wr_last,
  input  logic [W_WIDTH-1:0]   wr_data,
  input  logic                 rd_en,

  output logic                 full,
  output logic                 almost_full,
  output logic                 rd_valid,
  output logic [R_WIDTH-1:0]   rd_data,
  output logic                 empty
);

  localparam int ADDR_W  = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int COUNT_W = $clog2(DEPTH + 1);
  localparam int W_PER_R = R_WIDTH / W_WIDTH;

  logic [R_WIDTH-1:0] mem [0:DEPTH-1];

  logic [ADDR_W-1:0]  wptr;
  logic [ADDR_W-1:0]  rptr;
  logic [COUNT_W-1:0] word_count;

  logic [R_WIDTH-1:0] pack_buf;

  logic [W_PER_R-1:0] pack_slot;

  logic [R_WIDTH-1:0] assembled_word;
  logic [R_WIDTH-1:0] pack_buf_next;

  logic pack_finishes;
  logic pack_last_slot;

  always_comb begin
    assembled_word = pack_slot[0] ? '0 : pack_buf;

    if (W_PER_R > 0  && pack_slot[0])  assembled_word[(0*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 1  && pack_slot[1])  assembled_word[(1*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 2  && pack_slot[2])  assembled_word[(2*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 3  && pack_slot[3])  assembled_word[(3*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 4  && pack_slot[4])  assembled_word[(4*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 5  && pack_slot[5])  assembled_word[(5*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 6  && pack_slot[6])  assembled_word[(6*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 7  && pack_slot[7])  assembled_word[(7*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 8  && pack_slot[8])  assembled_word[(8*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 9  && pack_slot[9])  assembled_word[(9*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 10 && pack_slot[10]) assembled_word[(10*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 11 && pack_slot[11]) assembled_word[(11*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 12 && pack_slot[12]) assembled_word[(12*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 13 && pack_slot[13]) assembled_word[(13*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 14 && pack_slot[14]) assembled_word[(14*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 15 && pack_slot[15]) assembled_word[(15*W_WIDTH) +: W_WIDTH] = wr_data;
  end

  always_comb begin
    pack_buf_next = pack_slot[0] ? '0 : pack_buf;

    if (W_PER_R > 0  && pack_slot[0])  pack_buf_next[(0*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 1  && pack_slot[1])  pack_buf_next[(1*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 2  && pack_slot[2])  pack_buf_next[(2*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 3  && pack_slot[3])  pack_buf_next[(3*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 4  && pack_slot[4])  pack_buf_next[(4*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 5  && pack_slot[5])  pack_buf_next[(5*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 6  && pack_slot[6])  pack_buf_next[(6*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 7  && pack_slot[7])  pack_buf_next[(7*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 8  && pack_slot[8])  pack_buf_next[(8*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 9  && pack_slot[9])  pack_buf_next[(9*W_WIDTH)  +: W_WIDTH] = wr_data;
    if (W_PER_R > 10 && pack_slot[10]) pack_buf_next[(10*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 11 && pack_slot[11]) pack_buf_next[(11*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 12 && pack_slot[12]) pack_buf_next[(12*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 13 && pack_slot[13]) pack_buf_next[(13*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 14 && pack_slot[14]) pack_buf_next[(14*W_WIDTH) +: W_WIDTH] = wr_data;
    if (W_PER_R > 15 && pack_slot[15]) pack_buf_next[(15*W_WIDTH) +: W_WIDTH] = wr_data;
  end

  always_comb begin
    full        = (word_count == DEPTH[COUNT_W-1:0]);
    almost_full = (word_count == COUNT_W'(DEPTH-1));
    empty       = (word_count == 0);
  end

  always_comb begin
    pack_last_slot = pack_slot[W_PER_R-1];

    pack_finishes = wr_en && (pack_last_slot || wr_last);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      wptr       <= '0;
      rptr       <= '0;
      word_count <= '0;
      pack_slot  <= {{(W_PER_R-1){1'b0}}, 1'b1};
      rd_valid   <= 1'b0;
    end else begin
      rd_valid <= 1'b0;

      if (rd_en) begin
        rd_data  <= mem[rptr];
        rd_valid <= 1'b1;
        rptr     <= rptr + 1'b1;
      end

      if (wr_en) begin
        if (pack_finishes) begin
          mem[wptr] <= assembled_word;
          wptr      <= wptr + 1'b1;
          pack_slot <= {{(W_PER_R-1){1'b0}}, 1'b1};
        end else begin
          pack_buf  <= pack_buf_next;
          pack_slot <= pack_slot << 1;
        end
      end

      case ({(wr_en && pack_finishes), rd_en})
        2'b10: word_count <= word_count + 1'b1;
        2'b01: word_count <= word_count - 1'b1;
        default: word_count <= word_count;
      endcase
    end
  end

endmodule
