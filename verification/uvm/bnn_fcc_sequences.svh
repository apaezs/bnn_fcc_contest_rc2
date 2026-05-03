`ifndef _BNN_FCC_SEQUENCES_SVH_
`define _BNN_FCC_SEQUENCES_SVH_

class bnn_fcc_axi_beat_sequence #(
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = axi4_stream_pkg::DEFAULT_ID_WIDTH,
    parameter int DEST_WIDTH = axi4_stream_pkg::DEFAULT_DEST_WIDTH,
    parameter int USER_WIDTH = axi4_stream_pkg::DEFAULT_USER_WIDTH
) extends uvm_sequence #(axi4_stream_seq_item #(DATA_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));
    `uvm_object_param_utils(bnn_fcc_axi_beat_sequence#(DATA_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    typedef bit [DATA_WIDTH-1:0]   data_t;
    typedef bit [DATA_WIDTH/8-1:0] keep_t;

    virtual axi4_stream_if #(DATA_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    data_t beat_data[];
    keep_t beat_keep[];
    bit    beat_last[];
    int    gap_before[];

    function new(string name = "bnn_fcc_axi_beat_sequence");
        super.new(name);
    endfunction

    task body();
        axi4_stream_seq_item #(DATA_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) req;

        if (vif == null) begin
            `uvm_fatal(get_type_name(), "Sequence needs a valid AXI virtual interface.")
        end

        if (beat_data.size() != beat_keep.size() ||
            beat_data.size() != beat_last.size() ||
            beat_data.size() != gap_before.size()) begin
            `uvm_fatal(get_type_name(), "beat_data/beat_keep/beat_last/gap_before size mismatch.")
        end

        foreach (beat_data[i]) begin
            repeat (gap_before[i]) @(posedge vif.aclk);

            req = axi4_stream_seq_item #(DATA_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)::type_id::create($sformatf("req_%0d", i));
            req.is_packet_level = 1'b0;
            req.tdata = new[1];
            req.tstrb = new[1];
            req.tkeep = new[1];
            req.tdata[0] = beat_data[i];
            req.tstrb[0] = beat_keep[i];
            req.tkeep[0] = beat_keep[i];
            req.tlast    = beat_last[i];

            start_item(req);
            finish_item(req);
        end
    endtask
endclass

`endif
