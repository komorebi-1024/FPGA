// Transition controller v3: strictly vs-aligned, edge-triggered, explicit old/new buffer.
// image_ready is a 1-clk pulse (committed buffer switched). Only acted on in SECTION
// mode; station publishes are ignored so station images appear directly.
// If the mode leaves SECTION mid-transition (key press), abort immediately.
module wl_transition_ctrl #(
 parameter integer TRANS_FRAMES=60,  // 1s at ~60fps
 parameter integer HALF=30,
 parameter integer COOLDOWN_CLKS=250000  // 10ms guard between transitions at 25MHz
)(
 input wire clk,input wire rst,             // video_clk
 input wire vs,                             // frame start (vs_0 rising edge detected externally)
 input wire image_ready,                    // 1-clk pulse: new frame committed
 input wire in_section,                     // 1 = in SECTION mode (promo carousel)
 output reg trans_active,                   // 1 during transition
 output reg [1:0] trans_type,               // 0=fade 1=slide1 2=wipe 3=slide2
 output reg [5:0] trans_frame,              // 0..TRANS_FRAMES-1
 output reg [7:0] fade_coeff,               // 0..255
 output reg read_old,                       // 1=read old buffer during fade-out, 0=new/fade-in
 output reg trans_done                      // 1-cycle pulse when transition completes
);
reg [1:0] next_type;
reg vs_prev; reg [24:0] cooldown; reg pending;
wire vs_rise = vs && !vs_prev;

// fade_coeff is registered at vs_rise, so during frame k it holds fade_calc(k-1).
// The buffer switch happens at frame HALF, hence the coefficient must reach
// exactly 0 on the last old frame (k=HALF-1) and the first new frame (k=HALF);
// otherwise the new image peeks through before the fade-out reaches black.
reg [7:0] fade_calc;
always @* begin
 if(trans_type==2'd0)begin
  if(trans_frame<HALF-1)
   fade_calc=(8'd255*(HALF-2-trans_frame))/(HALF-1);
  else
   fade_calc=(8'd255*(trans_frame+1'b1-HALF))/(HALF-1);
 end else fade_calc=8'd255;
end

always @(posedge clk or posedge rst)begin
 if(rst)begin
  trans_active<=0;trans_type<=0;trans_frame<=0;fade_coeff<=255;
  next_type<=0;vs_prev<=0;cooldown<=0;read_old<=0;trans_done<=0;pending<=0;
 end else begin
  vs_prev<=vs;trans_done<=0;
  if(image_ready && in_section) pending<=1;   // station commits (in_section=0) are dropped
  if(trans_active)begin
   if(!in_section)begin
    // key pressed mid-transition: abort, station image cuts in directly
    trans_active<=0;read_old<=0;trans_done<=1;cooldown<=COOLDOWN_CLKS;
   end else if(vs_rise)begin
    if(trans_frame>=TRANS_FRAMES-1)begin
     trans_active<=0;fade_coeff<=255;read_old<=0;trans_done<=1;cooldown<=COOLDOWN_CLKS;
    end else begin
     trans_frame<=trans_frame+1'b1;
     fade_coeff<=fade_calc;
     read_old<=(trans_type==2'd0 && trans_frame+1'b1<HALF);
    end
   end
  end else begin
   if(cooldown>0) cooldown<=cooldown-1'b1;
   if(vs_rise && fade_coeff!=8'd255) fade_coeff<=255; // restore after an aborted fade, at frame boundary
   if(pending && cooldown==0)begin
    pending<=0;
    trans_active<=1;trans_type<=next_type;
    next_type<=(next_type==2'd3)?2'd0:(next_type+1'b1);
    trans_frame<=0;fade_coeff<=255;read_old<=1;
   end
  end
 end
end
endmodule