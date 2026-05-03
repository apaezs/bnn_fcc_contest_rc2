`ifndef _BNN_FCC_READY_CTRL_SVH_
`define _BNN_FCC_READY_CTRL_SVH_

class bnn_fcc_ready_ctrl extends uvm_component;
    `uvm_component_utils(bnn_fcc_ready_ctrl)

    bnn_fcc_uvm_cfg                           cfg;
    virtual axi4_stream_if #(OUTPUT_BUS_WIDTH) vif;
    bit                                       manual_mode;
    bit                                       manual_ready;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        manual_mode  = 1'b0;
        manual_ready = 1'b1;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(bnn_fcc_uvm_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("NO_CFG", "Could not get bnn_fcc_uvm_cfg.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(OUTPUT_BUS_WIDTH))::get(this, "", "data_out_vif", vif)) begin
            `uvm_fatal("NO_VIF", "Could not get data_out_vif for ready controller.")
        end
    endfunction

    task set_manual_ready(bit ready_value);
        manual_mode  = 1'b1;
        manual_ready = ready_value;
        @(negedge vif.aclk);
        if (vif.aresetn) vif.tready <= ready_value;
    endtask

    task release_manual();
        manual_mode = 1'b0;
    endtask

    task run_phase(uvm_phase phase);
        vif.tready <= 1'b0;
        forever begin
            @(negedge vif.aclk or negedge vif.aresetn);
            if (!vif.aresetn) begin
                vif.tready <= 1'b0;
            end else if (manual_mode) begin
                vif.tready <= manual_ready;
            end else if (!cfg.toggle_data_out_ready) begin
                vif.tready <= 1'b1;
            end else begin
                vif.tready <= $urandom_range(0, 1);
            end
        end
    endtask
endclass

`endif
