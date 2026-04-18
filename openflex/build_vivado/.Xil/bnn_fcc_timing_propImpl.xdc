set_property SRC_FILE_INFO {cfile:/ecel/UFAD/miguel.sanchez1/BNN_Contest/Apple_comp/openflex/build_vivado/vivado.xdc rfile:../vivado.xdc id:1} [current_design]
set_property src_info {type:XDC file:1 line:8 export:INPUT save:INPUT read:READ} [current_design]
create_pblock pblock_h1_low
resize_pblock [get_pblocks pblock_h1_low] -add {SLICE_X60Y0:SLICE_X120Y140}
set_property IS_SOFT TRUE [get_pblocks pblock_h1_low]
set_property src_info {type:XDC file:1 line:9 export:INPUT save:INPUT read:READ} [current_design]
create_pblock pblock_h1_high
resize_pblock [get_pblocks pblock_h1_high] -add {SLICE_X121Y0:SLICE_X180Y140}
set_property IS_SOFT TRUE [get_pblocks pblock_h1_high]
set_property src_info {type:XDC file:1 line:16 export:INPUT save:INPUT read:READ} [current_design]
if {[llength [get_cells -hier -filter {NAME =~ *GEN_LAYERS[1]*GEN_NP[0]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[1]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[2]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[3]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[4]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[5]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[6]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[7]*}]] > 0} {
add_cells_to_pblock [get_pblocks pblock_h1_low] [get_cells -hier -filter {NAME =~ *GEN_LAYERS[1]*GEN_NP[0]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[1]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[2]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[3]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[4]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[5]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[6]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[7]*}]
}
set_property src_info {type:XDC file:1 line:25 export:INPUT save:INPUT read:READ} [current_design]
if {[llength [get_cells -hier -filter {NAME =~ *GEN_LAYERS[1]*GEN_NP[8]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[9]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[10]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[11]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[12]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[13]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[14]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[15]*}]] > 0} {
add_cells_to_pblock [get_pblocks pblock_h1_high] [get_cells -hier -filter {NAME =~ *GEN_LAYERS[1]*GEN_NP[8]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[9]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[10]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[11]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[12]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[13]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[14]* || NAME =~ *GEN_LAYERS[1]*GEN_NP[15]*}]
}
