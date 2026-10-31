// Raw stereo PCM in continuous SD sectors, indexed by the WLPCM001 catalog.
// No FAT/WAV parser: pack_audio.py strips WAV headers and allocates the data.
// The read side pauses by not popping the FIFO; this side keeps it prefetched.
// A next_track pulse restarts the next song. Pulses during flush are ignored.
module wl_music_reader #(
 parameter [31:0] CATALOG_LBA=2057,
 parameter [31:0] DISK_SECTORS=262144
)(
 input wire clk,input wire rst,input wire sd_ready,input wire next_track,
 output reg sector_read,output reg [31:0] sector_addr,
 input wire [7:0] sector_data,input wire sector_valid,input wire sector_end,
 input wire [10:0] fifo_level,input wire fifo_full,
 output reg fifo_write,output reg [31:0] fifo_data,output reg fifo_flush,
 output reg [1:0] track_id,output reg [2:0] track_count,
 output reg catalog_ready,output reg audio_error,output reg buffer_ready
);
localparam WAIT_SD=0,META_READ=1,META_CHECK=2,VALIDATE=3,
 FLUSH=4,IDLE=5,DATA_READ=6,SILENT=7;
reg [2:0] state;
reg [8:0] byte_index;
reg [63:0] magic;
reg [7:0] count_field,channels,bits,flags;
reg [31:0] rate;
reg [31:0] starts[0:3],frames[0:3];
reg [1:0] check_index;
reg [1:0] validate_phase;
reg [31:0] check_start,check_frames;
reg [32:0] record_sectors,record_end;
reg [31:0] frames_left;
reg [23:0] sample_bytes;
reg [6:0] flush_count;
reg switch_pending;
wire [1:0] record_index=(byte_index-9'd16)>>4;
wire last_frame_now=sector_valid && byte_index[1:0]==3 && frames_left==1;
integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=WAIT_SD;sector_read<=0;sector_addr<=0;byte_index<=0;
  magic<=0;count_field<=0;channels<=0;bits<=0;flags<=0;rate<=0;
  check_index<=0;validate_phase<=0;check_start<=0;check_frames<=0;
  record_sectors<=0;record_end<=0;
  frames_left<=0;sample_bytes<=0;flush_count<=0;switch_pending<=0;
  fifo_write<=0;fifo_data<=0;fifo_flush<=1;track_id<=0;track_count<=0;
  catalog_ready<=0;audio_error<=0;buffer_ready<=0;
  for(i=0;i<4;i=i+1)begin starts[i]<=0;frames[i]<=0;end
 end else begin
  fifo_write<=0;
  if(!fifo_flush && fifo_level>=256)buffer_ready<=1;
  case(state)
   WAIT_SD:if(sd_ready)begin
    sector_addr<=CATALOG_LBA;sector_read<=1;byte_index<=0;state<=META_READ;
   end
   META_READ:begin
    if(sector_valid)begin
     byte_index<=byte_index+1'b1;
     if(byte_index<8)magic[byte_index*8 +:8]<=sector_data;
     case(byte_index)
      8:count_field<=sector_data;9:channels<=sector_data;
      10:bits<=sector_data;11:flags<=sector_data;
      12:rate[7:0]<=sector_data;13:rate[15:8]<=sector_data;
      14:rate[23:16]<=sector_data;15:rate[31:24]<=sector_data;
     endcase
     if(byte_index>=16 && byte_index<80)begin
      if(byte_index[3:0]<4)starts[record_index][byte_index[1:0]*8 +:8]<=sector_data;
      else if(byte_index[3:0]<8)frames[record_index][byte_index[1:0]*8 +:8]<=sector_data;
     end
    end
    if(sector_end)begin sector_read<=0;state<=META_CHECK;end
   end
   META_CHECK:begin
    if(magic!=64'h3130304d43504c57 || count_field>4 ||
       channels!=2 || bits!=16 || flags!=0 || rate!=48000)begin
     audio_error<=1;catalog_ready<=1;track_count<=0;state<=SILENT;
    end else begin
     track_count<=count_field[2:0];check_index<=0;validate_phase<=0;
     if(count_field==0)begin catalog_ready<=1;state<=SILENT;end
     else state<=VALIDATE;
    end
   end
   VALIDATE:begin
    // Startup-only validation is pipelined to keep the 100 MHz SD domain's
    // descriptor mux, ceil division, address addition and comparison apart.
    case(validate_phase)
     0:begin
      check_start<=starts[check_index];check_frames<=frames[check_index];
      validate_phase<=1;
     end
     1:begin
      record_sectors<=({1'b0,check_frames}+33'd127)>>7;
      validate_phase<=2;
     end
     2:begin record_end<={1'b0,check_start}+record_sectors;validate_phase<=3;end
     3:begin
      if(check_frames==0 || check_start<=CATALOG_LBA ||
         record_end>{1'b0,DISK_SECTORS})begin
       audio_error<=1;catalog_ready<=1;track_count<=0;state<=SILENT;
      end else if({1'b0,check_index}+1'b1==track_count)begin
       catalog_ready<=1;flush_count<=0;state<=FLUSH;
      end else begin check_index<=check_index+1'b1;validate_phase<=0;end
     end
    endcase
   end
   FLUSH:begin
    fifo_flush<=1;buffer_ready<=0;
    if(flush_count==63)begin
     fifo_flush<=0;switch_pending<=0;sector_addr<=starts[track_id];
     frames_left<=frames[track_id];state<=IDLE;
    end else flush_count<=flush_count+1'b1;
   end
   IDLE:if(fifo_level<=768 && !fifo_full)begin
    byte_index<=0;sector_read<=1;state<=DATA_READ;
   end
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
        if(!fifo_flush && !switch_pending && !next_track)begin
         if(fifo_full)audio_error<=1;
         else begin fifo_data<={sector_data,sample_bytes};fifo_write<=1;end
        end
       end
      endcase
     end
    end
    if(sector_end)begin
     sector_read<=0;
     if(switch_pending)begin flush_count<=0;state<=FLUSH;end
     else begin
      if(frames_left==0 || last_frame_now)begin
       sector_addr<=starts[track_id];frames_left<=frames[track_id];
      end else sector_addr<=sector_addr+1'b1;
      state<=IDLE;
     end
    end
   end
   SILENT:begin sector_read<=0;fifo_flush<=1;buffer_ready<=0;end
   default:begin state<=SILENT;audio_error<=1;end
  endcase
  if(next_track && catalog_ready && track_count!=0 && !fifo_flush)begin
   track_id<=({1'b0,track_id}+1'b1>=track_count)?2'd0:track_id+1'b1;
   fifo_flush<=1;fifo_write<=0;buffer_ready<=0;flush_count<=0;
   if(state==DATA_READ && !sector_end)switch_pending<=1;
   else begin state<=FLUSH;switch_pending<=0;end
  end
 end
end
endmodule
