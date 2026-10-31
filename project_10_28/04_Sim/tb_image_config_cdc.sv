`timescale 1ns/1ps
module tb_image_config_cdc;
localparam [8:0] DEFAULT_CONFIG=9'b0_00_010_010;
reg sc=0,vc=0;always #5 sc=~sc;always #20 vc=~vc;
reg rst=1,vs=1;
reg [8:0] desired_config=DEFAULT_CONFIG;
wire [8:0] frame_config;wire ho,vo,dout;wire [23:0] rgb;
wire ack_toggle;
`ifdef UNSAFE_OLD_TOGGLE
// Baseline reproduction: each 100MHz UI event directly toggles a 25MHz CDC.
reg [8:0] config_data=DEFAULT_CONFIG;reg config_toggle=0;
assign ack_toggle=config_toggle;
always @(posedge sc or posedge rst)
 if(rst)begin config_data<=DEFAULT_CONFIG;config_toggle<=0;end
 else if(desired_config!=config_data)begin config_data<=desired_config;config_toggle<=~config_toggle;end
`else
wire [8:0] config_data;wire config_toggle;
wl_image_config_source source(sc,rst,desired_config,ack_toggle,config_data,config_toggle);
`endif
wl_image_adjust adjust(
 .clk(vc),.rst(rst),.hs_in(1'b1),.vs_in(vs),.de_in(1'b1),.rgb_in(24'h20a0e0),
 .config_async(config_data),.config_toggle_async(config_toggle),
 .hs_out(ho),.vs_out(vo),.de_out(dout),.rgb_out(rgb),.frame_config(frame_config)
`ifndef UNSAFE_OLD_TOGGLE
 ,.config_ack_toggle(ack_toggle)
`endif
);
integer packets=0;reg toggle_previous=0;
reg [8:0] source_before;reg toggle_before,busy_before;
always @(posedge sc)begin
 if(rst)toggle_previous=0;
 else begin
  source_before=config_data;toggle_before=config_toggle;busy_before=(ack_toggle!=config_toggle);
  #1;
`ifndef UNSAFE_OLD_TOGGLE
  if(!rst && busy_before && (config_data!==source_before || config_toggle!==toggle_before))
   $fatal(1,"source changed an unacknowledged config bus");
`endif
  if(config_toggle!=toggle_previous)packets=packets+1;
  toggle_previous=config_toggle;
 end
end
reg vs_previous=1;reg [8:0] frame_previous=DEFAULT_CONFIG;reg frame_edge;
always @(posedge vc)begin
 if(rst)begin vs_previous=1;frame_previous=DEFAULT_CONFIG;end
 else begin
  frame_edge=vs_previous && !vs;vs_previous=vs;
  #1;
  if(!rst && frame_config!==frame_previous && !frame_edge)$fatal(1,"config changed away from VS boundary: actual=%h previous=%h rst=%b vs=%b",frame_config,frame_previous,rst,vs);
  frame_previous=frame_config;
 end
end
task cycles(input integer count);begin repeat(count)@(negedge sc);end endtask
task wait_latest;
 integer watchdog;
 begin
  watchdog=0;
  while(config_data!==desired_config || ack_toggle!==config_toggle)begin
   cycles(1);watchdog=watchdog+1;if(watchdog>200)$fatal(1,"latest source config was lost");
  end
  cycles(4);
 end
endtask
task frame(input [8:0] expected);
 begin
  @(negedge vc);vs=0;@(negedge vc);
  if(frame_config!==expected)$fatal(1,"latest config lost across CDC: actual=%h expected=%h",frame_config,expected);
  vs=1;@(negedge vc);
 end
endtask
integer before_packets,k;
initial begin
 cycles(8);rst=0;
 // Both 100MHz events fall between 25MHz sampling edges.
 @(posedge vc);#1;@(negedge sc);desired_config=9'b1_00_000_100;
 @(negedge sc);desired_config=9'b1_01_100_000;
 cycles(60);wait_latest();frame(9'b1_01_100_000);
`ifdef UNSAFE_OLD_TOGGLE
 $fatal(1,"unsafe baseline unexpectedly passed");
`else
 // Busy-time changes are coalesced; the source cannot overwrite the first bus.
 before_packets=packets;
 @(posedge vc);#1;
 for(k=0;k<8;k=k+1)begin
  @(negedge sc);
  desired_config={1'b1,k[1:0],3'(k%5),3'((k+1)%5)};
 end
 @(negedge sc);desired_config=9'b1_11_100_100;
 wait_latest();
 if(packets-before_packets!=2)$fatal(1,"busy updates were not coalesced into first/latest transactions");
 if(frame_config!==9'b1_01_100_000)$fatal(1,"pending config applied without a frame boundary");
 frame(9'b1_11_100_100);
 // Reset while a transaction is in flight restores both toggle endpoints.
 @(negedge sc);desired_config=9'b0_10_000_001;
 wait(config_toggle!=ack_toggle);@(negedge sc);rst=1;desired_config=DEFAULT_CONFIG;vs=1;
 cycles(8);rst=0;cycles(20);wait_latest();
 if(frame_config!==DEFAULT_CONFIG || config_toggle!==0 || ack_toggle!==0)$fatal(1,"in-flight reset left stale config/toggle");
 @(negedge sc);desired_config=9'b1_01_011_001;wait_latest();frame(9'b1_01_011_001);
 $display("PASS image config CDC: 100/25MHz, 10ns event spacing, busy coalescing, stable unacked bus, latest frame snapshot and in-flight reset");$finish;
`endif
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
