// WestLake scene wrapper: media reader + scene controller + vendor SD SPI transport.
module sd_card_bmp(
 input wire clk,input wire rst,input wire key_next,input wire key_audio,
 input wire write_finish_toggle,input wire publish_ack,
 output wire [3:0] state_code,output wire [1:0] write_buf_idx,
 output wire publish_toggle,output wire [1:0] publish_buffer,output wire [1:0] publish_id,
 output wire publish_kind,output wire scene_mode,output wire test_audio,output wire [3:0] dwell_seconds,
 output wire write_req,input wire write_req_ack,output wire write_en,output wire [31:0] write_data,
 output wire SD_nCS,output wire SD_DCLK,output wire SD_MOSI,input wire SD_MISO,
 input wire [10:0] audio_fifo_level,input wire audio_fifo_full,
 output wire audio_fifo_write,output wire [31:0] audio_fifo_data,
 output wire audio_fifo_flush,output wire audio_buffer_ready,
 output wire [1:0] music_track_id,output wire [2:0] music_track_count,
 output wire music_error,output reg music_menu_toggle,
 input wire voice_request_toggle,input wire [1:0] voice_station,input wire voice_stop,
 input wire [9:0] voice_fifo_level,input wire voice_fifo_full,
 output wire voice_fifo_write,output wire [31:0] voice_fifo_data,output wire voice_fifo_flush,
 output wire voice_session_ack,output wire voice_buffer_ready,output wire voice_catalog_ready,output wire voice_reader_error,
 output wire [31:0] voice_total_frames,output wire [31:0] voice_cue1,output wire [31:0] voice_cue2,
 output wire [14:0] voice_char_counts,
 input wire auto_depart_toggle,
 output wire [8:0] image_config,output wire image_config_toggle,
 input wire image_config_ack_toggle
);
wire [3:0] media_status;
assign state_code=(player_state==3'd3 || player_state==3'd6)?4'hb:media_status;
wire sd_ready,sec_read,sec_valid,sec_end,catalog_ready,media_error,reader_idle,source_done,load_start;
wire [31:0] sec_addr;wire [7:0] sec_data;wire [23:0] pixel;
wire [4:0] load_id;wire advance_press,audio_short,audio_long,station_advance,music_next;wire [2:0] player_state;
wire image_read,image_valid,image_end,audio_read,audio_valid,audio_end;
wire [31:0] image_addr,audio_addr;wire [7:0] image_data,audio_data;
wire voice_read,voice_valid,voice_end,combined_read,combined_valid,combined_end;
wire [31:0] voice_addr,combined_addr;wire [7:0] voice_data,combined_data;
wire [8:0] image_requested_config;
(* async_reg="true" *) reg [2:0] depart_sync;
always @(posedge clk or posedge rst)
 if(rst)depart_sync<=0;else depart_sync<={depart_sync[1:0],auto_depart_toggle};
