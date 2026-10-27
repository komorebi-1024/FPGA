// Source completion, SDRAM completion, and display acknowledgement are distinct.
// Never recycle the old front buffer until video has acknowledged its new read.
module wl_playlist_ctrl #(
 parameter integer CLK_HZ=100000000,
 parameter integer TRANSFER_TIMEOUT=2000000000
)(
 input wire clk,input wire rst,input wire catalog_ready,input wire media_error,
 input wire reader_idle,input wire source_done,input wire write_finish_toggle_async,
 input wire publish_ack_async,input wire next_press,input wire auto_press,input wire audio_press,
 input wire [1:0] dwell_switch_async,
 output reg load_start,output reg [1:0] load_id,output reg [1:0] write_buffer,
 output reg publish_toggle,output reg [1:0] publish_buffer,output reg [1:0] publish_id,
 output reg auto_enabled,output reg test_audio,output reg [1:0] displayed_id,
 output wire busy,output reg [3:0] dwell_seconds,output reg [2:0] state
);
localparam WAIT_CATALOG=0,LOADING=1,PUBLISH=2,IDLE=3,ERROR=4;
(* async_reg="true" *) reg [2:0] wr_sync,ack_sync;
(* async_reg="true" *) reg [1:0] sw_meta,sw_sync;
reg source_seen,write_seen,pending_next;
reg [31:0] dwell_count,dwell_limit;
reg [31:0] transfer_watchdog;
wire wr_pulse=wr_sync[2]^wr_sync[1];
assign busy=state!=IDLE;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  wr_sync<=0;ack_sync<=0;sw_meta<=0;sw_sync<=0;
  source_seen<=0;write_seen<=0;pending_next<=0;
  load_start<=0;load_id<=0;write_buffer<=0;publish_toggle<=0;publish_buffer<=0;publish_id<=0;
  auto_enabled<=0;test_audio<=1;displayed_id<=0;dwell_seconds<=5;
  dwell_count<=0;dwell_limit<=CLK_HZ*5;state<=WAIT_CATALOG;transfer_watchdog<=0;
 end else begin
  wr_sync<={wr_sync[1:0],write_finish_toggle_async};ack_sync<={ack_sync[1:0],publish_ack_async};
  sw_meta<=dwell_switch_async;sw_sync<=sw_meta;
  load_start<=0;
  if(state==LOADING || state==PUBLISH)transfer_watchdog<=transfer_watchdog+1'b1;
  else transfer_watchdog<=0;
  if(next_press)begin pending_next<=1;auto_enabled<=0;end
  else if(auto_press)auto_enabled<=~auto_enabled;
  if(audio_press)test_audio<=~test_audio;
  if(!auto_enabled || auto_press || state!=IDLE)dwell_count<=0;
  case(state)
   WAIT_CATALOG:if(catalog_ready && reader_idle)begin
    load_id<=0;write_buffer<=0;load_start<=1;source_seen<=0;write_seen<=0;state<=LOADING;
   end
   LOADING:begin
    if(source_done)source_seen<=1;
    if(wr_pulse)write_seen<=1;
    if((source_seen||source_done)&&(write_seen||wr_pulse))begin
     publish_buffer<=write_buffer;publish_id<=load_id;publish_toggle<=~publish_toggle;state<=PUBLISH;
    end
   end
   PUBLISH:if(ack_sync[2]==publish_toggle)begin
    displayed_id<=load_id;state<=IDLE;dwell_count<=0;
    case(sw_sync)
     0:begin dwell_seconds<=3;dwell_limit<=CLK_HZ*3;end
     1:begin dwell_seconds<=5;dwell_limit<=CLK_HZ*5;end
     2:begin dwell_seconds<=8;dwell_limit<=CLK_HZ*8;end
     3:begin dwell_seconds<=10;dwell_limit<=CLK_HZ*10;end
    endcase
   end
   IDLE:begin
    if(reader_idle && (pending_next || next_press || (auto_enabled&&!auto_press&&dwell_count>=dwell_limit-1)))begin
     load_id<=displayed_id+1'b1;write_buffer<={1'b0,~publish_buffer[0]};load_start<=1;
     source_seen<=0;write_seen<=0;pending_next<=0;dwell_count<=0;state<=LOADING;
    end else if(auto_enabled&&!auto_press)dwell_count<=dwell_count+1'b1;
   end
   ERROR:begin load_start<=0;auto_enabled<=0;end
   default:state<=ERROR;
  endcase
  if(media_error || ((state==LOADING || state==PUBLISH) && transfer_watchdog>=TRANSFER_TIMEOUT-1))begin state<=ERROR;load_start<=0;auto_enabled<=0;end
 end
end
endmodule
