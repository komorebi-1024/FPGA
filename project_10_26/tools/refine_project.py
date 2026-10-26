"""Reproducible refinements after integrate_project.py; originals are not changed."""
from pathlib import Path
root=Path(__file__).resolve().parent.parent
src=root/'03_Project/WestLake_AV/src'
h=src/'user_source/hdl_source'
p=h/'westlake/wl_media_reader.v'
s=p.read_text('utf-8')
if 'wire [1:0] catalog_index' not in s:
 s=s.replace("reg [8:0] byte_in_sector;", "reg [8:0] byte_in_sector;\nwire [1:0] catalog_index=(byte_in_sector-9'd16)>>4;\nlocalparam [31:0] FILE_SECTORS=(FILE_BYTES+511)/512;")
s=s.replace("byte_in_sector[5:4]-1'b1",'catalog_index')
s=s.replace('lba[1]<=lba[0] || lba[2]<=lba[1] || lba[3]<=lba[2] || lba[3]>=262144', 'lba[1]<lba[0]+FILE_SECTORS || lba[2]<lba[1]+FILE_SECTORS || lba[3]<lba[2]+FILE_SECTORS || lba[3]>262144-FILE_SECTORS')
p.write_text(s,'utf-8')
p=h/'westlake/wl_video_commit.v';s=p.read_text('utf-8').replace('last_consumed, request_seen,','last_consumed,').replace('request_seen<=0;','');p.write_text(s,'utf-8')
# SDRAM at 50 MHz, 144 degree shift: 8 ns write and 12 ns read budgets.
# Its peak 200 MB/s still exceeds 640x480x~60x4 = ~73.1 MB/s display demand.
p=h/'IP/sys_pll.v';s=p.read_text('utf-8').replace('125.000000MHZ','50.000000MHZ')
s=s.replace('.CLKC1_DIV(8)', '.CLKC1_DIV(20)').replace('.CLKC1_CPHASE(7)', '.CLKC1_CPHASE(19)')
s=s.replace('.CLKC2_DIV(8)', '.CLKC2_DIV(20)').replace('.CLKC2_CPHASE(3)', '.CLKC2_CPHASE(7)').replace('.CLKC2_CPHASE(9)', '.CLKC2_CPHASE(7)').replace('180.0000 DEG','144.0000 DEG');p.write_text(s,'utf-8')
p=h/'include/global_def.v';s=p.read_text('utf-8').replace('1000000000/125000000','1000000000/50000000');p.write_text(s,'utf-8')
p=src/'user_source/constraints_source/timing.sdc'
p.write_text('''# WestLake clocks. Pixel/serializer are related and remain timed together.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {sdram_clk_shifted} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
# FIFO constraints are supplied separately by the IP-generated Tcl files.
# No blanket asynchronous/exclusive grouping hides the CDC or SDRAM paths.
''','utf-8')
p=h/'westlake/wl_osd.v';s=p.read_text('utf-8').replace('../user_source/hdl_source/westlake/captions.hex','captions.hex').replace('../user_source/hdl_source/westlake/ascii_font.hex','ascii_font.hex');p.write_text(s,'utf-8')
p=h/'SD/sd_card_bmp.v';s=p.read_text('utf-8').replace('.sd_sec_write_data()',".sd_sec_write_data(8'd0)")
s=s.replace('.status(state_code)', '.status(media_status)')
if 'wire [3:0] media_status;' not in s:s=s.replace('wire sd_ready,','wire [3:0] media_status;\nassign state_code=(player_state==4 && !media_error)?4\'hb:media_status;\nwire sd_ready,')
p.write_text(s,'utf-8')
p=h/'top_tf_hdmi_audio.v';s=p.read_text('utf-8').replace("24'd307200", "21'd307200").replace("24'd0", "21'd0");p.write_text(s,'utf-8')
p=h/'SD/frame_read_write.v';p.write_bytes((root/'03_Project/00_Baseline/src/user_source/hdl_source/SD/frame_read_write.v').read_bytes())
# Keep the vendor FIFO's 9-bit used-word counters. The 10-bit controller inputs
# are safely zero-extended by Verilog; unused output bits must never be constants.
import xml.etree.ElementTree as ET
p=h/'IP/sys_pll.ipc';tree=ET.parse(p)
for c in tree.findall('.//clock'):
 if c.findtext('id') in ('1','2'):
  c.find('clock_division_factor').text='20';c.find('clock_frequency').text='50.0000000000000000MHz'
 if c.findtext('id')=='2':c.find('phase_shift').text='144.0000000000000000deg'
tree.write(p,encoding='utf-8',xml_declaration=True)
print('Applied catalog bounds, 50 MHz / 144 degree SDRAM, ROM paths, port widths and timing constraints.')
