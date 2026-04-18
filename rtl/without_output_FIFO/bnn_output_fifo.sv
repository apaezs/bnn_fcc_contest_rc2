module bnn_output_fifo (
    input  logic       clk,
    input  logic       rst,

    input  logic       wr_valid,
    input  logic [7:0] wr_data,

    input  logic       rd_ready,
    output logic       rd_valid,
    output logic [7:0] rd_data
);

    logic [7:0] mem [0:14];

    logic [3:0] wr_ptr_r;
    logic [3:0] rd_ptr_r;
    logic       ring_full_r;

    logic       rd_valid_r;
    logic [7:0] rd_data_r;

    logic       wr_stage_valid_r;
    logic [7:0] wr_stage_data_r;

    logic       mem_we_r;
    logic [3:0] mem_waddr_r;
    logic [7:0] mem_wdata_r;

    logic rd_fire;
    logic ring_empty;

    logic [3:0] wr_ptr_next;
    logic [3:0] rd_ptr_next;

    assign rd_fire    = rd_ready && rd_valid_r;
    assign ring_empty = !ring_full_r && (wr_ptr_r == rd_ptr_r);

    assign wr_ptr_next = (wr_ptr_r == 4'd14) ? 4'd0 : (wr_ptr_r + 4'd1);
    assign rd_ptr_next = (rd_ptr_r == 4'd14) ? 4'd0 : (rd_ptr_r + 4'd1);

    assign rd_valid = rd_valid_r;
    assign rd_data  = rd_data_r;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr_r         <= 4'd0;
            rd_ptr_r         <= 4'd0;
            ring_full_r      <= 1'b0;
            rd_valid_r       <= 1'b0;
            rd_data_r        <= 8'd0;
            wr_stage_valid_r <= 1'b0;
            wr_stage_data_r  <= 8'd0;
            mem_we_r         <= 1'b0;
            mem_waddr_r      <= 4'd0;
            mem_wdata_r      <= 8'd0;
        end else begin
            
            if (mem_we_r) mem[mem_waddr_r] <= mem_wdata_r;

            mem_we_r <= 1'b0;

            if (!rd_valid_r) begin
                if (wr_stage_valid_r) begin
                    rd_valid_r <= 1'b1;
                    rd_data_r  <= wr_stage_data_r;
                end
            end else begin
                unique case ({wr_stage_valid_r, rd_fire})
                    2'b00: begin
                    end

                    2'b01: begin
                        if (!ring_empty) begin
                            rd_data_r   <= mem[rd_ptr_r];
                            rd_ptr_r    <= rd_ptr_next;
                            ring_full_r <= 1'b0;
                        end else begin
                            rd_valid_r <= 1'b0;
                        end
                    end

                    2'b10: begin
                        if (!ring_full_r) begin
                            mem_we_r    <= 1'b1;
                            mem_waddr_r <= wr_ptr_r;
                            mem_wdata_r <= wr_stage_data_r;
                            wr_ptr_r <= wr_ptr_next;
                            if (wr_ptr_next == rd_ptr_r) ring_full_r <= 1'b1;

                        end else begin
                            rd_data_r   <= mem[rd_ptr_r];
                            rd_ptr_r    <= rd_ptr_next;
                            mem_we_r    <= 1'b1;
                            mem_waddr_r <= wr_ptr_r;
                            mem_wdata_r <= wr_stage_data_r;
                            wr_ptr_r    <= wr_ptr_next;
                            ring_full_r <= 1'b1;
                        end
                    end

                    2'b11: begin
                        if (!ring_empty) begin
                            rd_data_r   <= mem[rd_ptr_r];
                            rd_ptr_r    <= rd_ptr_next;
                            mem_we_r    <= 1'b1;
                            mem_waddr_r <= wr_ptr_r;
                            mem_wdata_r <= wr_stage_data_r;
                            wr_ptr_r <= wr_ptr_next;
                        end else begin
                            rd_data_r  <= wr_stage_data_r;
                            rd_valid_r <= 1'b1;
                        end
                    end

                    default: begin
                    end
                endcase
            end

            wr_stage_valid_r <= wr_valid;
            if (wr_valid) wr_stage_data_r <= wr_data;
        end
    end

endmodule
