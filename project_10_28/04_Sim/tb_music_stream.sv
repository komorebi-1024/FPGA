`timescale 1ns/1ps
// Integrated audio path at real 100 MHz SD / 25 MHz pixel / 48 kHz PCM rates.
module tb_music_stream;
reg sdclk=0,vclk=0;always #5 sdclk=~sdclk;always #20 vclk=~vclk;
reg rst=1,sd_ready=0,next_track=0,play=1;
wire ar,av,ae,ir,iv,ie,sr,sv,se;
wire [31:0] aa,sa;reg [31:0] ia=9000;
wire [7:0] ad,idata,sdata;
wire fw,flush,full,empty,catalog,error,ready;
wire [31:0] fd,fq;wire [10:0] level;
wire [1:0] track;wire [2:0] tracks;
wire wr_rst,rd_rst,pop,pcm_valid,music_valid,underrun,chime,acr;
wire [23:0] left,right;wire [19:0] cts,n;
reg [1:0] ready_sync=0;
assign ir=sd_ready;
wl_music_reader reader(sdclk,rst,sd_ready,next_track,ar,aa,ad,av,ae,
 level,full,fw,fd,flush,track,tracks,catalog,error,ready);
wl_sd_arbiter arbiter(sdclk,rst,ir,ia,idata,iv,ie,ar,aa,ad,av,ae,sr,sa,sdata,sv,se);
wl_reset_sync write_reset(sdclk,rst || flush,wr_rst);
wl_reset_sync read_reset(vclk,rst || flush,rd_rst);
wl_audio_fifo fifo(sdclk,wr_rst,fw,fd,full,level,vclk,rd_rst,pop,fq,empty);
always @(posedge vclk or posedge rst)
 if(rst)ready_sync<=0;else ready_sync<={ready_sync[0],ready};
wl_pcm_audio pcm(.clk(vclk),.rst(rst),.test_mode(1'b0),.arrival_event(1'b0),
 .sample_valid(pcm_valid),.pcm_left(left),.pcm_right(right),
 .acr_valid(acr),.acr_cts(cts),.acr_n(n),.chime_active(chime),
 .music_enable(play && !rd_rst),.music_ready(ready_sync[1]),.music_empty(empty),
 .music_data(fq),.music_pop(pop),.music_sample_valid(music_valid),.music_underrun(underrun),.voice_enable(1'b0),.voice_ready(1'b0),.voice_empty(1'b1),.voice_data(32'd0),.voice_pop(),.voice_underrun());

reg [7:0] meta[0:511];
function [31:0] sample;
 input integer song;input integer frame_id;
 reg [15:0] l,r;
 begin l=100+song*1000+frame_id;r=-1-song*1000-frame_id;sample={r,l};end
endfunction
function [7:0] sector_byte;
 input [31:0] lba;input integer offset;
 integer song,frame_id;reg [31:0] word_data;
 begin
  if(lba==2057)sector_byte=meta[offset];
  else if(lba>=9000)sector_byte=8'ha5^offset[7:0]^lba[7:0];
  else begin
   song=lba/1000-3;frame_id=(lba-(3000+song*1000))*128+offset/4;
   word_data=sample(song,frame_id);sector_byte=word_data[(offset%4)*8 +:8];
  end
 end
endfunction
task put32;
 input integer offset;input [31:0] value;
 begin
  meta[offset]=value[7:0];meta[offset+1]=value[15:8];
  meta[offset+2]=value[23:16];meta[offset+3]=value[31:24];
 end
endtask

// One indivisible SD sector, a byte every 32 SD clocks, with CMD-style latency.
reg [2:0] model_state=0;
reg [5:0] byte_delay=0;
reg [9:0] byte_index=0;
reg [31:0] locked_lba=0;
reg model_valid=0,model_end=0;reg [7:0] model_data=0;
assign sv=model_valid;assign se=model_end;assign sdata=model_data;
integer transactions=0,image_bytes=0,image_sectors=0,image_offset=0;
always @(posedge sdclk)begin
 model_valid<=0;model_end<=0;
 if(rst)begin model_state<=0;byte_delay<=0;byte_index<=0;end
 else case(model_state)
  0:if(sr)begin
   transactions=transactions+1;locked_lba<=sa;byte_delay<=0;byte_index<=0;model_state<=1;
  end
  1:begin
   if(!sr || sa!=locked_lba)$fatal(1,"transport request/address changed within sector");
   if(byte_delay==31)begin
    byte_delay<=0;model_valid<=1;model_data<=sector_byte(locked_lba,byte_index);
    if(byte_index==511)model_state<=2;else byte_index<=byte_index+1'b1;
   end else byte_delay<=byte_delay+1'b1;
  end
  2:begin model_end<=1;model_state<=3;end
  3:model_state<=4;
  4:model_state<=0;
 endcase
 if(!rst)begin
  if(iv)begin
   if(idata!==(8'ha5^image_offset[7:0]^ia[7:0]))$fatal(1,"image consumed audio bytes");
   image_offset=image_offset+1;image_bytes=image_bytes+1;
  end
  if(ie)begin
   if(image_offset!=512)$fatal(1,"image byte count %d",image_offset);
   image_offset=0;image_sectors=image_sectors+1;ia<=ia+1'b1;
  end
  if(iv && av || ie && ae)$fatal(1,"sector routed to both owners");
 end
end

integer sample_count=0,expected_frame=0,expected_song=0,paused_count;
integer tick_count=0,first_fill=0;
reg [31:0] expected_pcm;
always @(posedge flush)begin #1;expected_frame=0;expected_song=track;end
always @(posedge vclk)begin
 #1;
 if(!rst)begin
  if(underrun)$fatal(1,"music underrun with simultaneous image traffic");
  if(error)$fatal(1,"music reader error");
  if(pcm_valid)tick_count=tick_count+1;
  if(music_valid)begin
   if(!play || rd_rst)$fatal(1,"consumed audio while paused/reset");
   if(sample_count==0)begin
    first_fill=level;if(first_fill<250)$fatal(1,"audio started before prefill %d",first_fill);
   end
   expected_pcm=sample(expected_song,expected_frame);
   if({right[23:8],left[23:8]}!==expected_pcm || left[7:0]!=0 || right[7:0]!=0)
    $fatal(1,"PCM order sample=%d song=%d frame=%d actual=%h/%h expected=%h",sample_count,expected_song,expected_frame,left,right,expected_pcm);
   expected_frame=expected_frame+1;
   if(expected_frame==(expected_song==0?130:129))expected_frame=0;
   sample_count=sample_count+1;
  end
 end
end

integer k,ticks_before;
initial begin
 for(k=0;k<512;k=k+1)meta[k]=0;
 meta[0]="W";meta[1]="L";meta[2]="P";meta[3]="C";meta[4]="M";meta[5]="0";meta[6]="0";meta[7]="1";
 meta[8]=2;meta[9]=2;meta[10]=16;put32(12,48000);
 put32(16,3000);put32(20,130);put32(32,4000);put32(36,129);
 repeat(8)@(negedge sdclk);rst=0;sd_ready=1;
 wait(sample_count>=1000);
 // Pause for 80 real HDMI sample times; PCM timing continues, FIFO head does not.
 @(negedge vclk);play=0;paused_count=sample_count;ticks_before=tick_count;
 wait(tick_count>=ticks_before+80);
 if(sample_count!=paused_count)$fatal(1,"pause popped samples");
 @(negedge vclk);play=1;
 wait(sample_count>=1120);
 // Request a different song halfway through an audio sector, not at a boundary.
 wait(model_state==1 && locked_lba<9000 && locked_lba!=2057 && byte_index>40 && byte_index<400);
 @(negedge sdclk);next_track=1;@(negedge sdclk);next_track=0;
 wait(flush);wait(!flush);wait(!rd_rst && ready_sync[1]);
 wait(sample_count>=1620);
 if(track!=1 || tracks!=2 || image_sectors==0 || first_fill==0)$fatal(1,"integration coverage");
 $display("PASS integrated music stream: %0d PCM frames, %0d image sectors, precise EOF/pause/resume/switch, no underrun",sample_count,image_sectors);
 $finish;
end
initial begin #100000000;$fatal(1,"integrated stream timeout samples=%d sectors=%d",sample_count,transactions);end
endmodule
