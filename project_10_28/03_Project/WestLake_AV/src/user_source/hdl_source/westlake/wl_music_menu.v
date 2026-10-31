// Brief track-selection menu. Track names are numbered MUSIC 1..4 in this build.
// Two-stage synchronous font/pixel pipeline, same font ROM as the existing OSD.
module wl_music_menu #(
 parameter FONT_FILE="ascii_font.hex",parameter integer CLK_HZ=25000000
)(
 input wire clk,input wire rst,input wire menu_toggle,
 input wire [1:0] track_id,input wire [2:0] track_count,
 input wire playing,input wire audio_error,input wire underrun,
 input wire hs_in,input wire vs_in,input wire de_in,input wire [23:0] rgb_in,
 output reg hs_out,output reg vs_out,output reg de_out,output reg [23:0] rgb_out,
 input wire test_mode,input wire arrival_active,
 input wire narration_active,input wire narration_error
);
(* ram_style="block" *) reg [7:0] font[0:2047];
initial $readmemh(FONT_FILE,font);
reg [9:0] x,y;reg vs_previous,menu_seen;
reg [26:0] menu_timer;
wire panel=menu_timer!=0 && x>=344 && x<608 && y>=72 && y<136;
wire text_area=panel && x>=360 && x<520 && ((y>=80 && y<96)||(y>=112 && y<128));
wire [4:0] column=(x-360)>>3;
reg [6:0] character;
reg [159:0] line_text;
always @*begin
 if(y<104)line_text=narration_active?"STATION NARRATION   ":"MUSIC 0/0           ";
 else if(test_mode)line_text="TEST TONE 440 HZ    ";
 else if(arrival_active)line_text="ARRIVAL CHIME       ";
 else if(narration_error)line_text="VOICE ERROR         ";
 else if(narration_active)line_text="SPEAKING            ";
 else if(audio_error)line_text="SD AUDIO ERROR      ";
 else if(track_count==0)line_text="NO MUSIC            ";
 else if(underrun)line_text="AUDIO UNDERRUN      ";
 else if(playing)line_text="PLAYING             ";
 else line_text="PAUSED              ";
 character=7'd32;
 if(column<20)character=line_text[(19-column)*8 +: 8];
 if(y<104 && !narration_active && column==6)character=(track_count==0)?7'd45:(7'd49+track_id);
 if(y<104 && !narration_active && column==8)character=7'd48+track_count;
end
reg [7:0] font_word;
reg [2:0] font_bit;
reg panel_d,text_d,hs_d,vs_d,de_d;reg [23:0] rgb_d;
always @(posedge clk)font_word<=font[{character,y[3:0]}];
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;vs_previous<=0;menu_seen<=0;menu_timer<=CLK_HZ*3;
  font_bit<=0;panel_d<=0;text_d<=0;hs_d<=0;vs_d<=0;de_d<=0;rgb_d<=0;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  menu_seen<=menu_toggle;
  if(test_mode || arrival_active || narration_active || menu_toggle!=menu_seen)menu_timer<=CLK_HZ*3;
  else if(menu_timer!=0)menu_timer<=menu_timer-1'b1;
  vs_previous<=vs_in;
  if(vs_previous && !vs_in)begin x<=0;y<=0;end
  else if(de_in)begin if(x==639)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;end
  panel_d<=panel;text_d<=text_area;font_bit<=7-x[2:0];
  hs_d<=hs_in;vs_d<=vs_in;de_d<=de_in;rgb_d<=rgb_in;
  hs_out<=hs_d;vs_out<=vs_d;de_out<=de_d;
  if(!de_d)rgb_out<=0;
  else if(text_d && font_word[font_bit])rgb_out<=24'h70e8e0;
  else if(panel_d)rgb_out<=24'h102430;
  else rgb_out<=rgb_d;
 end
end
endmodule
