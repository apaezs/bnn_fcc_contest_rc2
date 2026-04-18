module NP_Threshold_Unit #(
    parameter int width = 8
)(
    input  logic             clk,

    input  logic [width-1:0] value,
    input  logic [width-1:0] thresh,
    output logic             y
);

    logic [width-1:0] thresh_r;
    logic             y_next;

    always_ff @(posedge clk) begin
        thresh_r <= thresh;
    end

    always_comb begin
        y_next = (value >= thresh_r);
    end

    always_ff @(posedge clk) begin
        y <= y_next;
    end

endmodule
