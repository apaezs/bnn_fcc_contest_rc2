module Pulse_Delay (
    input  logic clk,
    input  logic rst,

    input  logic in,
    output logic pulse
);
    logic in_d;
    logic pulse_d;
    logic pulse_now;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            in_d    <= 1'b0;
            pulse_d <= 1'b0;
        end else begin
            in_d    <= in;
            pulse_d <= pulse_now;
        end
    end

    assign pulse_now = in & ~in_d;
    assign pulse     = pulse_d;
endmodule