// Modal image settings use the existing station and music buttons.
module wl_image_ui_ctrl(
 input wire clk,input wire rst,input wire advance_press,
 input wire audio_short,input wire audio_long,
 output reg station_advance,output reg music_next,
 output reg [8:0] config_data,output reg config_toggle
);
reg [8:0] next_config;
reg next_advance,next_music;
always @*begin
 next_config=config_data;next_advance=0;next_music=0;
 if(audio_long)begin
  next_config[8]=!config_data[8];
  if(!config_data[8])next_config[7:6]=0;
 end else if(!config_data[8])begin
  next_advance=advance_press;next_music=audio_short;
 end else if(audio_short)begin
  next_config[7:6]=config_data[7:6]+1'b1;
 end else if(advance_press)begin
  case(config_data[7:6])
   2'd0:next_config[5:3]=(config_data[5:3]==4)?3'd0:config_data[5:3]+1'b1;
   2'd1:next_config[2:0]=(config_data[2:0]==4)?3'd0:config_data[2:0]+1'b1;
   2'd2:next_config[5:0]={3'd2,3'd2};
   2'd3:next_config[8]=0;
  endcase
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  config_data<={1'b0,2'd0,3'd2,3'd2};config_toggle<=0;
  station_advance<=0;music_next<=0;
 end else begin
  station_advance<=next_advance;music_next<=next_music;
  if(next_config!=config_data)begin
   config_data<=next_config;config_toggle<=~config_toggle;
  end
 end
end
endmodule
