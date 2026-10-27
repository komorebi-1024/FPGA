// Scene controller: STATION (station image + arrival chime, 5s hold, key=depart)
// and SECTION (5 promo images at 1s each, looping until key=arrive next station).
// A single "advance" key plays both roles. Reuses the load/publish/double-buffer
// handshake of the original playlist controller.
module wl_scene_ctrl #(
 parameter integer CLK_HZ=100000000,
 parameter integer NUM_STATIONS=4,
 parameter integer PROMOS_PER_INTERVAL=5,
 parameter integer STATION_DWELL_MS=5000,
 parameter integer PROMO_DWELL_MS=3000,
 parameter integer TRANSFER_TIMEOUT=2000000000
)(
 input wire clk,input wire rst,input wire catalog_ready,input wire media_error,
 input wire reader_idle,input wire source_done,input wire write_finish_toggle_async,
 input wire publish_ack_async,input wire advance_press,input wire audio_press,
 output reg load_start,output reg [4:0] load_id,output reg [1:0] write_buffer,
 output reg publish_toggle,output reg [1:0] publish_buffer,output reg [1:0] publish_id,
 output reg publish_kind,output reg scene_mode,output reg test_audio,
 output reg [3:0] dwell_seconds,output reg [2:0] state
);
localparam WAIT_CATALOG=0,STATION_LOAD=1,STATION_PUBLISH=2,STATION_HOLD=3,
 SECTION_LOAD=4,SECTION_PUBLISH=5,SECTION_HOLD=6,ERROR=7;
localparam [31:0] STATION_DWELL=CLK_HZ/1000*STATION_DWELL_MS;
localparam [31:0] PROMO_DWELL=CLK_HZ/1000*PROMO_DWELL_MS;
(* async_reg="true" *) reg [2:0] wr_sync,ack_sync;
reg source_seen,write_seen,pending_advance;
reg [1:0] station_id;
reg [2:0] promo_seq;
reg [31:0] dwell_count,dwell_limit;
reg [31:0] transfer_watchdog;
wire wr_pulse=wr_sync[2]^wr_sync[1];
wire [2:0] next_promo_seq=(promo_seq==PROMOS_PER_INTERVAL-1)?3'd0:promo_seq+1'b1;
wire [1:0] next_station=(station_id==NUM_STATIONS-1)?2'd0:(station_id+2'd1);
always @(posedge clk or posedge rst)begin
 if(rst)begin
  wr_sync<=0;ack_sync<=0;source_seen<=0;write_seen<=0;pending_advance<=0;
  load_start<=0;load_id<=0;write_buffer<=0;publish_toggle<=0;publish_buffer<=0;publish_id<=0;
  publish_kind<=0;scene_mode<=0;test_audio<=0;dwell_seconds<=5;
  station_id<=0;promo_seq<=0;dwell_count<=0;dwell_limit<=STATION_DWELL;
  state<=WAIT_CATALOG;transfer_watchdog<=0;
 end else begin
  wr_sync<={wr_sync[1:0],write_finish_toggle_async};ack_sync<={ack_sync[1:0],publish_ack_async};
  load_start<=0;
  if(state==STATION_LOAD||state==STATION_PUBLISH||state==SECTION_LOAD||state==SECTION_PUBLISH)
   transfer_watchdog<=transfer_watchdog+1'b1;
  else transfer_watchdog<=0;
  if(advance_press)pending_advance<=1;
  if(audio_press)test_audio<=~test_audio;
  case(state)
   WAIT_CATALOG:if(catalog_ready && reader_idle)begin
    station_id<=0;promo_seq<=0;load_id<=0;write_buffer<=0;load_start<=1;
    source_seen<=0;write_seen<=0;scene_mode<=1;state<=STATION_LOAD;
   end
   STATION_LOAD:begin
    if(source_done)source_seen<=1;
    if(wr_pulse)write_seen<=1;
    if((source_seen||source_done)&&(write_seen||wr_pulse))begin
     publish_buffer<=write_buffer;publish_id<=station_id;publish_kind<=1;
     publish_toggle<=~publish_toggle;state<=STATION_PUBLISH;
    end
   end
   STATION_PUBLISH:if(ack_sync[2]==publish_toggle)begin
    scene_mode<=1;dwell_seconds<=5;dwell_limit<=STATION_DWELL;dwell_count<=0;state<=STATION_HOLD;
   end
   STATION_HOLD:begin
    if(pending_advance||advance_press||dwell_count>=dwell_limit-1)begin
     promo_seq<=0;load_id<=NUM_STATIONS+station_id*PROMOS_PER_INTERVAL;
     write_buffer<={1'b0,~publish_buffer[0]};load_start<=1;
     source_seen<=0;write_seen<=0;pending_advance<=0;dwell_count<=0;scene_mode<=0;state<=SECTION_LOAD;
    end else dwell_count<=dwell_count+1'b1;
   end
   SECTION_LOAD:begin
    if(source_done)source_seen<=1;
    if(wr_pulse)write_seen<=1;
    if((source_seen||source_done)&&(write_seen||wr_pulse))begin
     publish_buffer<=write_buffer;publish_id<=station_id;publish_kind<=0;
     publish_toggle<=~publish_toggle;state<=SECTION_PUBLISH;
    end
   end
   SECTION_PUBLISH:if(ack_sync[2]==publish_toggle)begin
    dwell_seconds<=1;dwell_limit<=PROMO_DWELL;dwell_count<=0;state<=SECTION_HOLD;
   end
   SECTION_HOLD:begin
    if(pending_advance||advance_press)begin
     station_id<=next_station;load_id<=next_station;
     write_buffer<={1'b0,~publish_buffer[0]};load_start<=1;
     source_seen<=0;write_seen<=0;pending_advance<=0;dwell_count<=0;scene_mode<=1;state<=STATION_LOAD;
    end else if(dwell_count>=dwell_limit-1)begin
     promo_seq<=next_promo_seq;load_id<=NUM_STATIONS+station_id*PROMOS_PER_INTERVAL+next_promo_seq;
     write_buffer<={1'b0,~publish_buffer[0]};load_start<=1;
     source_seen<=0;write_seen<=0;dwell_count<=0;state<=SECTION_LOAD;
    end else dwell_count<=dwell_count+1'b1;
   end
   ERROR:load_start<=0;
   default:state<=ERROR;
  endcase
  if(media_error || ((state==STATION_LOAD||state==STATION_PUBLISH||state==SECTION_LOAD||state==SECTION_PUBLISH) && transfer_watchdog>=TRANSFER_TIMEOUT-1))begin
   state<=ERROR;load_start<=0;
  end
 end
end
endmodule
