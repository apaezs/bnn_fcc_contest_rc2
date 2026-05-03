`ifndef _BNN_FCC_COVERAGE_TEST_SVH_
`define _BNN_FCC_COVERAGE_TEST_SVH_

class bnn_fcc_coverage_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_coverage_test)

    function new(string name = "bnn_fcc_coverage_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

`endif
