module StickyBit (
    input  logic clk,
    input  logic rst,
    input  logic set,
    input  logic clear, 
    output logic q
);

always_ff @(posedge clk or posedge rst) begin
    if (rst)
        q <= 1'b0;
    else if (clear)
        q <= 1'b0;
    else if (set)
        q <= 1'b1;
end

endmodule