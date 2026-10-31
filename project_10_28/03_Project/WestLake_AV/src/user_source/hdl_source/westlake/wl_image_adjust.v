// RGB brightness/contrast before OSD. Three registered pixel stages, no RAM/DSP.
// The source holds config until config_ack_toggle acknowledges its capture.
// A synchronized toggle captures the stable bus; VS falling applies one snapshot.
module wl_image_adjust(
 input wire clk,input wire rst,
 input wire hs_in,input wire vs_in,input wire de_in,input wire [23:0] rgb_in,
 input wire [8:0] config_async,input wire config_toggle_async,
 output reg hs_out,output reg vs_out,output reg de_out,output reg [23:0] rgb_out,
 output reg [8:0] frame_config,output reg config_ack_toggle
);
localparam [8:0] DEFAULT_CONFIG=9'b0_00_010_010;
(* async_reg="true" *) reg [8:0] config_meta,config_sync;
(* async_reg="true" *) reg [1:0] toggle_sync;
reg toggle_seen,capture_pending,vs_previous;
reg [8:0] pending_config;
wire frame_start=vs_previous && !vs_in;
wire [8:0] pixel_config=frame_start?pending_config:frame_config;

function [8:0] valid_config;
 input [8:0] value;
 begin
  valid_config={value[8:6],(value[5:3]<=4)?value[5:3]:3'd2,
                          (value[2:0]<=4)?value[2:0]:3'd2};
 end
endfunction

always @(posedge clk or posedge rst)begin
 if(rst)begin
  config_meta<=DEFAULT_CONFIG;config_sync<=DEFAULT_CONFIG;toggle_sync<=0;
  toggle_seen<=0;capture_pending<=0;vs_previous<=1;
  pending_config<=DEFAULT_CONFIG;frame_config<=DEFAULT_CONFIG;config_ack_toggle<=0;
 end else begin
  config_meta<=config_async;config_sync<=config_meta;
  toggle_sync<={toggle_sync[0],config_toggle_async};vs_previous<=vs_in;
  if(capture_pending)begin
   pending_config<=valid_config(config_sync);capture_pending<=0;config_ack_toggle<=toggle_seen;
  end
  if(toggle_sync[1]!=toggle_seen)begin
   toggle_seen<=toggle_sync[1];capture_pending<=1;
  end
  if(frame_start)frame_config<=pending_config;
 end
end

// gain_q2 = 2,3,4,5,6, i.e. 50%,75%,100%,125%,150% around RGB midpoint 128.
// Explicit shift/add avoids inferring three general multipliers.
function signed [12:0] contrast_product;
 input [7:0] sample;
 input [2:0] level;
 reg signed [12:0] delta;
 begin
  delta=$signed({1'b0,sample})-13'sd128;
  case(level)
   0:contrast_product=delta<<<1;
   1:contrast_product=delta+(delta<<<1);
   3:contrast_product=delta+(delta<<<2);
   4:contrast_product=(delta<<<1)+(delta<<<2);
   default:contrast_product=delta<<<2;
  endcase
 end
endfunction
function signed [12:0] brightness_offset;
 input [2:0] level;
 begin
  case(level)
   0:brightness_offset=-13'sd64;
   1:brightness_offset=-13'sd32;
   3:brightness_offset=13'sd32;
   4:brightness_offset=13'sd64;
   default:brightness_offset=0;
  endcase
 end
endfunction
function [7:0] clamp8;
 input signed [12:0] value;
 begin
  if(value<0)clamp8=0;
  else if(value>255)clamp8=255;
  else clamp8=value[7:0];
 end
endfunction
reg signed [12:0] product_r,product_g,product_b,offset_d;
reg signed [12:0] sum_r,sum_g,sum_b;
reg hs_d1,vs_d1,de_d1,hs_d2,vs_d2,de_d2;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  product_r<=0;product_g<=0;product_b<=0;offset_d<=0;
  sum_r<=0;sum_g<=0;sum_b<=0;
  hs_d1<=0;vs_d1<=0;de_d1<=0;hs_d2<=0;vs_d2<=0;de_d2<=0;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  product_r<=contrast_product(rgb_in[23:16],pixel_config[2:0]);
  product_g<=contrast_product(rgb_in[15:8],pixel_config[2:0]);
  product_b<=contrast_product(rgb_in[7:0],pixel_config[2:0]);
  offset_d<=brightness_offset(pixel_config[5:3]);
  sum_r<=((product_r+13'sd2)>>>2)+13'sd128+offset_d;
  sum_g<=((product_g+13'sd2)>>>2)+13'sd128+offset_d;
  sum_b<=((product_b+13'sd2)>>>2)+13'sd128+offset_d;
  rgb_out<={clamp8(sum_r),clamp8(sum_g),clamp8(sum_b)};
  hs_d1<=hs_in;vs_d1<=vs_in;de_d1<=de_in;
  hs_d2<=hs_d1;vs_d2<=vs_d1;de_d2<=de_d1;
  hs_out<=hs_d2;vs_out<=vs_d2;de_out<=de_d2;
 end
end
endmodule
