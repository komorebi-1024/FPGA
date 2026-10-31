// Two-cycle pixel pipeline. Captions come from a synchronous 8192x32 ROM.
// The ROM holds four sets of 32 header rows + 64 footer rows.
module wl_osd #(
 parameter CAPTION_FILE="captions.hex",
 parameter FONT_FILE="ascii_font.hex",
 parameter integer CLK_HZ=25000000,
 parameter integer TYPE_CHAR_MS=125,
 parameter integer TYPE_MAX_CHARS=32,
 parameter integer VOICE_CAPTIONS=0
)(
 input wire clk,input wire rst,input wire hs_in,input wire vs_in,input wire de_in,
 input wire [23:0] rgb_in,input wire [1:0] station_id,
 input wire auto_mode,input wire test_audio,input wire [3:0] dwell_seconds,
 output reg hs_out,output reg vs_out,output reg de_out,output reg [23:0] rgb_out,
 input wire [1:0] voice_subtitle_phase,input wire [5:0] voice_subtitle_reveal
);
(* ram_style="block" *) reg [31:0] captions[0:8191];
(* ram_style="block" *) reg [7:0] ascii_font[0:2047];
initial begin $readmemh(CAPTION_FILE,captions);$readmemh(FONT_FILE,ascii_font);end
reg [9:0] x,y;
reg vs_previous;
reg [31:0] second_counter;
reg [3:0] su,st,mu,mt;
wire in_caption=de_in && (VOICE_CAPTIONS ?
 (y<24 || (y>=416 && y<440) || (y>=448 && y<472)) : (y<32 || y>=416));
wire in_status=de_in && y>=40 && y<56 && x>=16 && x<256;
wire panel=de_in && (y<64 || y>=416);
wire [6:0] cap_row=(y<32)?y[6:0]:(y-384);
wire [4:0] voice_row=(y<24)?y[4:0]:((y<440)?(y-416):(y-448));
wire [12:0] voice_base=(y<24)?13'd0:((y<440)?
 (13'd480+station_id*13'd480):
 (13'd2400+(station_id*13'd3+voice_subtitle_phase)*13'd480));
