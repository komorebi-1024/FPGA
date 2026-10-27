from pathlib import Path
import re
root=Path(__file__).resolve().parent.parent
src=root/'03_Project/WestLake_AV/src'
baseline=root/'03_Project/00_Baseline/src'
h=src/'user_source/hdl_source'
# Build the new storage wrapper while reusing the vendor SPI transport.
(h/'SD/sd_card_bmp.v').write_text('''// WestLake catalog + playback wrapper. Vendor SD SPI transport retained.
module sd_card_bmp(
 input wire clk,input wire rst,input wire key_next,input wire key_auto,input wire key_audio,
 input wire [1:0] dwell_switch,input wire write_finish_toggle,input wire publish_ack,
 output wire [3:0] state_code,output wire [1:0] write_buf_idx,
 output wire publish_toggle,output wire [1:0] publish_buffer,output wire [1:0] publish_id,
 output wire auto_enabled,output wire test_audio,output wire [3:0] dwell_seconds,
 output wire write_req,input wire write_req_ack,output wire write_en,output wire [31:0] write_data,
 output wire SD_nCS,output wire SD_DCLK,output wire SD_MOSI,input wire SD_MISO
);
wire sd_ready,sec_read,sec_valid,sec_end,catalog_ready,media_error,reader_idle,source_done,load_start;
wire [31:0] sec_addr;wire [7:0] sec_data;wire [23:0] pixel;
wire [1:0] load_id,displayed_id;wire next_press,auto_press,audio_press,busy;wire [2:0] player_state;
(* async_reg="true" *) reg [1:0] wrack_sync;
always @(posedge clk or posedge rst)if(rst)wrack_sync<=0;else wrack_sync<={wrack_sync[0],write_req_ack};
assign write_data={pixel,8'h00};
wl_key_debounce next_key(clk,rst,key_next,next_press);
wl_key_debounce auto_key(clk,rst,key_auto,auto_press);
wl_key_debounce audio_key(clk,rst,key_audio,audio_press);
wl_media_reader media(
 .clk(clk),.rst(rst),.sd_ready(sd_ready),.sector_read(sec_read),.sector_addr(sec_addr),
 .sector_data(sec_data),.sector_valid(sec_valid),.sector_end(sec_end),.catalog_ready(catalog_ready),
 .error(media_error),.status(state_code),.load_start(load_start),.load_id(load_id),.idle(reader_idle),
 .load_done(source_done),.write_req(write_req),.write_ack(wrack_sync[1]),.pixel_valid(write_en),.pixel_rgb(pixel));
wl_playlist_ctrl player(
 .clk(clk),.rst(rst),.catalog_ready(catalog_ready),.media_error(media_error),.reader_idle(reader_idle),
 .source_done(source_done),.write_finish_toggle_async(write_finish_toggle),.publish_ack_async(publish_ack),
 .next_press(next_press),.auto_press(auto_press),.audio_press(audio_press),.dwell_switch_async(dwell_switch),
 .load_start(load_start),.load_id(load_id),.write_buffer(write_buf_idx),.publish_toggle(publish_toggle),
 .publish_buffer(publish_buffer),.publish_id(publish_id),.auto_enabled(auto_enabled),.test_audio(test_audio),
 .displayed_id(displayed_id),.busy(busy),.dwell_seconds(dwell_seconds),.state(player_state));
sd_card_top transport(
 .clk(clk),.rst(rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
 .sd_init_done(sd_ready),.sd_sec_read(sec_read),.sd_sec_read_addr(sec_addr),.sd_sec_read_data(sec_data),
 .sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),.sd_sec_write(1'b0),
 .sd_sec_write_addr(32'd0),.sd_sec_write_data(),.sd_sec_write_data_req(),.sd_sec_write_end());
endmodule
''',encoding='utf-8')

