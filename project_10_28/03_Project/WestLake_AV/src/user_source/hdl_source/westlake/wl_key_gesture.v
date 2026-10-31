// Active-low key: short events occur on release; a long hold fires only once.
module wl_key_gesture #(
 parameter integer STABLE_CYCLES=2000000,
 parameter integer LONG_CYCLES=100000000
)(
 input wire clk,input wire rst,input wire key_n,
 output reg short_press,output reg long_press
);
localparam integer STABLE_BITS=(STABLE_CYCLES>1)?$clog2(STABLE_CYCLES):1;
localparam integer LONG_BITS=(LONG_CYCLES>1)?$clog2(LONG_CYCLES):1;
(* async_reg="true" *) reg [1:0] sync;
reg stable,long_sent;
reg [STABLE_BITS-1:0] stable_count;
reg [LONG_BITS-1:0] hold_count;
wire stable_change=(sync[1]!=stable) &&
                   (STABLE_CYCLES<=1 || stable_count==STABLE_CYCLES-1);
wire hold_elapsed=(LONG_CYCLES<=1 || hold_count==LONG_CYCLES-1);
always @(posedge clk or posedge rst)begin
 if(rst)begin
  sync<=2'b11;stable<=1;long_sent<=0;stable_count<=0;hold_count<=0;
  short_press<=0;long_press<=0;
 end else begin
  sync<={sync[0],key_n};short_press<=0;long_press<=0;
  if(sync[1]==stable || stable_change)stable_count<=0;
  else stable_count<=stable_count+1'b1;
  if(stable_change)begin
   stable<=sync[1];hold_count<=0;long_sent<=0;
   if(sync[1] && !long_sent)begin
    // A release exactly on the threshold also belongs to the long gesture.
    if(hold_elapsed)long_press<=1;else short_press<=1;
   end
  end else if(!stable && !long_sent)begin
   if(hold_elapsed)begin long_press<=1;long_sent<=1;end
   else hold_count<=hold_count+1'b1;
  end
 end
end
endmodule
