module Input_Layer #(
    parameter int unsigned out_w   = 8,
    parameter int unsigned in_w    = 64,
    localparam int unsigned CHUNK_W = in_w / out_w,
    parameter logic [CHUNK_W-1:0] THRESH = '0
)(
    input  logic               clk,
    input  logic               rst,

    input  logic               en,
    input  logic               last_in,
    input  logic [in_w-1:0]    istream,
    output logic               valid,
    output logic               last_out,
    output logic [out_w-1:0]   ostream
);

    logic [out_w-1:0] ostream_next;
    integer i;

    always_comb begin
        ostream_next = '0;
        for (i = 0; i < out_w; i++) begin
            logic [CHUNK_W-1:0] chunk;
            chunk = istream[i*CHUNK_W +: CHUNK_W];
            ostream_next[i] = (chunk >= THRESH);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid <= 1'b0;
        end else begin
            valid <= en;
        end
    end

    always_ff @(posedge clk) begin
        if (en) begin
            last_out <= last_in;
            ostream  <= ostream_next;
        end
    end

endmodule