s=(baseline/'user_source/hdl_source/top_tf_hdmi_audio.v').read_text('utf-8')
s=s.replace('input                       key2,', 'input                       key_audio,\n    input                       sw1,\n    input                       sw2,\n    input                       key2,',1)
# Replace reset and clock section; IP output port added below.
a=s.index('// 统一复位');b=s.index('// mem_clk 域',a)
s=s[:a]+'''// WestLake reset: wait for both PLLs and release separately in each domain.
wire sys_pll_lock,video_pll_lock,rst_all,rst_sd,rst_mem,rst_video;
reg [19:0] reset_count=0;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)reset_count<=0;
 else if(!sys_pll_lock || !video_pll_lock)reset_count<=0;
 else if(reset_count<1000000)reset_count<=reset_count+1'b1;
end
assign rst_all=!rst_n || !sys_pll_lock || !video_pll_lock || reset_count<1000000;
wl_reset_sync reset_sd(sd_card_clk,rst_all,rst_sd);
wl_reset_sync reset_mem(ext_mem_clk,rst_all,rst_mem);
wl_reset_sync reset_video(video_clk,rst_all,rst_video);
sys_pll sys_pll_m0(.refclk(clk),.reset(1'b0),.extlock(sys_pll_lock),
 .clk0_out(sd_card_clk),.clk1_out(ext_mem_clk),.clk2_out(ext_mem_clk_sft));
video_pll video_pll_m0(.refclk(clk),.reset(1'b0),.extlock(video_pll_lock),
 .clk0_out(video_clk),.clk1_out(hdmi_5x_clk));
wire publish_toggle,publish_ack,auto_enabled,test_audio;
wire [1:0] publish_buffer,publish_id,displayed_id;
wire [3:0] dwell_seconds;
wire arrival_event,timing_req,timing_ack;
wire osd_hs,osd_vs,osd_de;wire [23:0] osd_rgb;
(* async_reg="true" *) reg [1:0] auto_sync,test_sync;
reg [3:0] dwell_meta,dwell_sync;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin auto_sync<=0;test_sync<=2'b11;dwell_meta<=0;dwell_sync<=0;end
 else begin auto_sync<={auto_sync[0],auto_enabled};test_sync<={test_sync[0],test_audio};dwell_meta<=dwell_seconds;dwell_sync<=dwell_meta;end
end
wl_video_commit commit_frame(
 .clk(video_clk),.rst(rst_video),.timing_req(timing_req),.timing_ack(timing_ack),
 .memory_req(video_read_req),.memory_ack_async(video_read_req_ack),
 .publish_toggle_async(publish_toggle),.publish_buffer_async(publish_buffer),.publish_id_async(publish_id),
 .publish_ack_toggle(publish_ack),.read_buffer(disp_buf_idx),.displayed_id(displayed_id),
 .display_valid(display_valid),.arrival_event(arrival_event));

'''+s[b:]
s=s.replace('always @(posedge ext_mem_clk or posedge rst_all)', 'always @(posedge ext_mem_clk or posedge rst_mem)').replace('if (rst_all)\n        frame_write_toggle_mem','if (rst_mem)\n        frame_write_toggle_mem')
a=s.index('sd_card_bmp #(');b=s.index('seg_decoder seg_decoder_m0',a)
s=s[:a]+'''sd_card_bmp sd_card_bmp_m0(
 .clk(sd_card_clk),.rst(rst_sd),.key_next(key1),.key_auto(key2),.key_audio(key_audio),.dwell_switch({sw2,sw1}),
 .write_finish_toggle(frame_write_toggle_mem),.publish_ack(publish_ack),.state_code(state_code),
 .write_buf_idx(write_buf_idx),.publish_toggle(publish_toggle),.publish_buffer(publish_buffer),.publish_id(publish_id),
 .auto_enabled(auto_enabled),.test_audio(test_audio),.dwell_seconds(dwell_seconds),
 .write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
 .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso));

'''+s[b:]
s=s.replace('.rst               (rst_all)', '.rst               (rst_video)',2)
s=s.replace('.read_req          (video_read_req)', '.read_req          (timing_req)',1).replace('.read_req_ack      (video_read_req_ack)', '.read_req_ack      (timing_ack)',1)
s=s.replace('.rst               (rst_all)', '.rst               (rst_mem)')
s=s.replace('.Rst               (rst_all)', '.Rst               (rst_mem)')
a=s.index('// ===================== 音频');b=s.index('// ===================== RGB/DE',a)
s=s[:a]+'''// Original WestLake PCM source. 48 kHz sample enable and exact ACR ratio.
wl_pcm_audio audio_source(
 .clk(video_clk),.rst(rst_video),.test_mode(test_sync[1]),.arrival_event(arrival_event),
 .sample_valid(audio_valid),.pcm_left(audio_left_data),.pcm_right(audio_right_data),
 .acr_valid(acr_valid),.acr_cts(acr_cts),.acr_n(acr_n),.chime_active());
wl_osd overlay(
 .clk(video_clk),.rst(rst_video),.hs_in(hs),.vs_in(vs),.de_in(de),.rgb_in(vout_data),
 .station_id(displayed_id),.auto_mode(auto_sync[1]),.test_audio(test_sync[1]),.dwell_seconds(dwell_sync),
 .hs_out(osd_hs),.vs_out(osd_vs),.de_out(osd_de),.rgb_out(osd_rgb));

'''+s[b:]
s=s.replace('(rst_all)', '(rst_video)') # remaining HDMI reset connections only
s=s.replace('.I_vs          (vs)', '.I_vs          (osd_vs)').replace('.I_de          (de)', '.I_de          (osd_de)').replace('.I_rgb         (vout_data)', '.I_rgb         (osd_rgb)')
# Remove unused legacy audio wires; all clocks and active data paths remain explicit.
s=re.sub(r'^wire\s+(audio_pll_lock|audio_mclk|audio_i2s_bclk|audio_i2s_lrck|audio_i2s_dout);\n','',s,flags=re.M)
(h/'top_tf_hdmi_audio.v').write_text(s,encoding='utf-8')
for name in ['sys_pll','video_pll']:
 p=h/'IP'/f'{name}.v';s=(baseline/'user_source/hdl_source/IP'/f'{name}.v').read_text('utf-8')
 s=s.replace('  reset,','  reset,\n  extlock,',1).replace('  input reset;','  input reset;\n  output extlock;',1).replace('.extlock(open)', '.extlock(extlock)')
 # Unused output ports must not share an implicit multiply-driven net.
 s=s.replace('.psdone(open)', '.psdone()').replace('.do({open, open, open, open, open, open, open, open})','.do()')
 s=s.replace('  wire clk0_buf;', '  wire clk0_buf;\n  wire [1:0] unused_clocks;')
 s=s.replace('.clkc({open, open, clk2_out, clk1_out, clk0_buf})','.clkc({unused_clocks, clk2_out, clk1_out, clk0_buf})')
 # video PLL has three unused outputs.
 s=s.replace('  wire [1:0] unused_clocks;','  wire [2:0] unused_clocks;' if name=='video_pll' else '  wire [1:0] unused_clocks;')
 s=s.replace('.clkc({open, open, open, clk1_out, clk0_buf})','.clkc({unused_clocks, clk1_out, clk0_buf})')
 p.write_text(s,encoding='utf-8')
