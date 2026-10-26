// WestLake catalog + playback wrapper. Vendor SD SPI transport retained.
module sd_card_bmp(
 input wire clk,input wire rst,input wire key_next,input wire key_auto,input wire key_audio,
 input wire [1:0] dwell_switch,input wire write_finish_toggle,input wire publish_ack,
 output wire [3:0] state_code,output wire [1:0] write_buf_idx,
 output wire publish_toggle,output wire [1:0] publish_buffer,output wire [1:0] publish_id,
 output wire auto_enabled,output wire test_audio,output wire [3:0] dwell_seconds,
 output wire write_req,input wire write_req_ack,output wire write_en,output wire [31:0] write_data,
 output wire SD_nCS,output wire SD_DCLK,output wire SD_MOSI,input wire SD_MISO
);
wire [3:0] media_status;
assign state_code=(player_state==4 && !media_error)?4'hb:media_status;
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
 .error(media_error),.status(media_status),.load_start(load_start),.load_id(load_id),.idle(reader_idle),
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
 .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
endmodule
