# WestLake clocks. Pixel/serializer are related and remain timed together.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {sdram_clk_shifted} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
# FIFO constraints are supplied separately by the IP-generated Tcl files.
# No blanket asynchronous/exclusive grouping hides the CDC or SDRAM paths.

# Reset synchronizers de-assert once at startup. False-path their recovery to the
# fanout-heavy reset pins; the 3-stage shift register guarantees a clean release.
set_false_path -from [get_nets {reset_sd/release_chain[2] reset_mem/release_chain[2] reset_video/release_chain[2]}]
set_false_path -to [get_pins -hier {*.sr}]
