
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key_audio,
    input                       sw1,
    input                       sw2,
    input                       key2,           // 自动播放 开/关

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 21'd307200;   // 640*480
parameter BUF0_ADDR     = 21'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// WestLake reset: wait for both PLLs and release separately in each domain.
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
wire publish_toggle,publish_ack,test_audio,publish_kind,scene_mode;
wire [1:0] publish_buffer,publish_id,displayed_id;
wire [3:0] dwell_seconds;
wire trans_active;wire [1:0] trans_type;wire [5:0] trans_frame;wire [7:0] fade_coeff;
wire arrival_event,timing_req,timing_ack;
wire audio_arrival_event,auto_depart_toggle;
wire [8:0] image_config,image_frame_config;wire image_config_toggle,image_config_ack_toggle;
wire osd_hs,osd_vs,osd_de;wire [23:0] osd_rgb;
wire audio_fifo_write,audio_fifo_full,audio_fifo_empty,audio_fifo_flush,audio_buffer_ready;
wire [31:0] audio_fifo_input,audio_fifo_output;wire [10:0] audio_fifo_level;
wire [1:0] music_track_id;wire [2:0] music_track_count;
wire music_error,music_menu_toggle,audio_wr_reset,audio_rd_reset;
wire music_pop,music_sample_valid,music_underrun,chime_active;
(* async_reg="true" *) reg [1:0] buffer_ready_sync,menu_sync,music_error_sync,spectrum_switch_sync;
reg [1:0] track_meta,track_sync;reg [2:0] count_meta,count_sync;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin
  buffer_ready_sync<=0;menu_sync<=0;music_error_sync<=0;spectrum_switch_sync<=0;
  track_meta<=0;track_sync<=0;count_meta<=0;count_sync<=0;
 end else begin
  buffer_ready_sync<={buffer_ready_sync[0],audio_buffer_ready};
  menu_sync<={menu_sync[0],music_menu_toggle};music_error_sync<={music_error_sync[0],music_error};
  spectrum_switch_sync<={spectrum_switch_sync[0],sw1};
  track_meta<=music_track_id;track_sync<=track_meta;count_meta<=music_track_count;count_sync<=count_meta;
 end
end
wl_reset_sync audio_write_reset(sd_card_clk,rst_all || audio_fifo_flush,audio_wr_reset);
wl_reset_sync audio_read_reset(video_clk,rst_all || audio_fifo_flush,audio_rd_reset);
wl_audio_fifo music_fifo(
 .wr_clk(sd_card_clk),.wr_rst(audio_wr_reset),.wr_en(audio_fifo_write),.wr_data(audio_fifo_input),
 .wr_full(audio_fifo_full),.wr_level(audio_fifo_level),
 .rd_clk(video_clk),.rd_rst(audio_rd_reset),.rd_en(music_pop),.rd_data(audio_fifo_output),.rd_empty(audio_fifo_empty));
wire voice_request_toggle,voice_stop,voice_fifo_write,voice_fifo_full,voice_fifo_empty,voice_fifo_flush;
wire voice_session_ack,voice_buffer_ready,voice_catalog_ready,voice_reader_error;
wire [1:0] voice_station,voice_subtitle_phase;
wire [5:0] voice_subtitle_reveal;
wire [9:0] voice_fifo_level;
wire [31:0] voice_fifo_input,voice_fifo_output,voice_total_frames,voice_cue1,voice_cue2;
wire [14:0] voice_char_counts;
wire voice_wr_reset,voice_rd_reset,voice_play,voice_active,voice_pop,voice_underrun,voice_control_error,voice_complete;
wl_reset_sync voice_write_reset(sd_card_clk,rst_all || voice_fifo_flush,voice_wr_reset);
wl_reset_sync voice_read_reset(video_clk,rst_all || voice_fifo_flush,voice_rd_reset);
wl_audio_fifo #(.ADDR_BITS(9)) voice_fifo(
 .wr_clk(sd_card_clk),.wr_rst(voice_wr_reset),.wr_en(voice_fifo_write),.wr_data(voice_fifo_input),
 .wr_full(voice_fifo_full),.wr_level(voice_fifo_level),
 .rd_clk(video_clk),.rd_rst(voice_rd_reset),.rd_en(voice_pop),.rd_data(voice_fifo_output),.rd_empty(voice_fifo_empty));
(* async_reg="true" *) reg [1:0] scene_sync,test_sync;
reg [3:0] dwell_meta,dwell_sync;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin scene_sync<=0;test_sync<=0;dwell_meta<=0;dwell_sync<=0;end
 else begin scene_sync<={scene_sync[0],scene_mode};test_sync<={test_sync[0],sw2};dwell_meta<=dwell_seconds;dwell_sync<=dwell_meta;end
end
// image_ready is a 1-clk pulse on every committed buffer switch. The transition
// controller acts on it only in SECTION mode; station images appear directly.
reg [1:0] disp_buf_prev;
wire image_ready = (disp_buf_idx != disp_buf_prev);
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video) disp_buf_prev<=0;
 else disp_buf_prev<=disp_buf_idx;
