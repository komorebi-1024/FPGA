`timescale 1ns/1ps
module tb_image_settings_overlay;
reg clk=0;always #5 clk=~clk;
reg rst=1,hs=1,vs=1,de=0;reg [23:0] rgb=24'h123456;
reg [8:0] cfg_input=9'b0_00_010_010;
wire ho,vo,dout;wire [23:0] out;
wl_image_settings_overlay dut(clk,rst,hs,vs,de,rgb,cfg_input,ho,vo,dout,out);
function [34:0] reference_glyph;
 input [7:0] c;
 begin
  case(c)
   "A":reference_glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "B":reference_glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
   "C":reference_glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "D":reference_glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
   "E":reference_glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "F":reference_glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
   "G":reference_glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
   "H":reference_glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "I":reference_glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
   "J":reference_glyph={5'b00111,5'b00010,5'b00010,5'b00010,5'b10010,5'b10010,5'b01100};
   "K":reference_glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
   "L":reference_glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
   "M":reference_glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
   "N":reference_glyph={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
   "O":reference_glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "P":reference_glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
   "R":reference_glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
   "S":reference_glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
   "T":reference_glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
   "U":reference_glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "X":reference_glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
   "0":reference_glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
   "1":reference_glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "2":reference_glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
   "3":reference_glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
   "4":reference_glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
   "5":reference_glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
   "6":reference_glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
   "7":reference_glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
   "8":reference_glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
   "9":reference_glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
   "+":reference_glyph={5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000};
   "-":reference_glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
   "%":reference_glyph={5'b11001,5'b11010,5'b00010,5'b00100,5'b01000,5'b01011,5'b10011};
   ":":reference_glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
   ">":reference_glyph={5'b10000,5'b01000,5'b00100,5'b00010,5'b00100,5'b01000,5'b10000};
   default:reference_glyph=0;
  endcase
 end
endfunction
// Independent screen-space reference; strings and integer level arithmetic do
// not use the DUT's packed-string extraction or raster counters.
function automatic [23:0] reference_pixel;
 input integer px,py;
 input [8:0] cfg;
 input [23:0] background;
 integer row,sx,sy,col,b,c,selected_top;reg ink,value_region;
 reg [34:0] bits;reg [7:0] character;reg [23:0] result;
 string text;
 begin
  result=background;ink=0;value_region=0;text="";sx=0;sy=0;
  if(cfg[8] && px>=140 && px<500 && py>=144 && py<320)begin
   result=24'h102430;
   selected_top=182+24*cfg[7:6];
   if(px>=152 && px<488 && py>=selected_top && py<selected_top+24)result=24'h203c48;
   if(px==140 || px==499 || py==144 || py==319 || py==178)result=24'h38505c;
   if(px>=152 && px<488 && py>=selected_top && py<selected_top+24 &&
      (px==152 || px==487 || py==selected_top || py==selected_top+23))result=24'h50d0d0;
   if(py>=156 && py<170 && px>=160 && px<328)begin
    text="IMAGE SETTINGS";sx=(px-160)/2;sy=(py-156)/2;
   end else if(py>=188 && py<274 && (py-188)%24<14)begin
    row=(py-188)/24;sy=((py-188)%24)/2;
    if(px>=174 && px<318)begin
     sx=(px-174)/2;
     case(row)0:text="BRIGHTNESS";1:text="CONTRAST";2:text="DEFAULT";3:text="EXIT";endcase
    end else if(px>=382 && px<430 && row<2)begin
     sx=(px-382)/2;value_region=1;
     if(row==0)begin
      b=cfg[5:3];if(b>4)b=2;b=(b-2)*32;
      if(b==0)text="  0 ";else if(b<0)text=$sformatf("%0d ",b);else text=$sformatf("+%0d ",b);
     end else begin
      c=cfg[2:0];if(c>4)c=2;c=50+25*c;text=$sformatf("%3d%%",c);
     end
    end
   end else if(py>=292 && py<299 && px>=158 && px<272)begin
    text="K2:ADJUST K3:SELECT";sx=px-158;sy=py-292;
   end else if(py>=308 && py<315 && px>=158 && px<230)begin
    text="HOLD K3:EXIT";sx=px-158;sy=py-308;
   end
   if(text.len()!=0)begin
    col=sx/6;character=(col<text.len())?text[col]:8'd32;
    bits=reference_glyph(character);
    ink=sx%6<5 && bits[34-sy*5-sx%6];
   end
   if(ink)result=value_region?24'hffe8a0:24'hb8f4ee;
  end
  reference_pixel=result;
 end
endfunction
reg checking=0,capture=0;integer px=0,py=0,pixels=0,frames=0,fd;
reg [8:0] expected_config;reg [23:0] expected;
reg expected_hs,expected_vs,expected_de;
always @(posedge clk)begin
 if(!rst)begin
  expected_hs=hs;expected_vs=vs;expected_de=de;
  expected=checking && de ? reference_pixel(px,py,expected_config,rgb):rgb;
  #1;
  if(ho!==expected_hs || vo!==expected_vs || dout!==expected_de)$fatal(1,"sync/DE one-stage delay");
  if((checking || !de) && out!==expected)$fatal(1,"menu frame=%d x=%d y=%d cfg=%h got=%h expected=%h",frames,px,py,expected_config,out,expected);
  if(checking && de)begin
   if(capture)$fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);
   pixels=pixels+1;
   if(px==639)begin px=0;py=py+1;end else px=px+1;
  end
 end
end

task frame;
 input [8:0] cfg;
 input integer save_preview,change_midframe;
 integer x,y;
 begin
  @(negedge clk);checking=0;de=0;cfg_input=cfg;vs=1;repeat(3)@(negedge clk);
  vs=0;repeat(3)@(negedge clk);vs=1;repeat(3)@(negedge clk);
  expected_config=cfg;px=0;py=0;pixels=0;capture=save_preview;
  if(capture)begin fd=$fopen("image_settings_preview.rgb","wb");if(fd==0)$fatal(1,"preview open");end
  checking=1;
  for(y=0;y<480;y=y+1)begin
   de=1;
   for(x=0;x<640;x=x+1)begin
    rgb={x[7:0],y[7:0],(x[7:0]^y[7:0])};hs=x>=320;
    if(change_midframe && x==0 && y==200)cfg_input=9'b1_11_100_000;
    @(negedge clk);
   end
   de=0;rgb=24'h654321;repeat(3)@(negedge clk);
  end
  checking=0;capture=0;if(save_preview)$fclose(fd);
  if(pixels!=307200)$fatal(1,"pixel count %d",pixels);
  frames=frames+1;
 end
endtask
integer k;reg [2:0] b,c;reg [1:0] selection;
initial begin
 repeat(5)@(negedge clk);rst=0;
 // Closing is exact passthrough, including arbitrary blanking RGB.
 frame(9'b0_00_010_010,0,0);
 // Every numeric brightness and contrast label, and every menu item selection.
 for(k=0;k<5;k=k+1)begin
  b=k;c=4-k;selection=k%4;frame({1'b1,selection,b,c},0,0);
 end
 frame(9'b1_00_010_010,1,1);
 // The source changed mid-frame above; the completed frame still showed old
 // settings. A new VS edge applies all fields together on the next frame.
 frame(9'b1_11_100_000,0,0);
 frame(9'b1_01_111_111,0,0);
 frame(9'b0_11_100_000,0,0);
 $display("PASS image settings overlay: all labels/levels/selections, frame-atomic cfg_input, outside/closed/blank exact passthrough and sync; %d full frames",frames);$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
