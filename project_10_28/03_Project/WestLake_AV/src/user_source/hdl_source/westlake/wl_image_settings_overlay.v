// One pixel-clock stage. Compact LUT glyphs use no font RAM or DSP.
// The picture controls are applied upstream, so this menu stays readable.
module wl_image_settings_overlay(
 input wire clk,input wire rst,input wire hs_in,input wire vs_in,input wire de_in,
 input wire [23:0] rgb_in,input wire [8:0] config_in,
 output reg hs_out,output reg vs_out,output reg de_out,output reg [23:0] rgb_out
);
localparam [8:0] DEFAULT_CONFIG=9'b0_00_010_010;
reg [9:0] x,y;
reg vs_previous;
reg [8:0] frame_config;
wire panel=frame_config[8] && x>=140 && x<500 && y>=144 && y<320;
wire border=x==140 || x==499 || y==144 || y==319 || y==178;
wire [9:0] selected_y=10'd182+{6'd0,frame_config[7:6],2'b00}*6;
wire selected_row=x>=152 && x<488 && y>=selected_y && y<selected_y+24;
wire selected_border=selected_row && (x==152 || x==487 || y==selected_y || y==selected_y+23);

function [34:0] glyph;
 input [7:0] c;
 begin
  case(c)
   "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
   "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
   "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
   "G":glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
   "H":glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "I":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
   "J":glyph={5'b00111,5'b00010,5'b00010,5'b00010,5'b10010,5'b10010,5'b01100};
   "K":glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
   "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
   "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
   "N":glyph={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
   "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "P":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
   "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
   "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
   "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
   "U":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "X":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
   "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
   "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
   "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
   "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
   "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
   "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
   "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
   "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
   "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
   "+":glyph={5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000};
   "-":glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
   "%":glyph={5'b11001,5'b11010,5'b00010,5'b00100,5'b01000,5'b01011,5'b10011};
   ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
   ">":glyph={5'b10000,5'b01000,5'b00100,5'b00010,5'b00100,5'b01000,5'b10000};
   default:glyph=0;
  endcase
 end
endfunction

reg [159:0] text_line;
reg [31:0] value_line;
reg [7:0] text_char;
reg [9:0] text_offset;
reg [4:0] text_column;
reg [2:0] text_x,text_y;
reg text_region,value_region;
reg [34:0] text_bits;
reg text_pixel;
always @*begin
 text_line=0;value_line=0;text_char=0;text_offset=0;text_column=0;
 text_x=0;text_y=0;text_region=0;value_region=0;
 if(y>=156 && y<170 && x>=160 && x<328)begin
  text_line="IMAGE SETTINGS      ";text_offset=(x-160)>>1;
  text_y=(y-156)>>1;text_region=1;
 end else if(y>=188 && y<274 && (y-188)%24<14)begin
  case((y-188)/24)
   0:begin
    text_line="BRIGHTNESS          ";
    case(frame_config[5:3])
     0:value_line="-64 ";1:value_line="-32 ";3:value_line="+32 ";4:value_line="+64 ";
     default:value_line="  0 ";
    endcase
   end
   1:begin
    text_line="CONTRAST            ";
    case(frame_config[2:0])
     0:value_line=" 50%";1:value_line=" 75%";3:value_line="125%";4:value_line="150%";
     default:value_line="100%";
    endcase
   end
   2:text_line="DEFAULT             ";
   3:text_line="EXIT                ";
  endcase
  text_y=((y-188)%24)>>1;
  if(x>=174 && x<318)begin text_offset=(x-174)>>1;text_region=1;end
  else if(x>=382 && x<430 && (y-188)/24<2)begin
   text_offset=(x-382)>>1;text_region=1;value_region=1;
  end
 end else if(y>=292 && y<299 && x>=158 && x<272)begin
  text_line="K2:ADJUST K3:SELECT ";text_offset=x-158;text_y=y-292;text_region=1;
 end else if(y>=308 && y<315 && x>=158 && x<230)begin
  text_line="HOLD K3:EXIT        ";text_offset=x-158;text_y=y-308;text_region=1;
 end
 text_column=text_offset/6;text_x=text_offset%6;
 if(value_region)text_char=value_line[(3-text_column)*8 +:8];
 else if(text_region)text_char=text_line[(19-text_column)*8 +:8];
 text_bits=glyph(text_char);
 text_pixel=text_region && text_x<5 && text_bits[34-text_y*5-text_x];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;vs_previous<=0;frame_config<=DEFAULT_CONFIG;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  vs_previous<=vs_in;
  if(vs_previous && !vs_in)begin x<=0;y<=0;frame_config<=config_in;end
  else if(de_in)begin
   if(x==639)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
  end
  hs_out<=hs_in;vs_out<=vs_in;de_out<=de_in;
  if(!de_in || !panel)rgb_out<=rgb_in;
  else if(text_pixel)rgb_out<=value_region?24'hffe8a0:24'hb8f4ee;
  else if(selected_border)rgb_out<=24'h50d0d0;
  else if(border)rgb_out<=24'h38505c;
  else if(selected_row)rgb_out<=24'h203c48;
  else rgb_out<=24'h102430;
 end
end
endmodule
