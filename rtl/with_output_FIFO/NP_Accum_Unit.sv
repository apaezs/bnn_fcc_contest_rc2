module NP_Accum_Unit #(
    parameter int iwidth = 32,
    parameter int owidth = 32
)(
    input  logic                 clk,

    input  logic                 en,
    input  logic                 ld,
    input  logic [iwidth-1:0]    din,
    output logic [owidth-1:0]    acc
);

    logic [iwidth-1:0] din_r;
    logic [owidth-1:0] din_ext_r;
    logic [owidth-1:0] sum_r;
    logic [owidth-1:0] add_result;

    always_ff @(posedge clk) begin
        din_r <= din;
    end

    always_ff @(posedge clk) begin
        din_ext_r <= owidth'(din_r);
    end

    assign add_result = sum_r + din_ext_r;

    always_ff @(posedge clk) begin
        if (ld)
            sum_r <= din_ext_r;
        else if (en)
            sum_r <= add_result;
    end

    always_ff @(posedge clk) begin
        acc <= sum_r;
    end

endmodule
