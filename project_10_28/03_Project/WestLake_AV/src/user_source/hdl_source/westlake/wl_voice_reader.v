// One-shot station PCM reader. A separate FIFO preserves the paused music head.
// Commands are held-payload/toggle CDC; stop consumes pending starts, never loops.
// Metadata/cues count stereo sample frames, not bytes or SD sectors.
module wl_voice_reader #(
 parameter [31:0] CATALOG_LBA=2058,
 parameter [31:0] DISK_SECTORS=262144
)(
 input wire clk,input wire rst,input wire sd_ready,
 input wire start_toggle_async,input wire [1:0] station_id_async,input wire stop_async,
 output reg sector_read,output reg [31:0] sector_addr,
 input wire [7:0] sector_data,input wire sector_valid,input wire sector_end,
 input wire [9:0] fifo_level,input wire fifo_full,
 output reg fifo_write,output reg [31:0] fifo_data,output reg fifo_flush,
 output reg session_ack_toggle,output reg buffer_ready,
 output reg catalog_ready,output reg voice_error,
 output reg [31:0] current_total_frames,current_cue1,current_cue2,
 output reg [14:0] current_chars
);
localparam WAIT_SD=0,META_READ=1,META_CHECK=2,VALIDATE=3,
 IDLE=4,FLUSH=5,WAIT_DATA=6,DATA_READ=7,FINISHED=8,BAD=9;
