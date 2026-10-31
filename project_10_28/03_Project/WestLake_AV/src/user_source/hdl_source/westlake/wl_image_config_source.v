// Publish a stable configuration bus until the pixel domain captures it.
// UI events can arrive on adjacent clocks; while busy only the latest desired
// value matters. Acknowledge capture rather than VS so one frame need not stall UI.
module wl_image_config_source(
 input wire clk,input wire rst,input wire [8:0] desired_config,input wire ack_toggle_async,
 output reg [8:0] config_data,output reg config_toggle
);
localparam [8:0] DEFAULT_CONFIG=9'b0_00_010_010;
(* async_reg="true" *) reg [1:0] ack_sync;
always @(posedge clk or posedge rst)begin
 if(rst)begin ack_sync<=0;config_data<=DEFAULT_CONFIG;config_toggle<=0;end
 else begin
  ack_sync<={ack_sync[0],ack_toggle_async};
  if(ack_sync[1]==config_toggle && desired_config!=config_data)begin
   config_data<=desired_config;config_toggle<=~config_toggle;
  end
 end
end
endmodule
