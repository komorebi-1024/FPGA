// Station narration controller, synchronous to the 25 MHz HDMI pixel clock.
// Subtitle progress follows PCM FIFO pops, never SD read completion or wall time.
// The reader holds metadata until the next request; ready acknowledges that the
// metadata and its FIFO belong to request_toggle. Commands must be >=3 SD clocks
// apart, as for any toggle CDC. Arrival publications are normally frames apart.
module wl_voice_ctrl #(
 parameter integer CLK_HZ=25000000,
 parameter integer WAIT_TIMEOUT_CYCLES=CLK_HZ*2
)(
 input wire clk,input wire rst,input wire arrival_event,
 input wire [1:0] station_id,input wire in_station,
 input wire reader_ack_toggle_async,input wire reader_ready_async,
 input wire reader_error_async,input wire reader_catalog_ready_async,
 input wire voice_fifo_reset,input wire voice_pop,
 input wire [31:0] current_total_frames_async,
 input wire [31:0] current_cue1_async,input wire [31:0] current_cue2_async,
 input wire [14:0] current_chars_async,
 output reg request_toggle,output reg [1:0] request_station,
 output wire stop_request,output wire voice_play,output wire voice_active,
 output reg [1:0] subtitle_phase,output reg [5:0] subtitle_reveal,
 output wire subtitle_session_toggle,
 output reg voice_done,output reg voice_complete,output reg voice_error
);
(* async_reg="true" *) reg [1:0] ack_sync,ready_sync,error_sync,catalog_sync;
reg [31:0] total_meta,total_sync,cue1_meta,cue1_sync,cue2_meta,cue2_sync;
reg [14:0] chars_meta,chars_sync;
reg pending,playing,clear_seen;
reg [1:0] start_guard;
reg [31:0] wait_count,played_count,total_frames,cue1,cue2;
reg [14:0] sentence_chars;
reg [31:0] segment_frames;
reg [4:0] segment_chars;
reg [32:0] character_acc;
reg next_sentence;
wire [32:0] character_sum=character_acc+{28'd0,segment_chars};
wire [31:0] next_frames=(subtitle_phase==0)?(cue2-cue1):(total_frames-cue2);
wire [4:0] next_chars=(subtitle_phase==0)?sentence_chars[9:5]:sentence_chars[14:10];
wire at_cue=(subtitle_phase==0 && played_count+1'b1==cue1) ||
            (subtitle_phase==1 && played_count+1'b1==cue2);
assign stop_request=!in_station;
assign voice_play=playing && in_station && !arrival_event && !voice_fifo_reset;
assign voice_active=(pending || playing) && in_station;
assign subtitle_session_toggle=request_toggle;

always @(posedge clk or posedge rst)begin
 if(rst)begin
  ack_sync<=0;ready_sync<=0;error_sync<=0;catalog_sync<=0;
  total_meta<=0;total_sync<=0;cue1_meta<=0;cue1_sync<=0;cue2_meta<=0;cue2_sync<=0;
  chars_meta<=0;chars_sync<=0;
 end else begin
  ack_sync<={ack_sync[0],reader_ack_toggle_async};
  ready_sync<={ready_sync[0],reader_ready_async};
  error_sync<={error_sync[0],reader_error_async};
  catalog_sync<={catalog_sync[0],reader_catalog_ready_async};
  total_meta<=current_total_frames_async;total_sync<=total_meta;
  cue1_meta<=current_cue1_async;cue1_sync<=cue1_meta;
  cue2_meta<=current_cue2_async;cue2_sync<=cue2_meta;
  chars_meta<=current_chars_async;chars_sync<=chars_meta;
 end
end

always @(posedge clk or posedge rst)begin
 if(rst)begin
  request_toggle<=0;request_station<=0;pending<=0;playing<=0;
  clear_seen<=0;start_guard<=0;wait_count<=0;played_count<=0;
  total_frames<=0;cue1<=0;cue2<=0;sentence_chars<=0;
  segment_frames<=0;segment_chars<=0;character_acc<=0;next_sentence<=0;
  subtitle_phase<=0;subtitle_reveal<=0;
  voice_done<=0;voice_complete<=0;voice_error<=0;
 end else begin
  voice_done<=0;
  if(!in_station)begin
   pending<=0;playing<=0;clear_seen<=0;start_guard<=0;wait_count<=0;
   played_count<=0;character_acc<=0;next_sentence<=0;
   subtitle_phase<=0;subtitle_reveal<=0;voice_complete<=0;voice_error<=0;
  end else if(arrival_event)begin
   request_toggle<=~request_toggle;request_station<=station_id;
   pending<=1;playing<=0;clear_seen<=0;start_guard<=3;wait_count<=0;
   played_count<=0;character_acc<=0;next_sentence<=0;
   subtitle_phase<=0;subtitle_reveal<=0;voice_complete<=0;voice_error<=0;
  end else if(pending)begin
   if(start_guard!=0)start_guard<=start_guard-1'b1;
   else if(voice_fifo_reset || !ready_sync[1])clear_seen<=1;
   if(catalog_sync[1] && error_sync[1])begin
    pending<=0;playing<=0;voice_error<=1;
    // With a missing/invalid voice catalog leave useful station text visible.
    subtitle_phase<=1;subtitle_reveal<=32;
   end else if(wait_count>=WAIT_TIMEOUT_CYCLES-1)begin
    pending<=0;playing<=0;voice_error<=1;subtitle_phase<=1;subtitle_reveal<=32;
   end else if(start_guard==0 && clear_seen && ack_sync[1]==request_toggle &&
               ready_sync[1] && !voice_fifo_reset)begin
    if(total_sync>cue2_sync && cue2_sync>cue1_sync && cue1_sync!=0 &&
       chars_sync[4:0]!=0 && chars_sync[9:5]!=0 && chars_sync[14:10]!=0 &&
       cue1_sync>=chars_sync[4:0] && cue2_sync-cue1_sync>=chars_sync[9:5] &&
       total_sync-cue2_sync>=chars_sync[14:10])begin
     total_frames<=total_sync;cue1<=cue1_sync;cue2<=cue2_sync;sentence_chars<=chars_sync;
     segment_frames<=cue1_sync;segment_chars<=chars_sync[4:0];
     // ceil(samples*characters/segment_length) shows the first glyph on the
     // first spoken sample, and gives the last glyph one full character slot.
     pending<=0;playing<=1;played_count<=0;character_acc<={1'b0,cue1_sync}-1'b1;
    end else begin
     pending<=0;voice_error<=1;subtitle_phase<=1;subtitle_reveal<=32;
    end
   end else wait_count<=wait_count+1'b1;
  end else if(playing && voice_pop && voice_play)begin
   played_count<=played_count+1'b1;
   if(played_count+1'b1>=total_frames)begin
    playing<=0;voice_done<=1;voice_complete<=1;
    subtitle_phase<=2;subtitle_reveal<={1'b0,sentence_chars[14:10]};
    character_acc<=0;next_sentence<=0;
   end else if(next_sentence)begin
    // Keep the preceding sentence complete until the first sample of the next.
    subtitle_phase<=subtitle_phase+1'b1;next_sentence<=0;
    segment_frames<=next_frames;segment_chars<=next_chars;
    if(next_frames==1)begin
     character_acc<=0;subtitle_reveal<={1'b0,next_chars};next_sentence<=1;
    end else begin
     character_acc<={28'd0,next_chars}-1'b1;subtitle_reveal<=1;
    end
   end else if(at_cue)begin
    subtitle_reveal<={1'b0,segment_chars};character_acc<=0;next_sentence<=1;
   end else if(character_sum>={1'b0,segment_frames})begin
    character_acc<=character_sum-{1'b0,segment_frames};
    if(subtitle_reveal<segment_chars)subtitle_reveal<=subtitle_reveal+1'b1;
   end else character_acc<=character_sum;
  end
 end
end
endmodule
