`timescale 1ns/1ps
module tb_image_controls;
localparam integer STABLE=4,LONG=40;
localparam [8:0] DEFAULT_CONFIG=9'b0_00_010_010;
reg sd_clk=0;always #5 sd_clk=~sd_clk;
reg video_clk=0;
initial begin #3;forever #20 video_clk=~video_clk;end
reg rst=1,key_next_n=1,key_audio_n=1;
wire advance_press,audio_short,audio_long,station_advance,music_next,config_toggle;
wire [8:0] config_data,frame_config;
wire [8:0] published_config;
wire published_toggle,config_ack;
reg hs=1,vs=1,de=1;
reg [23:0] rgb=24'h2080e0;
wire hs_out,vs_out,de_out;
wire [23:0] rgb_out;
wl_key_debounce #(.STABLE_CYCLES(STABLE)) advance_key(
 sd_clk,rst,key_next_n,advance_press);
wl_key_gesture #(.STABLE_CYCLES(STABLE),.LONG_CYCLES(LONG)) audio_key(
 sd_clk,rst,key_audio_n,audio_short,audio_long);
wl_image_ui_ctrl controls(sd_clk,rst,advance_press,audio_short,audio_long,
 station_advance,music_next,config_data,config_toggle);
wl_image_config_source publisher(
 .clk(sd_clk),.rst(rst),.desired_config(config_data),.ack_toggle_async(config_ack),
 .config_data(published_config),.config_toggle(published_toggle));
wl_image_adjust image_adjust(
 .clk(video_clk),.rst(rst),.hs_in(hs),.vs_in(vs),.de_in(de),.rgb_in(rgb),
 .config_async(published_config),.config_toggle_async(published_toggle),
 .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out),
 .frame_config(frame_config),.config_ack_toggle(config_ack));

integer station_events=0,music_events=0,short_events=0,long_events=0;
integer config_events=0,frames=0,pixels_compared=0,q;
reg previous_toggle=0;
reg [8:0] model_config=DEFAULT_CONFIG;
reg [23:0] expected_rgb[0:2];
reg expected_hs[0:2],expected_vs[0:2],expected_de[0:2];
reg [2:0] valid=0;
function [8:0] cfg(input reg menu,input integer selection,input integer brightness,input integer contrast);
 cfg={menu,selection[1:0],brightness[2:0],contrast[2:0]};
endfunction
function [7:0] reference_channel(input integer channel,input integer brightness,input integer contrast);
 integer value;
 begin
  // Independent integer multiply models gain and round-to-nearest, then clips.
  value=(((channel-128)*(contrast+2)+2)>>>2)+128+(brightness-2)*32;
  if(value<0)reference_channel=0;
  else if(value>255)reference_channel=255;
  else reference_channel=value;
 end
endfunction
always @(posedge sd_clk)begin
 #1;
 if(rst)begin
  station_events=0;music_events=0;short_events=0;long_events=0;
  config_events=0;previous_toggle=0;
 end else begin
  if(station_advance)station_events=station_events+1;
  if(music_next)music_events=music_events+1;
  if(audio_short)short_events=short_events+1;
  if(audio_long)long_events=long_events+1;
  if(config_toggle!=previous_toggle)config_events=config_events+1;
  previous_toggle=config_toggle;
 end
end
always @(posedge video_clk)begin
 if(rst)valid<=0;
 else begin
  for(q=2;q>0;q=q-1)begin
   expected_rgb[q]<=expected_rgb[q-1];expected_hs[q]<=expected_hs[q-1];
   expected_vs[q]<=expected_vs[q-1];expected_de[q]<=expected_de[q-1];
  end
  expected_rgb[0]<={reference_channel(rgb[23:16],model_config[5:3],model_config[2:0]),
                    reference_channel(rgb[15:8],model_config[5:3],model_config[2:0]),
                    reference_channel(rgb[7:0],model_config[5:3],model_config[2:0])};
  expected_hs[0]<=hs;expected_vs[0]<=vs;expected_de[0]<=de;
  valid<={valid[1:0],1'b1};
  #1;
  if(frame_config!==model_config)$fatal(1,"config escaped frame boundary: got=%h expected=%h",frame_config,model_config);
  if(valid[2])begin
   if(rgb_out!==expected_rgb[2])$fatal(1,"pixel got=%h expected=%h frame_config=%h",rgb_out,expected_rgb[2],frame_config);
   if({hs_out,vs_out,de_out}!=={expected_hs[2],expected_vs[2],expected_de[2]})
    $fatal(1,"pixel and sync/DE pipeline differ");
   pixels_compared=pixels_compared+1;
  end
 end
end
task sd_cycles(input integer n);begin repeat(n)begin @(posedge sd_clk);#2;end end endtask
task video_cycles(input integer n);begin repeat(n)begin @(posedge video_clk);#2;end end endtask
task key2;
 begin
  @(negedge sd_clk);key_next_n=0;sd_cycles(STABLE+4);
  @(negedge sd_clk);key_next_n=1;sd_cycles(STABLE+4);
 end
endtask
task key3_short;
 begin
  @(negedge sd_clk);key_audio_n=0;sd_cycles(STABLE+4);
  @(negedge sd_clk);key_audio_n=1;sd_cycles(STABLE+4);
 end
endtask
task key3_long;
 integer music_before;
 begin
  music_before=music_events;
  @(negedge sd_clk);key_audio_n=0;sd_cycles(LONG*2+STABLE+4);
  if(music_events!=music_before)$fatal(1,"long hold changed music before release");
  @(negedge sd_clk);key_audio_n=1;sd_cycles(STABLE+4);
  if(music_events!=music_before)$fatal(1,"long release leaked a short music event");
 end
endtask
task routes(input integer stations,input integer music);
 begin
  if(station_events!=stations || music_events!=music)
   $fatal(1,"modal routing station=%0d music=%0d expected=%0d/%0d",station_events,music_events,stations,music);
 end
endtask
task settle_config(input [8:0] expected);
 integer timeout_cycles;
 begin
  if(config_data!==expected)$fatal(1,"source UI config got=%h expected=%h",config_data,expected);
  // Real round-trip mailbox handshake, with no forced DUT state.
  video_cycles(8);
  timeout_cycles=0;
  while(published_config!==expected || config_ack!==published_toggle)begin
   video_cycles(1);timeout_cycles=timeout_cycles+1;
   if(timeout_cycles>32)$fatal(1,"configuration publisher did not complete the round-trip handshake");
  end
  if(frame_config!==model_config)$fatal(1,"source event changed an active frame");
 end
endtask
task start_frame(input [8:0] expected,input [23:0] expected_pixel);
 begin
  @(negedge video_clk);vs=0;model_config=expected;
  video_cycles(1);
  if(frame_config!==expected)$fatal(1,"next frame did not latch stable UI config");
  @(negedge video_clk);vs=1;
  video_cycles(4);frames=frames+1;
  if(rgb_out!==expected_pixel)$fatal(1,"literal pixel got=%h expected=%h",rgb_out,expected_pixel);
 end
endtask

initial begin
 sd_cycles(8);@(negedge sd_clk);rst=0;
 video_cycles(10);
 if(rgb_out!==24'h2080e0 || frame_config!==DEFAULT_CONFIG)$fatal(1,"default RGB is not bit-exact");
 routes(0,0);
 key3_short();routes(0,1);

 key3_long();routes(0,1);
 settle_config(cfg(1,0,2,2));start_frame(cfg(1,0,2,2),24'h2080e0);
 // Brightness +32 is isolated from station advance and waits for VS falling.
 key2();routes(0,1);settle_config(cfg(1,0,3,2));
 if(rgb_out!==24'h2080e0)$fatal(1,"brightness changed before next frame");
 start_frame(cfg(1,0,3,2),24'h40a0ff);

 key3_short();routes(0,1);
 settle_config(cfg(1,1,3,2));start_frame(cfg(1,1,3,2),24'h40a0ff);
 key2();routes(0,1);settle_config(cfg(1,1,3,3));
 if(rgb_out!==24'h40a0ff)$fatal(1,"contrast changed before next frame");
 start_frame(cfg(1,1,3,3),24'h28a0ff);

 key3_short();routes(0,1);
 settle_config(cfg(1,2,3,3));start_frame(cfg(1,2,3,3),24'h28a0ff);
 key2();routes(0,1);settle_config(cfg(1,2,2,2));
 if(rgb_out!==24'h28a0ff)$fatal(1,"DEFAULT changed an active frame");
 start_frame(cfg(1,2,2,2),24'h2080e0);

 key3_short();routes(0,1);
 settle_config(cfg(1,3,2,2));start_frame(cfg(1,3,2,2),24'h2080e0);
 key2();routes(0,1);
 settle_config(cfg(0,3,2,2));start_frame(cfg(0,3,2,2),24'h2080e0);
 key2();routes(1,1);key3_short();routes(1,2);

 // A second menu session exits by a long hold, including its consumed release.
 key3_long();routes(1,2);
 settle_config(cfg(1,0,2,2));start_frame(cfg(1,0,2,2),24'h2080e0);
 key3_long();routes(1,2);
 settle_config(cfg(0,0,2,2));start_frame(cfg(0,0,2,2),24'h2080e0);
 video_cycles(10);routes(1,2);
 if(short_events!=5 || long_events!=3 || config_events!=10 || frames!=10)
  $fatal(1,"event totals short=%0d long=%0d config=%0d frames=%0d",short_events,long_events,config_events,frames);
 $display("PASS image controls: SD100MHz/video25MHz; RGB 2080e0 -> 40a0ff -> 28a0ff -> 2080e0; %0d pixels, %0d frame updates, 5 short/3 long gestures, station=1 music=2, modal isolation and release safety",pixels_compared,frames);
 $finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
