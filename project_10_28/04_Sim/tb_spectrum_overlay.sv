`timescale 1ns/1ps
module tb_spectrum_overlay;
reg clk=0;always #5 clk=~clk;
reg rst=1,en=1,hs=0,vs=0,de=0;reg [23:0] rgb=0;
reg [63:0] levels=64'hf0c0a08060402010;
wire ho,vo,dout;wire [23:0] out;
wl_spectrum_overlay dut(clk,rst,en,levels,hs,vs,de,rgb,ho,vo,dout,out);
reg [23:0] photo[0:307199];
integer peak_ref[0:7],hold_ref[0:7],height_ref[0:7];
integer x,y,b,f,fd;
reg [23:0] want;
function [39:0] font_columns;
 input [7:0] c;
 begin
  case(c)
   "S":font_columns=40'h4649494931;
   "P":font_columns=40'h7f09090906;
   "E":font_columns=40'h7f49494941;
   "C":font_columns=40'h3e41414141;
   "T":font_columns=40'h01017f0101;
   "R":font_columns=40'h7f09192946;
   "U":font_columns=40'h3f4040403f;
   "M":font_columns=40'h7f020c027f;
   "D":font_columns=40'h7f4141413e;
   "F":font_columns=40'h7f09090901;
   "L":font_columns=40'h7f40404040;
   "O":font_columns=40'h3e4141413e;
   "W":font_columns=40'h7f2018207f;
   "H":font_columns=40'h7f0808087f;
   "I":font_columns=40'h41417f4141;
   "G":font_columns=40'h3e41494979;
   "1":font_columns=40'h00427f4000;
   "2":font_columns=40'h4261514946;
   "3":font_columns=40'h4149494936;
   "4":font_columns=40'h1814127f10;
   "5":font_columns=40'h4f49494931;
   "6":font_columns=40'h3e49494930;
   "7":font_columns=40'h0171090503;
   "8":font_columns=40'h3649494936;
   default:font_columns=0;
  endcase
 end
endfunction
function text_on;
 input integer px,py;
 integer cx,cy,column,offset;
 reg [7:0] c,word_column;
 reg [127:0] line;
 reg [31:0] direction;
 reg [39:0] fontword;
 begin
  cx=6;cy=0;c=0;line="SPECTRUM  DFT256";direction="    ";
  if(py>=280 && py<287 && px>=330 && px<426)begin
   offset=px-330;column=offset/6;cx=offset%6;cy=py-280;c=line[(15-column)*8 +:8];
  end else if(py>=280 && py<287 && px>=576 && px<594)begin
   offset=px-576;cx=offset%6;cy=py-280;
   case(offset/6)0:c="R";1:c="E";2:c="L";endcase
  end else if(py>=300 && py<307 && ((px>=330&&px<348)||(px>=568&&px<592)))begin
   if(px<348)begin offset=px-330;direction="LOW ";end
   else begin offset=px-568;direction="HIGH";end
   cx=offset%6;cy=py-300;c=direction[(3-offset/6)*8 +:8];
  end else if(py>=382 && py<389 && px>=345 && px<574)begin
   offset=px-345;cx=offset%32;cy=py-382;c=49+offset/32;
  end
  fontword=font_columns(c);word_column=0;
  if(cx<5)word_column=fontword[(4-cx)*8 +:8];
  text_on=cx<5 && word_column[cy];
 end
endfunction
function [23:0] pixel_reference;
 input integer px,py;
 input [23:0] original;
 integer band,top,peak_top;
 reg panel,column;
 begin
  pixel_reference=original;
  panel=en && px>=320 && px<608 && py>=272 && py<392;
  column=px>=336 && px<592 && (px-336)%32<24;
  band=(px-336)/32;top=376;peak_top=376;
  if(band>=0 && band<8)begin top=376-height_ref[band];peak_top=376-peak_ref[band];end
  if(panel)begin
   if(text_on(px,py))pixel_reference=24'hb8f4ee;
   else if(column && peak_ref[band]!=0 && py==peak_top)pixel_reference=24'hffe8a0;
   else if(column && py>=top && py<376)begin
    if(py<334)pixel_reference=24'hffcc50;
    else if(py<355)pixel_reference=24'h50e0c0;
    else pixel_reference=24'h30a8e8;
   end else if((px>=330 && px<598 && (py==312||py==344||py==376)) ||
               px==320 || px==607 || py==272 || py==391 || py==292)pixel_reference=24'h38505c;
   else pixel_reference={2'b0,original[23:18],2'b0,original[15:10],2'b0,original[7:2]};
  end
 end
endfunction
task frame_start;
 integer i,h;
 begin
  de=0;vs=1;repeat(2)@(negedge clk);vs=0;@(negedge clk);
  for(i=0;i<8;i=i+1)begin
   height_ref[i]=en?(levels[i*8 +:8]>>2):0;
   h=height_ref[i];
   if(!en)begin peak_ref[i]=0;hold_ref[i]=0;end
   else if(h>=peak_ref[i] && h!=0)begin peak_ref[i]=h;hold_ref[i]=30;end
   else if(hold_ref[i]!=0)hold_ref[i]=hold_ref[i]-1;
   else if(peak_ref[i]!=0)peak_ref[i]=peak_ref[i]-1;
   if(dut.peak_height[i]!==peak_ref[i] || dut.peak_hold[i]!==hold_ref[i])
    $fatal(1,"peak state band=%d got=%d/%d expected=%d/%d",i,dut.peak_height[i],dut.peak_hold[i],peak_ref[i],hold_ref[i]);
  end
 end
endtask
task scan_frame;
 input integer preview;
 begin
  frame_start();
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    de=1;hs=x[0];rgb=photo[y*640+x];want=pixel_reference(x,y,rgb);
    @(posedge clk);#1;
    if(out!==want || !dout || ho!==hs || vo!==vs)
     $fatal(1,"pixel/timing x=%d y=%d actual=%h expected=%h",x,y,out,want);
    if(preview)$fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);
    @(negedge clk);
    // All eight level changes during active video must wait until next frame.
    if(x==400 && y==300)levels=0;
   end
   de=0;repeat(3)@(negedge clk);
  end
 end
endtask
initial begin
 $readmemh("input_0.hex",photo);
 for(b=0;b<8;b=b+1)begin peak_ref[b]=0;hold_ref[b]=0;height_ref[b]=0;end
 repeat(4)@(negedge clk);rst=0;
 fd=$fopen("spectrum_overlay_preview.rgb","wb");scan_frame(1);$fclose(fd);
 // Zero input removes bars, but all eight independent peaks remain held.
 scan_frame(0);
 for(f=0;f<29;f=f+1)frame_start();
 for(b=0;b<8;b=b+1)if(dut.peak_hold[b]!=0)$fatal(1,"hold duration");
 frame_start();
 repeat(64)frame_start();
 for(b=0;b<8;b=b+1)if(dut.peak_height[b]!=0)$fatal(1,"silence peak did not reach zero");
 scan_frame(0);
 en=0;@(negedge clk);
 for(b=0;b<8;b=b+1)begin peak_ref[b]=0;hold_ref[b]=0;end
 scan_frame(0);
 // Disable clears peaks immediately and bypasses all title/grid pixels.
 en=1;levels=64'hffffffffffffffff;frame_start();
 en=0;@(negedge clk);
 for(b=0;b<8;b=b+1)if(dut.peak_height[b]!=0 || dut.peak_hold[b]!=0)$fatal(1,"disable clear");
 rst=1;@(negedge clk);
 if(out!=0 || dout || ho || vo)$fatal(1,"reset outputs");
 for(b=0;b<8;b=b+1)if(dut.peak_height[b]!=0)$fatal(1,"reset peak");
 rst=0;de=0;@(posedge clk);#1;if(dout || out!=0)$fatal(1,"blanking");
 $display("PASS spectrum overlay: eight bands/text/all pixels, frame latch, peak hold/release, silence/bypass/reset and sync");$finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
