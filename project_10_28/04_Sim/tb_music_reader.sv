`timescale 1ns/1ps
module tb_music_reader;
reg clk=0;always #5 clk=~clk;
reg rst=1,ready=0,next_track=0,valid=0,finish=0,full=0;
reg [7:0] data=0;reg [10:0] level=0;
wire req,push,flush,cat,error,buffer_ready;wire [31:0] addr,pcm;
wire [1:0] track;wire [2:0] tracks;
wl_music_reader dut(clk,rst,ready,next_track,req,addr,data,valid,finish,
 level,full,push,pcm,flush,track,tracks,cat,error,buffer_ready);
reg [7:0] meta[0:511];
integer n,j,expected_frame=0,writes=0,flush_clocks=0,cycle;
integer start_address,frame_number;reg [31:0] value,expected;
reg checking=1;
function [31:0] sample;
 input integer song;input integer frame_id;
 begin sample=((song+1)<<28)+frame_id;end
endfunction
always @(posedge clk)begin
 if(rst || flush)begin level<=0;expected_frame=0;end
 else if(push)begin
  level<=level+1'b1;
  expected=sample(track,expected_frame);
  if(checking && pcm!==expected)$fatal(1,"PCM order/byte order actual=%h expected=%h frame=%d song=%d",pcm,expected,expected_frame,track);
  expected_frame=expected_frame+1;
  if(expected_frame==(track==0?130:129))expected_frame=0;
  writes=writes+1;
 end
 if(flush)flush_clocks=flush_clocks+1;else flush_clocks=0;
end
task put32;
 input integer offset;input [31:0] v;
 begin
  meta[offset]=v[7:0];meta[offset+1]=v[15:8];meta[offset+2]=v[23:16];meta[offset+3]=v[31:24];
 end
endtask
task metadata;
 begin
  for(n=0;n<512;n=n+1)meta[n]=0;
  meta[0]="W";meta[1]="L";meta[2]="P";meta[3]="C";meta[4]="M";meta[5]="0";meta[6]="0";meta[7]="1";
  meta[8]=2;meta[9]=2;meta[10]=16;put32(12,48000);
  put32(16,3000);put32(20,130);put32(32,4000);put32(36,129);
 end
endtask
task reset_reader;
 begin
  rst=1;ready=0;valid=0;finish=0;next_track=0;full=0;
  repeat(4)@(negedge clk);rst=0;ready=1;
 end
endtask
task sector;
 input integer switch_byte;
 integer b,tag,fid;reg [31:0] word_data,locked_addr;
 begin
  while(!req)@(negedge clk);
  locked_addr=addr;
  for(b=0;b<512;b=b+1)begin
   if(addr!==locked_addr || !req)$fatal(1,"request changed before end");
   if(locked_addr==2057)data=meta[b];
   else begin
    tag=locked_addr/1000-3;
    fid=(locked_addr-(3000+tag*1000))*128+b/4;
    word_data=sample(tag,fid);data=word_data[(b%4)*8 +:8];
   end
   valid=1;next_track=(b==switch_byte);
   @(negedge clk);valid=0;next_track=0;@(negedge clk);
  end
  finish=1;@(negedge clk);finish=0;
  repeat(3)@(negedge clk);
 end
endtask
initial begin
 metadata();reset_reader();sector(-1);
 while(!cat)@(negedge clk);
 if(error || tracks!=2)$fatal(1,"catalog rejected");
 // 130 frames: first sector 128, next sector exactly 2, then seamless loop.
 sector(-1);sector(-1);sector(-1);
 repeat(5)@(negedge clk);
 if(writes!=258 || !buffer_ready)$fatal(1,"partial tail/prefill writes=%d ready=%b",writes,buffer_ready);
 // A track change in flight must drain all old bytes while keeping request.
 sector(17);
 if(!flush || track!=1)$fatal(1,"switch flush/track");
 while(flush)@(negedge clk);
 if(flush_clocks<64 || buffer_ready)$fatal(1,"switch ready/flush duration");
 if(addr!=4000 || level!=0)$fatal(1,"new song position/FIFO reset");
 sector(-1);sector(-1);sector(-1);
 repeat(5)@(negedge clk);
 if(!buffer_ready || expected_frame!=128)$fatal(1,"song 1 tail loop");
 // Hold off all new reads when FIFO is above the reservation threshold.
 // Complete a possibly scheduled sector first.
 while(level<=768)sector(-1);
 full=1;repeat(5)@(negedge clk);
 if(req)$fatal(1,"request while full");full=0;
 // Validate all four descriptors and wrap track 3 back to track 0.
 metadata();meta[8]=4;put32(48,5000);put32(52,129);put32(64,6000);put32(68,129);
 reset_reader();sector(-1);
 while(!cat)@(negedge clk);
 if(error || tracks!=4)$fatal(1,"four-track catalog");
 for(cycle=0;cycle<4;cycle=cycle+1)begin
  while(flush)@(negedge clk);
  sector(17);
  if(track!=((cycle+1)%4) || !flush)$fatal(1,"track wrap selection");
  // Inputs during flush are deliberately ignored, rather than queued.
  next_track=1;@(negedge clk);next_track=0;
 end
 // An invalid catalog never reads audio and does not hold an SD request.
 metadata();put32(20,32'hffffffff);reset_reader();sector(-1);
 repeat(20)@(negedge clk);
 if(!cat || !error || tracks!=0 || req || !flush)$fatal(1,"overflow catalog accepted");
 metadata();put32(16,262143);put32(20,129);reset_reader();sector(-1);
 repeat(20)@(negedge clk);
 if(!error || req)$fatal(1,"out of disk accepted");
 metadata();meta[8]=0;reset_reader();sector(-1);
 repeat(20)@(negedge clk);
 if(!cat || error || tracks!=0 || req || !flush)$fatal(1,"zero-track catalog");
 metadata();meta[0]=0;reset_reader();sector(-1);
 repeat(20)@(negedge clk);
 if(!cat || !error || req)$fatal(1,"old-image missing audio catalog");
 $display("PASS music reader: stereo byte order, partial EOF, looping, prefill, in-flight switch, full, metadata bounds and no audio");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
