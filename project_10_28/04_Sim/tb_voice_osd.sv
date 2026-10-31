`timescale 1ns/1ps
module tb_voice_osd;
reg clk=0;always #5 clk=~clk;
reg rst=1,hs=1,vs=1,de=0;reg [1:0] station=0,phase=0;reg [5:0] reveal=0;
wire ho,vo,dout;wire [23:0] out;
localparam [23:0] RGB=24'h80c040;
wl_osd #(.CAPTION_FILE("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/voice_captions.hex"),
 .FONT_FILE("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/ascii_font.hex"),.VOICE_CAPTIONS(1)) dut(
 clk,rst,hs,vs,de,RGB,station,1'b1,1'b0,4'd5,ho,vo,dout,out,phase,reveal);
reg [31:0] rom[0:8191];reg [23:0] expected[0:307199];
integer s,p,r,x,y,base,row,word_addr,count=0;reg monitor=0,ink,check_pixel;reg [23:0] want;
always @(posedge clk)begin #1;
 if(monitor && dout)begin
  // The other OSD tests verify the independent status/route panel.
  if((count/640<40 || count/640>=56) && !(count/640>=400 && count/640<416))begin
   if(out!==expected[count])$fatal(1,"voice OSD s=%d phase=%d reveal=%d pixel=%d got=%h expected=%h",s,p,r,count,out,expected[count]);
  end
  count=count+1;
 end
end
initial begin
 $readmemh("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/voice_captions.hex",rom);
 for(s=0;s<4;s=s+1)for(p=0;p<3;p=p+1)for(r=0;r<2;r=r+1)begin
  rst=1;de=0;vs=1;monitor=0;repeat(4)@(negedge clk);rst=0;
  station=s;phase=p;reveal=r?31:0;
  for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin
   want=(y<64 || y>=416)?24'h203010:RGB;ink=0;base=0;row=0;
   if(y<24)begin base=0;row=y;ink=1;end
   else if(y>=416 && y<440)begin base=480+s*480;row=y-416;ink=1;end
   else if(y>=448 && y<472)begin base=2400+(s*3+p)*480;row=y-448;ink=(x<16+20*reveal);end
   word_addr=base+row*20+x/32;
   if(ink && rom[word_addr][31-x%32])want=24'hffffff;
   expected[y*640+x]=want;
  end
  vs=0;repeat(3)@(negedge clk);vs=1;count=0;monitor=1;
  for(y=0;y<480;y=y+1)begin de=1;repeat(640)@(negedge clk);de=0;repeat(3)@(negedge clk);end
  repeat(5)@(negedge clk);monitor=0;
  if(count!=307200)$fatal(1,"voice OSD count");
 end
 $display("PASS voice OSD: all four stations/three phrases, hidden/full reveal, shared title, unchanged sync pipeline");$finish;
end
initial begin #100000000;$fatal(1,"voice OSD timeout");end
endmodule
