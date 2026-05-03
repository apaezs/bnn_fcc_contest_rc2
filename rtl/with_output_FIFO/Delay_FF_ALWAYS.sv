module Delay_FF_ALWAYS #(
    parameter int LAT = 1
)(
    input  logic clk,
    input  logic din,
    
    output logic dout
);

    logic [0:LAT] stage;

    assign stage[0] = din;

    genvar i;
    generate
        for (i = 0; i < LAT; i++) begin : GEN_DELAY
            Register_ALWAYS #(
                .DWIDTH(1)
            ) reg_i (
                .clk(clk),
                .d  (stage[i]),
                .q  (stage[i+1])
            );
        end
    endgenerate

    assign dout = stage[LAT];

endmodule

