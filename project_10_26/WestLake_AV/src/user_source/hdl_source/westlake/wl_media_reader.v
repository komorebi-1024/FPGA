// Deterministic WestLake media catalog at reserved FAT32 sector 2056.
// All BMP headers are validated before the catalog is declared ready.
// Does not walk FAT chains: use the generated disk image, not fragmented copies.
module wl_media_reader #(
    parameter integer WIDTH=640, HEIGHT=480,
    parameter [31:0] CATALOG_LBA=2056,
    parameter integer TIMEOUT_CYCLES=200000000,
    parameter integer NUM_STATIONS=4,
    parameter integer PROMOS_PER_INTERVAL=5,
    parameter integer TOTAL_IMAGES=24,
    parameter [31:0] DISK_SECTORS=262144
)(
    input wire clk,input wire rst,input wire sd_ready,
    output reg sector_read,output reg [31:0] sector_addr,
    input wire [7:0] sector_data,input wire sector_valid,input wire sector_end,
    output reg catalog_ready,output reg error,output reg [3:0] status,
    input wire load_start,input wire [4:0] load_id,
    output wire idle,output reg load_done,
    output reg write_req,input wire write_ack,
    output reg pixel_valid,output reg [23:0] pixel_rgb
);
localparam [31:0] FILE_BYTES=54+WIDTH*HEIGHT*3;
localparam [31:0] FILE_SECTORS=(FILE_BYTES+511)/512;
localparam [63:0] CATALOG_MAGIC=64'h3230303056414c57; // "WLAV0002"
localparam WAIT_SD=0,META_REQ=1,META_READ=2,META_CHECK=3,HDR_REQ=4,
 HDR_READ=5,HDR_CHECK=6,READY=7,WRITE_WAIT=8,WRITE_RELEASE=9,
 DATA_REQ=10,DATA_READ=11,FAULT=12;
