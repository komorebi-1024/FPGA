// Single pixel-clock stage; no new RAM or DSP. Eight real DFT frequency bands.
// Header/LOW-HIGH/band indices explain the relative display without pretending
// that unequal-width bands have a calibrated or linear frequency scale.
// Spectrum and peaks are latched at frame boundaries. Peak hold is 30 frames
// (~0.5 seconds at 60 Hz), then releases one display pixel per frame.
module wl_spectrum_overlay(
 input wire clk,input wire rst,input wire enable,input wire [63:0] levels,
 input wire hs_in,input wire vs_in,input wire de_in,input wire [23:0] rgb_in,
 output reg hs_out,output reg vs_out,output reg de_out,output reg [23:0] rgb_out
);
reg [9:0] x,y;
reg vs_previous;
reg [63:0] frame_levels;
reg [5:0] peak_height[0:7];
reg [4:0] peak_hold[0:7];
integer band;
wire panel=enable && x>=320 && x<608 && y>=272 && y<392;
wire column=x>=336 && x<592 && (x-336)%32<24;
wire [2:0] column_band=(x-336)>>5;
wire [5:0] height=frame_levels[column_band*8 +: 8]>>2;
wire bar=column && y>=376-height && y<376;
wire peak=column && peak_height[column_band]!=0 && y==376-peak_height[column_band];
wire grid=x>=330 && x<598 && (y==312 || y==344 || y==376);
wire border=x==320 || x==607 || y==272 || y==391 || y==292;

// Compact 5x7 uppercase font. Constants synthesize to combinational LUTs.
function [34:0] glyph;
 input [7:0] c;
 begin
  case(c)
   "S":glyph=35'b01111100001000001110000010000111110;
   "P":glyph=35'b11110100011000111110100001000010000;
   "E":glyph=35'b11111100001000011110100001000011111;
   "C":glyph=35'b01111100001000010000100001000001111;
   "T":glyph=35'b11111001000010000100001000010000100;
   "R":glyph=35'b11110100011000111110101001001010001;
   "U":glyph=35'b10001100011000110001100011000101110;
   "M":glyph=35'b10001110111010110101100011000110001;
   "D":glyph=35'b11110100011000110001100011000111110;
   "F":glyph=35'b11111100001000011110100001000010000;
   "L":glyph=35'b10000100001000010000100001000011111;
   "O":glyph=35'b01110100011000110001100011000101110;
   "W":glyph=35'b10001100011000110101101011101110001;
   "H":glyph=35'b10001100011000111111100011000110001;
   "I":glyph=35'b11111001000010000100001000010011111;
   "G":glyph=35'b01111100001000010111100011000101111;
   "1":glyph=35'b00100011000010000100001000010001110;
   "2":glyph=35'b01110100010000100010001000100011111;
   "3":glyph=35'b11110000010000101110000010000111110;
   "4":glyph=35'b00010001100101010010111110001000010;
   "5":glyph=35'b11111100001000011110000010000111110;
   "6":glyph=35'b01110100001000011110100011000101110;
   "7":glyph=35'b11111000010001000100010000100001000;
   "8":glyph=35'b01110100011000101110100011000101110;
   default:glyph=0;
  endcase
 end
endfunction
reg [7:0] text_char;
reg [4:0] text_x;reg [2:0] text_y;
reg text_region;
reg [127:0] title;
reg [31:0] direction;
reg [9:0] text_offset;
reg [34:0] text_bits;
reg text_pixel;
always @*begin
 text_char=0;text_x=0;text_y=0;text_region=0;text_offset=0;
 title="SPECTRUM  DFT256";direction="    ";
 if(y>=280 && y<287 && x>=330 && x<426)begin
  text_offset=x-330;text_x=text_offset%6;text_y=y-280;
  text_char=title[(15-text_offset/6)*8 +:8];text_region=1;
 end else if(y>=280 && y<287 && x>=576 && x<594)begin
  text_offset=x-576;text_x=text_offset%6;text_y=y-280;
  case(text_offset/6)0:text_char="R";1:text_char="E";2:text_char="L";endcase
  text_region=1;
 end else if(y>=300 && y<307 && ((x>=330 && x<348)||(x>=568 && x<592)))begin
  if(x<348)begin text_offset=x-330;direction="LOW ";end
  else begin text_offset=x-568;direction="HIGH";end
  text_x=text_offset%6;text_y=y-300;
  text_char=direction[(3-text_offset/6)*8 +:8];text_region=1;
 end else if(y>=382 && y<389 && x>=345 && x<574)begin
  text_offset=x-345;text_x=text_offset%32;text_y=y-382;
  text_char=8'd49+text_offset/32;text_region=1;
 end
 text_bits=glyph(text_char);
 text_pixel=text_region && text_x<5 && text_bits[34-text_y*5-text_x];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;vs_previous<=0;frame_levels<=0;
  for(band=0;band<8;band=band+1)begin peak_height[band]<=0;peak_hold[band]<=0;end
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  vs_previous<=vs_in;
  if(!enable)begin
   frame_levels<=0;
   for(band=0;band<8;band=band+1)begin peak_height[band]<=0;peak_hold[band]<=0;end
  end else if(vs_previous && !vs_in)begin
   frame_levels<=levels;
   for(band=0;band<8;band=band+1)begin
    if((levels[band*8 +:8]>>2)>=peak_height[band] && levels[band*8 +:8]>=4)begin
     peak_height[band]<=levels[band*8 +:8]>>2;peak_hold[band]<=30;
    end else if(peak_hold[band]!=0)peak_hold[band]<=peak_hold[band]-1'b1;
    else if(peak_height[band]!=0)peak_height[band]<=peak_height[band]-1'b1;
   end
  end
  if(vs_previous && !vs_in)begin x<=0;y<=0;end
  else if(de_in)begin
   if(x==639)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
  end
  hs_out<=hs_in;vs_out<=vs_in;de_out<=de_in;
  if(!de_in)rgb_out<=0;
  else if(panel && text_pixel)rgb_out<=24'hb8f4ee;
  else if(panel && peak)rgb_out<=24'hffe8a0;
  else if(panel && bar)begin
   if(y<334)rgb_out<=24'hffcc50;
   else if(y<355)rgb_out<=24'h50e0c0;
   else rgb_out<=24'h30a8e8;
  end else if(panel && (grid||border))rgb_out<=24'h38505c;
  else if(panel)rgb_out<={2'b0,rgb_in[23:18],2'b0,rgb_in[15:10],2'b0,rgb_in[7:2]};
  else rgb_out<=rgb_in;
 end
end
endmodule
