`timescale 1ns/1ps
module tb_image_ui_ctrl;
reg clk=0;always #5 clk=~clk;
reg rst=1,advance=0,audio_short=0,audio_long=0;
wire station_advance,music_next,toggle;
wire [8:0] config_data;
integer level,i;
wl_image_ui_ctrl dut(clk,rst,advance,audio_short,audio_long,
 station_advance,music_next,config_data,toggle);
function [8:0] cfg(input reg menu,input integer selection,input integer brightness,input integer contrast);
 cfg={menu,selection[1:0],brightness[2:0],contrast[2:0]};
endfunction
task event_check(input reg adv,input reg sh,input reg lo,input [8:0] expected,
 input reg expected_advance,input reg expected_music);
 reg previous_toggle;reg [8:0] previous_config;
 begin
  @(negedge clk);advance=adv;audio_short=sh;audio_long=lo;
  previous_toggle=toggle;previous_config=config_data;
  @(posedge clk);#1;
  if(config_data!==expected || station_advance!==expected_advance || music_next!==expected_music)
   $fatal(1,"UI got cfg=%h advance=%b music=%b expected=%h/%b/%b",config_data,station_advance,music_next,expected,expected_advance,expected_music);
  if(toggle!==(previous_toggle^(previous_config!=expected)))$fatal(1,"config toggle did not match actual change");
  @(negedge clk);advance=0;audio_short=0;audio_long=0;
  previous_toggle=toggle;
  repeat(3)begin
   @(posedge clk);#1;
   if(config_data!==expected || station_advance || music_next || toggle!==previous_toggle)
    $fatal(1,"UI outputs repeated or config changed between events");
  end
 end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 if(config_data!==cfg(0,0,2,2) || toggle || station_advance || music_next)$fatal(1,"UI default");
 event_check(1,0,0,cfg(0,0,2,2),1,0);
 event_check(0,1,0,cfg(0,0,2,2),0,1);
 event_check(1,1,0,cfg(0,0,2,2),1,1);
 // Long wins over both other buttons; entering cannot cut music or depart.
 event_check(1,1,1,cfg(1,0,2,2),0,0);
 level=2;
 for(i=0;i<5;i=i+1)begin
  level=(level==4)?0:level+1;
  event_check(1,0,0,cfg(1,0,level,2),0,0);
 end
 event_check(0,1,0,cfg(1,1,2,2),0,0);
 level=2;
 for(i=0;i<5;i=i+1)begin
  level=(level==4)?0:level+1;
  event_check(1,0,0,cfg(1,1,2,level),0,0);
 end
 event_check(1,0,0,cfg(1,1,2,3),0,0);
 // Simultaneous menu short/advance selects the next item without adjusting.
 event_check(1,1,0,cfg(1,2,2,3),0,0);
 event_check(1,0,0,cfg(1,2,2,2),0,0);
 event_check(1,0,0,cfg(1,2,2,2),0,0);
 event_check(0,1,0,cfg(1,3,2,2),0,0);
 event_check(0,1,0,cfg(1,0,2,2),0,0);
 event_check(1,0,0,cfg(1,0,3,2),0,0);
 event_check(0,1,0,cfg(1,1,3,2),0,0);
 event_check(0,1,0,cfg(1,2,3,2),0,0);
 event_check(1,0,0,cfg(1,2,2,2),0,0);
 event_check(0,1,0,cfg(1,3,2,2),0,0);
 event_check(1,0,0,cfg(0,3,2,2),0,0);
 event_check(1,0,0,cfg(0,3,2,2),1,0);
 event_check(0,1,0,cfg(0,3,2,2),0,1);
 // Re-entry always selects brightness, preserving adjusted values on exit.
 event_check(0,0,1,cfg(1,0,2,2),0,0);
 event_check(1,0,0,cfg(1,0,3,2),0,0);
 event_check(0,1,0,cfg(1,1,3,2),0,0);
 event_check(1,1,1,cfg(0,1,3,2),0,0);
 event_check(0,0,1,cfg(1,0,3,2),0,0);
 @(negedge clk);rst=1;
 @(posedge clk);#1;
 if(config_data!==cfg(0,0,2,2) || toggle || station_advance || music_next)$fatal(1,"UI reset");
 $display("PASS image UI: defaults, all levels, selection wrap, restore, exit/re-entry, event priority, modal isolation, toggle stability");
 $finish;
end
initial begin #20000;$fatal(1,"timeout");end
endmodule
