// Wait after the final narration sample, then request one automatic departure.
// A level completion input cannot retrigger until the vehicle leaves the station.
module wl_station_departure #(
 parameter integer CLK_HZ=25000000,
 parameter integer HOLD_CYCLES=CLK_HZ*3
)(
 input wire clk,input wire rst,input wire in_station,input wire narration_complete,
 output reg depart_toggle
);
localparam integer COUNT_BITS=(HOLD_CYCLES>1)?$clog2(HOLD_CYCLES):1;
reg [COUNT_BITS-1:0] hold_count;
reg fired;
always @(posedge clk or posedge rst)begin
 if(rst)begin hold_count<=0;fired<=0;depart_toggle<=0;end
 else if(!in_station)begin hold_count<=0;fired<=0;end
 else if(!narration_complete)hold_count<=0;
 else if(!fired)begin
  if(HOLD_CYCLES<=1 || hold_count==HOLD_CYCLES-1)begin
   depart_toggle<=~depart_toggle;fired<=1;hold_count<=0;
  end else hold_count<=hold_count+1'b1;
 end
end
endmodule