// Ignore a late automatic request after KEY2 has already started departure.
wire auto_depart_press=(depart_sync[2]^depart_sync[1]) && player_state==3'd3;
(* async_reg="true" *) reg [1:0] wrack_sync;
always @(posedge clk or posedge rst)if(rst)wrack_sync<=0;else wrack_sync<={wrack_sync[0],write_req_ack};
assign write_data={pixel,8'h00};
wl_key_debounce advance_key(clk,rst,key_next,advance_press);
wl_key_gesture audio_key(.clk(clk),.rst(rst),.key_n(key_audio),.short_press(audio_short),.long_press(audio_long));
wl_image_ui_ctrl image_controls(
 .clk(clk),.rst(rst),.advance_press(advance_press),.audio_short(audio_short),.audio_long(audio_long),
 .station_advance(station_advance),.music_next(music_next),.config_data(image_requested_config),.config_toggle());
wl_image_config_source image_config_source(
 .clk(clk),.rst(rst),.desired_config(image_requested_config),.ack_toggle_async(image_config_ack_toggle),
 .config_data(image_config),.config_toggle(image_config_toggle));
always @(posedge clk or posedge rst)
 if(rst)music_menu_toggle<=0;else if(music_next)music_menu_toggle<=~music_menu_toggle;
wl_media_reader media(
 .clk(clk),.rst(rst),.sd_ready(sd_ready),.sector_read(image_read),.sector_addr(image_addr),
 .sector_data(image_data),.sector_valid(image_valid),.sector_end(image_end),.catalog_ready(catalog_ready),
 .error(media_error),.status(media_status),.load_start(load_start),.load_id(load_id),.idle(reader_idle),
 .load_done(source_done),.write_req(write_req),.write_ack(wrack_sync[1]),.pixel_valid(write_en),.pixel_rgb(pixel));
wl_scene_ctrl #(.AUTO_DEPART(0)) player(
 .clk(clk),.rst(rst),.catalog_ready(catalog_ready),.media_error(media_error),.reader_idle(reader_idle),
 .source_done(source_done),.write_finish_toggle_async(write_finish_toggle),.publish_ack_async(publish_ack),
 .advance_press(station_advance || auto_depart_press),.audio_press(1'b0),
 .load_start(load_start),.load_id(load_id),.write_buffer(write_buf_idx),.publish_toggle(publish_toggle),
 .publish_buffer(publish_buffer),.publish_id(publish_id),.publish_kind(publish_kind),
 .scene_mode(scene_mode),.test_audio(test_audio),.dwell_seconds(dwell_seconds),.state(player_state));
wl_music_reader music_reader(
 .clk(clk),.rst(rst),.sd_ready(sd_ready),.next_track(music_next),
 .sector_read(audio_read),.sector_addr(audio_addr),.sector_data(audio_data),.sector_valid(audio_valid),.sector_end(audio_end),
 .fifo_level(audio_fifo_level),.fifo_full(audio_fifo_full),.fifo_write(audio_fifo_write),.fifo_data(audio_fifo_data),
 .fifo_flush(audio_fifo_flush),.buffer_ready(audio_buffer_ready),
 .track_id(music_track_id),.track_count(music_track_count),.catalog_ready(),.audio_error(music_error));
wl_voice_reader voice_reader(
 .clk(clk),.rst(rst),.sd_ready(sd_ready),
 .start_toggle_async(voice_request_toggle),.station_id_async(voice_station),.stop_async(voice_stop),
 .sector_read(voice_read),.sector_addr(voice_addr),.sector_data(voice_data),.sector_valid(voice_valid),.sector_end(voice_end),
 .fifo_level(voice_fifo_level),.fifo_full(voice_fifo_full),.fifo_write(voice_fifo_write),.fifo_data(voice_fifo_data),.fifo_flush(voice_fifo_flush),
 .session_ack_toggle(voice_session_ack),.buffer_ready(voice_buffer_ready),.catalog_ready(voice_catalog_ready),.voice_error(voice_reader_error),
 .current_total_frames(voice_total_frames),.current_cue1(voice_cue1),.current_cue2(voice_cue2),.current_chars(voice_char_counts));
// Voice > music > picture, with each complete sector locked to its requester.
// Paused music is retained in its own FIFO; narration never flushes that head.
wl_sd_arbiter audio_arbiter(
 .clk(clk),.rst(rst),.image_read(audio_read),.image_addr(audio_addr),
 .image_data(audio_data),.image_valid(audio_valid),.image_end(audio_end),
 .audio_read(voice_read),.audio_addr(voice_addr),.audio_data(voice_data),.audio_valid(voice_valid),.audio_end(voice_end),
 .sector_read(combined_read),.sector_addr(combined_addr),.sector_data(combined_data),.sector_valid(combined_valid),.sector_end(combined_end));
wl_sd_arbiter sd_arbiter(
 .clk(clk),.rst(rst),.image_read(image_read),.image_addr(image_addr),
 .image_data(image_data),.image_valid(image_valid),.image_end(image_end),
 .audio_read(combined_read),.audio_addr(combined_addr),.audio_data(combined_data),.audio_valid(combined_valid),.audio_end(combined_end),
 .sector_read(sec_read),.sector_addr(sec_addr),.sector_data(sec_data),.sector_valid(sec_valid),.sector_end(sec_end));
sd_card_top transport(
 .clk(clk),.rst(rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
 .sd_init_done(sd_ready),.sd_sec_read(sec_read),.sd_sec_read_addr(sec_addr),.sd_sec_read_data(sec_data),
 .sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),.sd_sec_write(1'b0),
 .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
endmodule
