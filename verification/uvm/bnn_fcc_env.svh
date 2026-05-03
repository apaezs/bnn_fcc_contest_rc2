`ifndef _BNN_FCC_ENV_SVH_
`define _BNN_FCC_ENV_SVH_

class bnn_fcc_env extends uvm_env;
    `uvm_component_utils(bnn_fcc_env)

    axi4_stream_agent   #(CONFIG_BUS_WIDTH) config_agent;
    axi4_stream_agent   #(INPUT_BUS_WIDTH)  data_in_agent;
    axi4_stream_monitor #(OUTPUT_BUS_WIDTH) data_out_monitor;

    bnn_fcc_ready_ctrl  ready_ctrl;
    bnn_fcc_scoreboard  scoreboard;
    bnn_fcc_coverage    coverage;

    bnn_fcc_uvm_cfg                            cfg;
    virtual axi4_stream_if #(CONFIG_BUS_WIDTH) config_vif;
    virtual axi4_stream_if #(INPUT_BUS_WIDTH)  data_in_vif;
    virtual axi4_stream_if #(OUTPUT_BUS_WIDTH) data_out_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(bnn_fcc_uvm_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("NO_CFG", "Could not get bnn_fcc_uvm_cfg.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(CONFIG_BUS_WIDTH))::get(this, "", "config_vif", config_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get config_vif.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(INPUT_BUS_WIDTH))::get(this, "", "data_in_vif", data_in_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get data_in_vif.")
        end
        if (!uvm_config_db#(virtual axi4_stream_if #(OUTPUT_BUS_WIDTH))::get(this, "", "data_out_vif", data_out_vif)) begin
            `uvm_fatal("NO_VIF", "Could not get data_out_vif.")
        end

        config_agent    = axi4_stream_agent #(CONFIG_BUS_WIDTH)::type_id::create("config_agent", this);
        data_in_agent   = axi4_stream_agent #(INPUT_BUS_WIDTH)::type_id::create("data_in_agent", this);
        data_out_monitor = axi4_stream_monitor #(OUTPUT_BUS_WIDTH)::type_id::create("data_out_monitor", this);
        ready_ctrl      = bnn_fcc_ready_ctrl::type_id::create("ready_ctrl", this);
        scoreboard      = bnn_fcc_scoreboard::type_id::create("scoreboard", this);
        coverage        = bnn_fcc_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        config_agent.driver.vif   = config_vif;
        config_agent.monitor.vif  = config_vif;
        data_in_agent.driver.vif  = data_in_vif;
        data_in_agent.monitor.vif = data_in_vif;
        data_out_monitor.vif      = data_out_vif;

        config_agent.configure_transaction_level(1'b0);
        data_in_agent.configure_transaction_level(1'b0);
        data_out_monitor.is_packet_level = 1'b0;

        config_agent.driver.set_delay(1, 1);
        data_in_agent.driver.set_delay(1, 1);

        data_in_agent.monitor.ap.connect(scoreboard.data_in_ae);
        data_out_monitor.ap.connect(scoreboard.data_out_ae);
    endfunction
endclass

`endif
