// Pixel-domain fade applied after OSD. fade_coeff is 8-bit fixed point:
// 255 = full brightness, 0 = black. 2-cycle pipeline keeps the multiply registered
// and keeps hs/vs/de aligned with the delayed RGB.
module wl_video_fx #(
 parameter integer COEFF_BITS=8
)(
 input wire clk,input wire rst,
 input wire hs_in,input wire vs_in,input wire de_in,input wire [23:0] rgb_in,
 input wire [COEFF_BITS-1:0] fade_coeff,
 output reg hs_out,output reg vs_out,output reg de_out,output reg [23:0] rgb_out
);
reg hs_d1,vs_d1,de_d1;reg [23:0] rgb_d1;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  hs_d1<=0;vs_d1<=0;de_d1<=0;rgb_d1<=0;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  hs_d1<=hs_in;vs_d1<=vs_in;de_d1<=de_in;rgb_d1<=rgb_in;
  hs_out<=hs_d1;vs_out<=vs_d1;de_out<=de_d1;
  rgb_out[23:16]<=(({8'd0,rgb_d1[23:16]}*fade_coeff)>>COEFF_BITS);
  rgb_out[15:8] <=(({8'd0,rgb_d1[15:8]} *fade_coeff)>>COEFF_BITS);
  rgb_out[7:0]  <=(({8'd0,rgb_d1[7:0]}  *fade_coeff)>>COEFF_BITS);
 end
end
endmodule