adc=src/'user_source/constraints_source/pin.adc'
s=(baseline/'user_source/constraints_source/pin.adc').read_text('utf-8')
s+='\n# WestLake additional controls: KEY3, SW1 and SW2 from HX4S20 manual.\n'
for port,pin in [('key_audio','B1'),('sw1','C8'),('sw2','C7')]:s+=f'set_pin_assignment {{ {port} }} {{ LOCATION = {pin}; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }}\n'
adc.write_text(s,encoding='utf-8')
# Use the stable original project entry name, and append the new RTL files.
p=src/'td_project/HDMI1.4b_Transmitter_v1.0.al';s=p.read_text('utf-8')
s=re.sub(r'\s*<File Path="../user_source/hdl_source/westlake/[^\"]+">.*?</File>','',s,flags=re.S)
entries=''
for order,f in enumerate(sorted((h/'westlake').glob('*.v')),60):
 entries+=f'''            <File Path="../user_source/hdl_source/westlake/{f.name}"><FileInfo>
                <Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>
                <Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{order}"/>
            </FileInfo></File>\n'''
s=s.replace('        </Verilog>',entries+'        </Verilog>',1)
# XML in vendor .al uses literal P&R; retain that convention for compatibility.
s=s.replace('P&amp;R','P&R')
p.write_text(s,encoding='utf-8')
print('Integrated WestLake top, media, reset, audio, OSD and controls.')
