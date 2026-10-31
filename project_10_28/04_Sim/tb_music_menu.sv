`timescale 1ns/1ps
module tb_music_menu;
reg clk=0;always #5 clk=~clk;
reg rst=1,toggle=0,playing=1,error=0,underrun=0,hs=1,vs=1,de=0,test_mode=0,chime=0;
reg [1:0] track=0;reg [2:0] total=4;reg [23:0] rgb=24'h234567;
wire ho,vo,dout;wire [23:0] out;
wl_music_menu #(.FONT_FILE("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/ascii_font.hex"),.CLK_HZ(500000))
 dut(clk,rst,toggle,track,total,playing,error,underrun,hs,vs,de,rgb,ho,vo,dout,out,test_mode,chime,1'b0,1'b0);
reg [7:0] font[0:2047];reg [23:0] expected[0:307199];
integer x,y,k,c,idx,count=0;reg monitor=0;reg [159:0] text_line;reg [7:0] ch;
always @(posedge clk)begin #1;
 if(monitor && dout)begin
  if(out!==expected[count])$fatal(1,"menu case=%d pixel=%d got=%h expected=%h",k,count,out,expected[count]);
  count=count+1;
 end
end
initial begin
 $readmemh("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/ascii_font.hex",font);
 repeat(5)@(negedge clk);rst=0;
 for(k=0;k<8;k=k+1)begin
  case(k)
   1:begin track=3;playing=0;end
   2:total=0;
   3:error=1;
   4:begin error=0;total=4;underrun=1;end
   6:begin error=1;test_mode=1;end
   7:begin test_mode=0;chime=1;end
  endcase
  toggle=~toggle;repeat(4)@(negedge clk);
  if(k==5)repeat(1500005)@(negedge clk);
  for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin
   idx=y*640+x;expected[idx]=rgb;
   if(k!=5 && x>=344 && x<608 && y>=72 && y<136)begin
    expected[idx]=24'h102430;
    if(x>=360 && x<520 && ((y>=80&&y<96)||(y>=112&&y<128)))begin
    if(y<104)text_line="MUSIC 0/0           ";
     else if(test_mode)text_line="TEST TONE 440 HZ    ";
     else if(chime)text_line="ARRIVAL CHIME       ";
     else if(error)text_line="SD AUDIO ERROR      ";
     else if(total==0)text_line="NO MUSIC            ";
     else if(underrun)text_line="AUDIO UNDERRUN      ";
     else if(playing)text_line="PLAYING             ";else text_line="PAUSED              ";
     c=(x-360)/8;ch=text_line[(19-c)*8 +:8];
     if(y<104 && c==6)ch=(total==0)?45:49+track;
     if(y<104 && c==8)ch=48+total;
     if(font[ch*16+y%16][7-x%8])expected[idx]=24'h70e8e0;
    end
   end
  end
  vs=1;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);vs=1;
  count=0;monitor=1;
  for(y=0;y<480;y=y+1)begin
   de=1;repeat(640)@(negedge clk);de=0;repeat(160)@(negedge clk);
  end
  repeat(5)@(negedge clk);monitor=0;
  if(count!=307200)$fatal(1,"menu pixel count");
 end
 $display("PASS music menu: numbered tracks, playing/paused/no music/error, timer and all pixels");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