end
wl_transition_ctrl trans_ctrl(
 .clk(video_clk),.rst(rst_video),.vs(vs_0),
 .image_ready(image_ready),.in_section(~scene_sync[1]),
 .trans_active(trans_active),.trans_type(trans_type),.trans_frame(trans_frame),.fade_coeff(fade_coeff),
 .read_old(),.trans_done());
wl_video_commit commit_frame(
 .clk(video_clk),.rst(rst_video),.timing_req(timing_req),.timing_ack(timing_ack),
 .memory_req(video_read_req),.memory_ack_async(video_read_req_ack),
 .publish_toggle_async(publish_toggle),.publish_buffer_async(publish_buffer),.publish_id_async(publish_id),
 .publish_kind_async(publish_kind),
 .publish_ack_toggle(publish_ack),.read_buffer(disp_buf_idx),.displayed_id(displayed_id),
 .display_valid(display_valid),.arrival_event(arrival_event));

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp sd_card_bmp_m0(
 .clk(sd_card_clk),.rst(rst_sd),.key_next(key1),.key_audio(key_audio),
 .write_finish_toggle(frame_write_toggle_mem),.publish_ack(publish_ack),.state_code(state_code),
 .write_buf_idx(write_buf_idx),.publish_toggle(publish_toggle),.publish_buffer(publish_buffer),.publish_id(publish_id),
 .publish_kind(publish_kind),.scene_mode(scene_mode),.test_audio(test_audio),.dwell_seconds(dwell_seconds),
 .write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
 .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
 .audio_fifo_level(audio_fifo_level),.audio_fifo_full(audio_fifo_full),
 .audio_fifo_write(audio_fifo_write),.audio_fifo_data(audio_fifo_input),
 .audio_fifo_flush(audio_fifo_flush),.audio_buffer_ready(audio_buffer_ready),
 .music_track_id(music_track_id),.music_track_count(music_track_count),.music_error(music_error),.music_menu_toggle(music_menu_toggle),
 .voice_request_toggle(voice_request_toggle),.voice_station(voice_station),.voice_stop(voice_stop),
 .voice_fifo_level(voice_fifo_level),.voice_fifo_full(voice_fifo_full),.voice_fifo_write(voice_fifo_write),
 .voice_fifo_data(voice_fifo_input),.voice_fifo_flush(voice_fifo_flush),
 .voice_session_ack(voice_session_ack),.voice_buffer_ready(voice_buffer_ready),.voice_catalog_ready(voice_catalog_ready),.voice_reader_error(voice_reader_error),
 .voice_total_frames(voice_total_frames),.voice_cue1(voice_cue1),.voice_cue2(voice_cue2),.voice_char_counts(voice_char_counts),
 .auto_depart_toggle(auto_depart_toggle),.image_config(image_config),.image_config_toggle(image_config_toggle),
 .image_config_ack_toggle(image_config_ack_toggle));

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (timing_req),
    .read_req_ack      (timing_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
assign vout_data = display_valid ? vout_data_raw : 21'd0;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480),
    .TRANS_FRAMES     (60),  // must match wl_transition_ctrl
    .HALF             (30)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (21'd0),
    .read_addr_3       (21'd0),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (21'd0),
    .write_addr_3      (21'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .trans_active      (trans_active),
    .trans_type        (trans_type),
    .trans_frame       (trans_frame)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// Pause consumption at stations. FIFO retains the exact next stereo frame.
wire music_play=display_valid && !scene_sync[1] && !audio_rd_reset;
wl_arrival_audio_gate arrival_audio_gate(
 .clk(video_clk),.rst(rst_video),.arrival_event(arrival_event),
 .in_station(display_valid && scene_sync[1]),.audio_arrival_event(audio_arrival_event),.boot_waiting());
wl_station_departure station_departure(
 .clk(video_clk),.rst(rst_video),.in_station(display_valid && scene_sync[1]),
 .narration_complete(voice_complete || voice_control_error),.depart_toggle(auto_depart_toggle));
wl_voice_ctrl voice_controller(
 .clk(video_clk),.rst(rst_video),.arrival_event(audio_arrival_event),.station_id(displayed_id),.in_station(display_valid && scene_sync[1]),
 .reader_ack_toggle_async(voice_session_ack),.reader_ready_async(voice_buffer_ready),.reader_error_async(voice_reader_error),
 .reader_catalog_ready_async(voice_catalog_ready),.voice_fifo_reset(voice_rd_reset),.voice_pop(voice_pop),
 .current_total_frames_async(voice_total_frames),.current_cue1_async(voice_cue1),.current_cue2_async(voice_cue2),.current_chars_async(voice_char_counts),
 .request_toggle(voice_request_toggle),.request_station(voice_station),.stop_request(voice_stop),
 .voice_play(voice_play),.voice_active(voice_active),.subtitle_phase(voice_subtitle_phase),.subtitle_reveal(voice_subtitle_reveal),
 .subtitle_session_toggle(),.voice_done(),.voice_complete(voice_complete),.voice_error(voice_control_error));
wl_pcm_audio #(.CHIME_SAMPLES(48000),.CHIME_SHIFT(7)) audio_source(
 .clk(video_clk),.rst(rst_video),.test_mode(test_sync[1]),.arrival_event(audio_arrival_event),
 .sample_valid(audio_valid),.pcm_left(audio_left_data),.pcm_right(audio_right_data),
 .acr_valid(acr_valid),.acr_cts(acr_cts),.acr_n(acr_n),.chime_active(chime_active),
 .music_enable(music_play),.music_ready(buffer_ready_sync[1]),.music_empty(audio_fifo_empty),.music_data(audio_fifo_output),
 .music_pop(music_pop),.music_sample_valid(music_sample_valid),.music_underrun(music_underrun),
 .voice_enable(voice_play),.voice_ready(!voice_rd_reset),.voice_empty(voice_fifo_empty),.voice_data(voice_fifo_output),
 .voice_pop(voice_pop),.voice_underrun(voice_underrun));
// Adjust the photo before drawing captions, spectrum and menus.
wire image_hs,image_vs,image_de;wire [23:0] image_rgb;
wl_image_adjust image_adjust(
 .clk(video_clk),.rst(rst_video),.hs_in(hs),.vs_in(vs),.de_in(de),.rgb_in(vout_data),
 .config_async(image_config),.config_toggle_async(image_config_toggle),.frame_config(image_frame_config),
 .hs_out(image_hs),.vs_out(image_vs),.de_out(image_de),.rgb_out(image_rgb),.config_ack_toggle(image_config_ack_toggle));
wl_osd #(.CAPTION_FILE("voice_captions.hex"),.VOICE_CAPTIONS(1)) overlay(
 .clk(video_clk),.rst(rst_video),.hs_in(image_hs),.vs_in(image_vs),.de_in(image_de),.rgb_in(image_rgb),
 .station_id(displayed_id),.auto_mode(scene_sync[1]),.test_audio(test_sync[1]),.dwell_seconds(dwell_sync),
 .hs_out(osd_hs),.vs_out(osd_vs),.de_out(osd_de),.rgb_out(osd_rgb),
 .voice_subtitle_phase(voice_subtitle_phase),.voice_subtitle_reveal(voice_subtitle_reveal));

wire fx_hs,fx_vs,fx_de;wire [23:0] fx_rgb;
wl_video_fx video_fx(
 .clk(video_clk),.rst(rst_video),
 .hs_in(osd_hs),.vs_in(osd_vs),.de_in(osd_de),.rgb_in(osd_rgb),
 .fade_coeff(fade_coeff),
 .hs_out(fx_hs),.vs_out(fx_vs),.de_out(fx_de),.rgb_out(fx_rgb));

wire signed [16:0] mono_sum=$signed(audio_left_data[23:8])+$signed({audio_right_data[23],audio_right_data[23:8]});
wire [63:0] spectrum_levels;wire spectrum_overrun;
wire spectrum_enable=music_play && spectrum_switch_sync[1];
wl_audio_spectrum spectrum(
 .clk(video_clk),.rst(rst_video),.enable(spectrum_enable),
 .sample_valid(music_sample_valid),.sample_pcm(mono_sum[16:1]),
 .levels(spectrum_levels),.levels_valid(),.sample_overrun(spectrum_overrun));
wire spectrum_hs,spectrum_vs,spectrum_de;wire [23:0] spectrum_rgb;
wl_spectrum_overlay spectrum_overlay(
 .clk(video_clk),.rst(rst_video),.enable(spectrum_enable),.levels(spectrum_levels),
 .hs_in(fx_hs),.vs_in(fx_vs),.de_in(fx_de),.rgb_in(fx_rgb),
 .hs_out(spectrum_hs),.vs_out(spectrum_vs),.de_out(spectrum_de),.rgb_out(spectrum_rgb));
wire menu_hs,menu_vs,menu_de;wire [23:0] menu_rgb;
wl_music_menu music_menu(
 .clk(video_clk),.rst(rst_video),.menu_toggle(menu_sync[1]),.track_id(track_sync),.track_count(count_sync),
 .test_mode(test_sync[1]),
 .arrival_active(chime_active),
 .narration_active(voice_active),.narration_error(voice_control_error || voice_underrun),
 .playing(music_play),.audio_error(music_error_sync[1]),.underrun(music_underrun || spectrum_overrun),
 .hs_in(spectrum_hs),.vs_in(spectrum_vs),.de_in(spectrum_de),.rgb_in(spectrum_rgb),
 .hs_out(menu_hs),.vs_out(menu_vs),.de_out(menu_de),.rgb_out(menu_rgb));

wire settings_hs,settings_vs,settings_de;wire [23:0] settings_rgb;
wl_image_settings_overlay image_settings(
 .clk(video_clk),.rst(rst_video),.hs_in(menu_hs),.vs_in(menu_vs),.de_in(menu_de),.rgb_in(menu_rgb),
 .config_in(image_frame_config),
 .hs_out(settings_hs),.vs_out(settings_vs),.de_out(settings_de),.rgb_out(settings_rgb));

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (settings_vs),
    .I_de          (settings_de),
    .I_rgb         (settings_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_video),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
