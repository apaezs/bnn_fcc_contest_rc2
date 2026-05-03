`ifndef _BNN_FCC_SCOREBOARD_SVH_
`define _BNN_FCC_SCOREBOARD_SVH_

class bnn_fcc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(bnn_fcc_scoreboard)

    typedef axi4_stream_seq_item #(INPUT_BUS_WIDTH)  data_in_item_t;
    typedef axi4_stream_seq_item #(OUTPUT_BUS_WIDTH) data_out_item_t;

    uvm_analysis_export #(data_in_item_t)   data_in_ae;
    uvm_analysis_export #(data_out_item_t)  data_out_ae;
    uvm_tlm_analysis_fifo #(data_in_item_t) data_in_fifo;
    uvm_tlm_analysis_fifo #(data_out_item_t) data_out_fifo;

    bnn_fcc_uvm_cfg                           cfg;
    virtual axi4_stream_if #(INPUT_BUS_WIDTH) data_in_vif;

    pixel_t                                   partial_img_q[$];
    int                                       expected_q[$];
    int                                       passed;
    int                                       failed;
    int                                       output_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        passed       = 0;
        failed       = 0;
        output_count = 0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(bnn_fcc_uvm_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("NO_CFG", "Could not get bnn_fcc_uvm_cfg.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(INPUT_BUS_WIDTH))::get(this, "", "data_in_vif", data_in_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get data_in_vif for scoreboard.")
        end

        data_in_ae   = new("data_in_ae", this);
        data_out_ae  = new("data_out_ae", this);
        data_in_fifo = new("data_in_fifo", this);
        data_out_fifo = new("data_out_fifo", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        data_in_ae.connect(data_in_fifo.analysis_export);
        data_out_ae.connect(data_out_fifo.analysis_export);
    endfunction

    function int get_pending_count();
        return expected_q.size();
    endfunction

    function int get_passed();
        return passed;
    endfunction

    function int get_failed();
        return failed;
    endfunction

    task clear_expected_state();
        partial_img_q.delete();
        expected_q.delete();
    endtask

    task monitor_reset();
        forever begin
            @(negedge data_in_vif.aresetn);
            clear_expected_state();
        end
    endtask

    task process_inputs();
        data_in_item_t item;
        pixel_t        full_img[];
        int            expected_pred;

        forever begin
            data_in_fifo.get(item);
            if (!data_in_vif.aresetn) begin
                continue;
            end

            for (int lane = 0; lane < INPUTS_PER_CYCLE; lane++) begin
                if (item.tkeep[0][lane*BYTES_PER_INPUT+:BYTES_PER_INPUT] != '0) begin
                    partial_img_q.push_back(item.tdata[0][lane*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH]);
                end
            end

            if (item.tlast) begin
                if (partial_img_q.size() == cfg.actual_topology[0]) begin
                    full_img = new[partial_img_q.size()];
                    foreach (partial_img_q[i]) full_img[i] = partial_img_q[i];
                    expected_pred = cfg.model.compute_reference(full_img);
                    expected_q.push_back(expected_pred);
                end else if (partial_img_q.size() != 0) begin
                    `uvm_warning("SCOREBOARD", $sformatf("Ignoring partial image of %0d pixels on tlast; expected %0d.", partial_img_q.size(), cfg.actual_topology[0]))
                end
                partial_img_q.delete();
            end
        end
    endtask

    task process_outputs();
        data_out_item_t item;
        int             actual_pred;
        int             expected_pred;

        forever begin
            data_out_fifo.get(item);
            if (!data_in_vif.aresetn) begin
                continue;
            end

            if (expected_q.size() == 0) begin
                failed++;
                `uvm_error("SCOREBOARD", "Received DUT output with no queued expected result.")
                continue;
            end

            expected_pred = expected_q.pop_front();
            actual_pred   = int'(item.tdata[0][OUTPUT_DATA_WIDTH-1:0]);
            output_count++;

            if (actual_pred == expected_pred) begin
                passed++;
                `uvm_info("SCOREBOARD", $sformatf("PASSED image %0d: actual=%0d expected=%0d", output_count-1, actual_pred, expected_pred), UVM_LOW)
            end else begin
                failed++;
                `uvm_error("SCOREBOARD", $sformatf("FAILED image %0d: actual=%0d expected=%0d", output_count-1, actual_pred, expected_pred))
            end
        end
    endtask

    task run_phase(uvm_phase phase);
        fork
            monitor_reset();
            process_inputs();
            process_outputs();
        join
    endtask
endclass

`endif