reg [3:0] state;
(* async_reg="true" *) reg [2:0] start_sync;
(* async_reg="true" *) reg [1:0] stop_sync;
reg [1:0] station_meta,station_sync;
reg start_seen,pending_start,pending_toggle,discard,session_active;
reg [1:0] pending_station;
reg [8:0] byte_index;
reg [63:0] magic;
reg [7:0] count_field,channels,bits,segments;
reg [31:0] rate;
reg reserved_bad;
reg [31:0] starts[0:3],frames[0:3],cue1[0:3],cue2[0:3];
reg [7:0] chars0[0:3],chars1[0:3],chars2[0:3];
reg [1:0] check_index,validate_phase;
reg [31:0] check_start,check_frames,check_cue1,check_cue2;
reg [7:0] check_chars0,check_chars1,check_chars2;
reg [32:0] check_sectors,check_end;
reg check_bad;
reg [6:0] flush_count;
reg [31:0] frames_left,session_start;
reg [23:0] sample_bytes;
wire [1:0] record_index=(byte_index-9'd16)>>5;
wire [4:0] record_byte=byte_index-9'd16;
wire command_event=start_sync[2]!=start_seen;
wire stop=stop_sync[1];
wire last_frame_now=sector_valid && byte_index[1:0]==3 && frames_left==1;
wire operational=state==IDLE || state==FLUSH || state==WAIT_DATA || state==DATA_READ || state==FINISHED;
integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  start_sync<=0;stop_sync<=2'b11;station_meta<=0;station_sync<=0;
  start_seen<=0;pending_start<=0;pending_toggle<=0;pending_station<=0;
  discard<=0;session_active<=0;state<=WAIT_SD;
  sector_read<=0;sector_addr<=0;byte_index<=0;
  magic<=0;count_field<=0;channels<=0;bits<=0;segments<=0;rate<=0;reserved_bad<=0;
  check_index<=0;validate_phase<=0;check_start<=0;check_frames<=0;check_cue1<=0;check_cue2<=0;
  check_chars0<=0;check_chars1<=0;check_chars2<=0;check_sectors<=0;check_end<=0;check_bad<=0;
  flush_count<=0;frames_left<=0;session_start<=0;sample_bytes<=0;
  fifo_write<=0;fifo_data<=0;fifo_flush<=1;session_ack_toggle<=0;buffer_ready<=0;
  catalog_ready<=0;voice_error<=0;current_total_frames<=0;current_cue1<=0;current_cue2<=0;current_chars<=0;
  for(i=0;i<4;i=i+1)begin starts[i]<=0;frames[i]<=0;cue1[i]<=0;cue2[i]<=0;
   chars0[i]<=0;chars1[i]<=0;chars2[i]<=0;end
 end else begin
  start_sync<={start_sync[1:0],start_toggle_async};stop_sync<={stop_sync[0],stop_async};
  station_meta<=station_id_async;station_sync<=station_meta;
  fifo_write<=0;
  // Small valid clips (<128 frames) can also start once their exact tail is loaded.
  if(!fifo_flush && session_active && (fifo_level>=128 || (state==FINISHED && fifo_level!=0)))buffer_ready<=1;
  case(state)
   WAIT_SD:if(sd_ready)begin sector_read<=1;sector_addr<=CATALOG_LBA;byte_index<=0;state<=META_READ;end
   META_READ:begin
    if(sector_valid)begin
     byte_index<=byte_index+1'b1;
     if(byte_index<8)magic[byte_index*8 +:8]<=sector_data;
     case(byte_index)
      8:count_field<=sector_data;9:channels<=sector_data;10:bits<=sector_data;11:segments<=sector_data;
      12:rate[7:0]<=sector_data;13:rate[15:8]<=sector_data;14:rate[23:16]<=sector_data;15:rate[31:24]<=sector_data;
     endcase
     if(byte_index>=16 && byte_index<144)begin
      case(record_byte)
       0,1,2,3:starts[record_index][byte_index[1:0]*8 +:8]<=sector_data;
       4,5,6,7:frames[record_index][byte_index[1:0]*8 +:8]<=sector_data;
       8,9,10,11:cue1[record_index][byte_index[1:0]*8 +:8]<=sector_data;
       12,13,14,15:cue2[record_index][byte_index[1:0]*8 +:8]<=sector_data;
       20:chars0[record_index]<=sector_data;
       21:chars1[record_index]<=sector_data;
       22:chars2[record_index]<=sector_data;
       // CRC32 at offsets16..19 is checked by the host image verifier.
       16,17,18,19:begin end
       default:if(sector_data!=0)reserved_bad<=1;
      endcase
     end
    end
    if(sector_end)begin sector_read<=0;state<=META_CHECK;end
   end
   META_CHECK:begin
    if(magic!=64'h313030434f564c57 || count_field!=4 || channels!=2 || bits!=16 || segments!=3 || rate!=48000 || reserved_bad)begin
     catalog_ready<=1;voice_error<=1;state<=BAD;
    end else begin check_index<=0;validate_phase<=0;state<=VALIDATE;end
   end
   VALIDATE:case(validate_phase)
    0:begin
     check_start<=starts[check_index];check_frames<=frames[check_index];
     check_cue1<=cue1[check_index];check_cue2<=cue2[check_index];
     check_chars0<=chars0[check_index];check_chars1<=chars1[check_index];check_chars2<=chars2[check_index];validate_phase<=1;
    end
    1:begin
     check_sectors<=({1'b0,check_frames}+33'd127)>>7;
     check_bad<=check_start<=CATALOG_LBA || check_frames==0 || check_cue1==0 || check_cue1>=check_cue2 || check_cue2>=check_frames ||
       check_chars0==0 || check_chars0>31 || check_chars1==0 || check_chars1>31 || check_chars2==0 || check_chars2>31;
     validate_phase<=2;
    end
    2:begin check_end<={1'b0,check_start}+check_sectors;validate_phase<=3;end
    3:begin
     if(check_bad || check_end>{1'b0,DISK_SECTORS})begin catalog_ready<=1;voice_error<=1;state<=BAD;end
     else if(check_index==3)begin catalog_ready<=1;state<=IDLE;end
     else begin check_index<=check_index+1'b1;validate_phase<=0;end
    end
   endcase
   IDLE:if(pending_start && !stop && !command_event)begin
    current_total_frames<=frames[pending_station];current_cue1<=cue1[pending_station];current_cue2<=cue2[pending_station];
    current_chars<={chars2[pending_station][4:0],chars1[pending_station][4:0],chars0[pending_station][4:0]};
    session_start<=starts[pending_station];session_ack_toggle<=pending_toggle;
    pending_start<=0;discard<=0;session_active<=1;
    fifo_flush<=1;buffer_ready<=0;flush_count<=0;state<=FLUSH;
   end
   FLUSH:begin
    fifo_flush<=1;buffer_ready<=0;
    if(flush_count==63)begin
     fifo_flush<=0;frames_left<=current_total_frames;sector_addr<=session_start;state<=WAIT_DATA;
    end else flush_count<=flush_count+1'b1;
   end
   WAIT_DATA:if(!stop && !command_event && fifo_level<=256 && !fifo_full)begin byte_index<=0;sector_read<=1;state<=DATA_READ;end
   DATA_READ:begin
    if(sector_valid)begin
     byte_index<=byte_index+1'b1;
     if(frames_left!=0)begin
      case(byte_index[1:0])
       0:sample_bytes[7:0]<=sector_data;
       1:sample_bytes[15:8]<=sector_data;
       2:sample_bytes[23:16]<=sector_data;
       3:begin
        frames_left<=frames_left-1'b1;
        if(!discard && !fifo_flush && !command_event && !stop)begin
         if(fifo_full)voice_error<=1;
         else begin fifo_data<={sector_data,sample_bytes};fifo_write<=1;end
        end
       end
      endcase
     end
    end
    if(sector_end)begin
     sector_read<=0;
     if(discard || stop || pending_start)state<=IDLE;
     else if(frames_left==0 || last_frame_now)state<=FINISHED;
     else begin sector_addr<=sector_addr+1'b1;state<=WAIT_DATA;end
    end
   end
   FINISHED:begin end
   BAD:begin fifo_flush<=1;buffer_ready<=0;sector_read<=0;pending_start<=0;session_active<=0;end
   default:begin voice_error<=1;state<=BAD;end
  endcase
  // A new command cancels the old FIFO immediately, but never withdraws a
  // sector request in flight. DATA_READ drains/discards before accepting latest.
  if(command_event)begin
   start_seen<=start_sync[2];pending_start<=!stop;
   pending_station<=station_sync;pending_toggle<=start_sync[2];
   fifo_flush<=1;buffer_ready<=0;discard<=1;session_active<=0;fifo_write<=0;
   if(operational && !(state==DATA_READ && !sector_end))state<=IDLE;
  end
  if(stop)begin
   pending_start<=0;fifo_flush<=1;buffer_ready<=0;discard<=1;session_active<=0;fifo_write<=0;
   if(operational && !(state==DATA_READ && !sector_end))state<=IDLE;
  end
 end
end
endmodule