wire [12:0] caption_addr=VOICE_CAPTIONS ?
 (voice_base+voice_row*13'd20+{8'd0,x[9:5]}) :
 (station_id*13'd1920+cap_row*13'd20+{8'd0,x[9:5]});
// Typewriter reveal: only the description rows (cap_row>=64, screen y>=448) are
// revealed character by character; title and station/next lines show immediately.
localparam [31:0] CHAR_CLKS=CLK_HZ/1000*TYPE_CHAR_MS;
reg [1:0] station_prev;
reg [5:0] reveal_char;
reg [31:0] char_timer;
wire in_desc=de_in && (cap_row>=7'd64);
wire [9:0] reveal_x=10'd16+(10'd20*(VOICE_CAPTIONS?voice_subtitle_reveal:reveal_char));
wire desc_revealed=!in_desc || (x<reveal_x);
reg desc_revealed_d;
wire [5:0] status_column=(x-16)>>3;
reg [6:0] status_char;
always @*begin
 status_char=7'd32;
 case(status_column)
 0:status_char=auto_mode?"A":"S";1:status_char=auto_mode?"U":"T";
 2:status_char=auto_mode?"T":"O";3:status_char=auto_mode?"O":"P";
 5:status_char=test_audio?"T":"C";6:status_char=test_audio?"E":"H";
 7:status_char=test_audio?"S":"I";8:status_char=test_audio?"T":"M";
 10:status_char="P";11:status_char="=";12:status_char=(dwell_seconds==10)?"1":"0";
 13:status_char=(dwell_seconds==10)?"0":(7'd48+dwell_seconds);14:status_char="s";
 16:status_char="U";17:status_char="=";18:status_char=7'd48+mt;19:status_char=7'd48+mu;
 20:status_char=":";21:status_char=7'd48+st;22:status_char=7'd48+su;
 24:status_char="S";25:status_char="=";26:status_char=7'd49+station_id;
 27:status_char="/";28:status_char="4";
 endcase
 if(VOICE_CAPTIONS)begin
  case(status_column)
   0:status_char=auto_mode?"S":"M";1:status_char=auto_mode?"T":"O";
   2:status_char=auto_mode?"O":"V";3:status_char=auto_mode?"P":"E";
   5:status_char="4";6:status_char="8";7:status_char="K";8:status_char=" ";9:status_char=" ";
   10:status_char=auto_mode?"H":"A";11:status_char=auto_mode?"O":"U";
   12:status_char=auto_mode?"L":"T";13:status_char=auto_mode?"D":"O";14:status_char=" ";
  endcase
 end
end
wire [3:0] font_row=y-40;
reg [31:0] cap_word;
reg [7:0] font_word;
reg [4:0] cap_bit;
reg [2:0] font_bit;
reg cap_d,status_d,panel_d,de_d,hs_d,vs_d,rail_d,stop_d,selected_d;
reg [23:0] rgb_d;
wire rail=de_in && y>=407 && y<=408 && x>=80 && x<=560;
wire stop=de_in && y>=400 && y<=414 &&
 ((x>=76&&x<=84)||(x>=236&&x<=244)||(x>=396&&x<=404)||(x>=556&&x<=564));
wire selected=stop && ((station_id==0 && x<100)||(station_id==1&&x>=200&&x<300)||
                      (station_id==2&&x>=300&&x<500)||(station_id==3&&x>=500));
always @(posedge clk) begin
 cap_word<=captions[in_caption?caption_addr:13'd0];
 font_word<=ascii_font[{status_char,font_row}];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;vs_previous<=0;second_counter<=0;su<=0;st<=0;mu<=0;mt<=0;
  cap_bit<=0;font_bit<=0;cap_d<=0;status_d<=0;panel_d<=0;
  de_d<=0;hs_d<=0;vs_d<=0;rgb_d<=0;rail_d<=0;stop_d<=0;selected_d<=0;
  station_prev<=0;reveal_char<=0;char_timer<=0;desc_revealed_d<=0;
  de_out<=0;hs_out<=0;vs_out<=0;rgb_out<=0;
 end else begin
  vs_previous<=vs_in;
  if(vs_previous && !vs_in)begin x<=0;y<=0;end
  else if(de_in)begin
   if(x==639)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
  end
  if(second_counter==CLK_HZ-1)begin
   second_counter<=0;
   if(su==9)begin su<=0;
    if(st==5)begin st<=0;
     if(mu==9)begin mu<=0;if(mt==9)mt<=0;else mt<=mt+1'b1;end
     else mu<=mu+1'b1;
    end else st<=st+1'b1;
   end else su<=su+1'b1;
  end else second_counter<=second_counter+1'b1;
  if(station_prev!=station_id)begin
   station_prev<=station_id;reveal_char<=0;char_timer<=0;
  end else if(reveal_char<TYPE_MAX_CHARS)begin
   if(char_timer>=CHAR_CLKS-1)begin char_timer<=0;reveal_char<=reveal_char+1'b1;end
   else char_timer<=char_timer+1'b1;
  end
  cap_bit<=31-x[4:0];font_bit<=7-x[2:0];cap_d<=in_caption;status_d<=in_status;panel_d<=panel;
  desc_revealed_d<=desc_revealed;
  de_d<=de_in;hs_d<=hs_in;vs_d<=vs_in;rgb_d<=rgb_in;
  rail_d<=rail;stop_d<=stop;selected_d<=selected;
  de_out<=de_d;hs_out<=hs_d;vs_out<=vs_d;
  if(!de_d)rgb_out<=0;
  else if(status_d && font_word[font_bit])rgb_out<=24'h50e0e0;
  else if(cap_d && cap_word[cap_bit] && desc_revealed_d)rgb_out<=24'hffffff;
  else if(selected_d)rgb_out<=24'hffcc30;
  else if(stop_d||rail_d)rgb_out<=24'hbebebe;
  else if(panel_d)rgb_out<={2'b00,rgb_d[23:18],2'b00,rgb_d[15:10],2'b00,rgb_d[7:2]};
  else rgb_out<=rgb_d;
 end
end
endmodule