reg [3:0] state;
reg [8:0] byte_in_sector;
wire [4:0] catalog_index=(byte_in_sector-9'd16)>>4;
reg [63:0] magic;
reg [7:0] image_count,meta_depth,num_stations,promos_per_interval;
reg [15:0] meta_width,meta_height;
reg [31:0] lba[0:23];
reg [31:0] lengths[0:23];
reg [4:0] current_id;
reg [31:0] cur_lba,cur_len;
reg catalog_bad;
reg header_good;
reg checking_catalog;
reg [15:0] bmp_magic,planes,bits;
reg [31:0] file_size,pixel_offset,width,height,compression;
reg [31:0] stream_pos,watchdog;
reg [1:0] component;
reg [7:0] blue,green;
integer i;
wire good_header=(bmp_magic==16'h4d42)&&(file_size==FILE_BYTES)&&
 (pixel_offset==54)&&(width==WIDTH)&&(height==HEIGHT)&&
 (planes==1)&&(bits==24)&&(compression==0);
assign idle=(state==READY);
wire header_ok=(magic==CATALOG_MAGIC)&&(image_count==TOTAL_IMAGES)&&(meta_depth==24)&&
 (meta_width==WIDTH)&&(meta_height==HEIGHT)&&
 (num_stations==NUM_STATIONS)&&(promos_per_interval==PROMOS_PER_INTERVAL);
always @(posedge clk or posedge rst) begin
 if(rst) begin
  state<=WAIT_SD;sector_read<=0;sector_addr<=0;catalog_ready<=0;error<=0;status<=0;
  byte_in_sector<=0;magic<=0;image_count<=0;meta_depth<=0;meta_width<=0;meta_height<=0;
  num_stations<=0;promos_per_interval<=0;
  current_id<=0;cur_lba<=0;cur_len<=0;catalog_bad<=0;header_good<=0;checking_catalog<=1;bmp_magic<=0;planes<=0;bits<=0;
  file_size<=0;pixel_offset<=0;width<=0;height<=0;compression<=0;
  stream_pos<=0;watchdog<=0;component<=0;blue<=0;green<=0;
  write_req<=0;load_done<=0;pixel_valid<=0;pixel_rgb<=0;
  for(i=0;i<TOTAL_IMAGES;i=i+1)begin lba[i]<=0;lengths[i]<=0;end
 end else begin
  load_done<=0;pixel_valid<=0;
  if(state==WAIT_SD || state==READY || state==FAULT || sector_valid || sector_end)
   watchdog<=0;
  else watchdog<=watchdog+1'b1;
  case(state)
   WAIT_SD: if(sd_ready)begin state<=META_REQ;status<=1;end
   META_REQ:begin byte_in_sector<=0;cur_lba<=0;cur_len<=0;catalog_bad<=0;sector_addr<=CATALOG_LBA;sector_read<=1;state<=META_READ;end
   META_READ:begin
    if(sector_valid)begin
     byte_in_sector<=byte_in_sector+1'b1;
     if(byte_in_sector<8) magic[byte_in_sector*8 +: 8]<=sector_data;
     case(byte_in_sector)
      8:image_count<=sector_data;9:meta_depth<=sector_data;
      10:meta_width[7:0]<=sector_data;11:meta_width[15:8]<=sector_data;
      12:meta_height[7:0]<=sector_data;13:meta_height[15:8]<=sector_data;
      14:num_stations<=sector_data;15:promos_per_interval<=sector_data;
     endcase
     if(byte_in_sector>=16 && byte_in_sector<16+TOTAL_IMAGES*16)begin
      if(byte_in_sector[3:0]<4)begin
       lba[catalog_index][byte_in_sector[1:0]*8 +:8]<=sector_data;
       cur_lba[byte_in_sector[1:0]*8 +:8]<=sector_data;
      end
      if(byte_in_sector[3:0]>=4 && byte_in_sector[3:0]<8)begin
       lengths[catalog_index][byte_in_sector[1:0]*8 +:8]<=sector_data;
       cur_len[byte_in_sector[1:0]*8 +:8]<=sector_data;
      end
      if(byte_in_sector[3:0]==8 && (cur_len!=FILE_BYTES || cur_lba<=CATALOG_LBA || cur_lba>DISK_SECTORS-FILE_SECTORS))
       catalog_bad<=1;
     end
    end
    if(sector_end)begin sector_read<=0;state<=META_CHECK;end
   end
   META_CHECK:begin
    if(!header_ok || catalog_bad)begin error<=1;status<=4'he;state<=FAULT;end
    else begin current_id<=0;checking_catalog<=1;state<=HDR_REQ;status<=2;end
   end
   HDR_REQ:begin
    byte_in_sector<=0;bmp_magic<=0;file_size<=0;pixel_offset<=0;
    width<=0;height<=0;planes<=0;bits<=0;compression<=0;
    sector_addr<=lba[current_id];sector_read<=1;state<=HDR_READ;
   end
   HDR_READ:begin
    if(sector_valid)begin
     byte_in_sector<=byte_in_sector+1'b1;
     case(byte_in_sector)
      0:bmp_magic[7:0]<=sector_data;1:bmp_magic[15:8]<=sector_data;
      2:file_size[7:0]<=sector_data;3:file_size[15:8]<=sector_data;4:file_size[23:16]<=sector_data;5:file_size[31:24]<=sector_data;
      10:pixel_offset[7:0]<=sector_data;11:pixel_offset[15:8]<=sector_data;12:pixel_offset[23:16]<=sector_data;13:pixel_offset[31:24]<=sector_data;
      18:width[7:0]<=sector_data;19:width[15:8]<=sector_data;20:width[23:16]<=sector_data;21:width[31:24]<=sector_data;
      22:height[7:0]<=sector_data;23:height[15:8]<=sector_data;24:height[23:16]<=sector_data;25:height[31:24]<=sector_data;
      26:planes[7:0]<=sector_data;27:planes[15:8]<=sector_data;
      28:bits[7:0]<=sector_data;29:bits[15:8]<=sector_data;
      30:compression[7:0]<=sector_data;31:compression[15:8]<=sector_data;32:compression[23:16]<=sector_data;33:compression[31:24]<=sector_data;
     endcase
    end
    if(sector_end)begin sector_read<=0;header_good<=good_header;state<=HDR_CHECK;end
   end
   HDR_CHECK:begin
    if(!header_good)begin error<=1;status<=4'hd;state<=FAULT;end
    else if(checking_catalog)begin
     if(current_id==TOTAL_IMAGES-1)begin catalog_ready<=1;state<=READY;status<=4;end
     else begin current_id<=current_id+1'b1;state<=HDR_REQ;end
    end else begin write_req<=1;state<=WRITE_WAIT;end
   end
   READY:if(load_start)begin current_id<=load_id;checking_catalog<=0;state<=HDR_REQ;status<=3;end
   WRITE_WAIT:if(write_ack)begin write_req<=0;state<=WRITE_RELEASE;end
   WRITE_RELEASE:if(!write_ack)begin sector_addr<=lba[current_id];stream_pos<=0;component<=0;state<=DATA_REQ;end
   DATA_REQ:begin sector_read<=1;state<=DATA_READ;end
   DATA_READ:begin
    if(sector_valid)begin
     stream_pos<=stream_pos+1'b1;
     if(stream_pos>=54 && stream_pos<FILE_BYTES)begin
      case(component)
       0:begin blue<=sector_data;component<=1;end
       1:begin green<=sector_data;component<=2;end
       2:begin pixel_rgb<={sector_data,green,blue};pixel_valid<=1;component<=0;end
      endcase
     end
    end
    if(sector_end)begin
     sector_read<=0;
     if(stream_pos>=FILE_BYTES)begin load_done<=1;state<=READY;status<=4;end
     else begin sector_addr<=sector_addr+1'b1;state<=DATA_REQ;end
    end
   end
   FAULT:begin sector_read<=0;write_req<=0;end
   default:begin error<=1;status<=4'hf;state<=FAULT;end
  endcase
  if(watchdog>=TIMEOUT_CYCLES-1 && state!=FAULT && state!=READY && state!=WAIT_SD)begin
   state<=FAULT;error<=1;status<=4'hc;sector_read<=0;write_req<=0;
  end
 end
end
endmodule
