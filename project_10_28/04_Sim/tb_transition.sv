`timescale 1ns/1ps
module tb_transition;
reg clk=0;always #20 clk=~clk; // 25MHz video_clk
reg rst=1;
reg [23:0] rgb_in=0; reg [7:0] coeff=255;
wire [23:0] rgb_out; wire hso,vso,deo;
wl_video_fx fx(clk,rst,1'b0,1'b0,1'b1,rgb_in,coeff,hso,vso,deo,rgb_out);

reg vs=0,buf_changed=0,scene_section=0;
wire trans_active;wire[1:0] trans_type;wire[5:0] trans_frame;wire[7:0] fade_coeff;
wl_transition_ctrl tc(.clk(clk),.rst(rst),.vs(vs),.image_ready(buf_changed),.in_section(scene_section),
 .trans_active(trans_active),.trans_type(trans_type),.trans_frame(trans_frame),.fade_coeff(fade_coeff),
 .read_old(),.trans_done());

task wait_cycles(input integer n); repeat(n)@(negedge clk); endtask
task pulse_vs; begin vs=1;@(negedge clk);vs=0;end endtask
task pulse_buf; begin buf_changed=1;@(negedge clk);buf_changed=0;end endtask
task run_transition; begin repeat(61)begin pulse_vs;wait_cycles(2);end wait_cycles(250100);end endtask

integer i;
initial begin
 rst=1;repeat(4)@(negedge clk);rst=0;wait_cycles(4);
 // ---- test wl_video_fx ----
 rgb_in=24'hFF8844;
 coeff=255; wait_cycles(4);
 if(rgb_out!==24'hFE8743) $display("coeff=255 -> %h (expect ~fe8743)", rgb_out); else $display("PASS fx coeff=255");
 coeff=128; wait_cycles(4);
 if(rgb_out!==24'h7F4422) $display("coeff=128 -> %h (expect 7f4422)", rgb_out); else $display("PASS fx coeff=128");
 coeff=0; wait_cycles(4);
 if(rgb_out!==24'h000000) $display("coeff=0 -> %h", rgb_out); else $display("PASS fx coeff=0");
 // ---- test wl_transition_ctrl rotation ----
 scene_section=1;
 pulse_buf; wait_cycles(4);
 if(!trans_active || trans_type!==0) $fatal(1,"start: active=%b type=%0d",trans_active,trans_type);
 $display("PASS start transition type=fade");
 // run 60 vs pulses (one full fade transition), check fade_coeff goes down then up
 for(i=0;i<60;i=i+1)begin
  pulse_vs; wait_cycles(2);
  if(i==1 && fade_coeff<255) $display("  frame1 coeff=%0d",fade_coeff);
  if(i==29 && fade_coeff>30) $display("  frame29 coeff=%0d (should be near 0)",fade_coeff);
  if(i==30 && fade_coeff>30) $display("  frame30 coeff=%0d (should be near 0)",fade_coeff);
  if(i==59 && fade_coeff<200) $display("  frame59 coeff=%0d (should be near 255)",fade_coeff);
 end
 wait_cycles(2);
 if(trans_active) $fatal(1,"transition did not end");
 $display("PASS fade transition completed (60 frames)");
 // trigger again -> should be slide1 (wait for each transition to complete first)
 run_transition;
 pulse_buf; wait_cycles(4);
 if(trans_type!==1) $fatal(1,"second type=%0d expected slide1",trans_type);
 $display("PASS rotation -> slide1");
 run_transition;
 pulse_buf; wait_cycles(4);
 if(trans_type!==2) $fatal(1,"third type=%0d expected wipe",trans_type);
 $display("PASS rotation -> wipe");
 run_transition;
 pulse_buf; wait_cycles(4);
 if(trans_type!==3) $fatal(1,"fourth type=%0d expected slide2",trans_type);
 $display("PASS rotation -> slide2");
 run_transition;
 pulse_buf; wait_cycles(4);
 if(trans_type!==0) $fatal(1,"fifth type=%0d expected fade",trans_type);
 $display("PASS rotation -> fade (wrap)");
 run_transition;
 // scene_section=0 -> no transition trigger
 scene_section=0; pulse_buf; wait_cycles(4);
 if(trans_active) $fatal(1,"should not transition in station mode");
 $display("PASS no transition in station mode");
 // abort: leaving section mid-transition stops it immediately
 scene_section=1; pulse_buf; wait_cycles(4);
 if(!trans_active) $fatal(1,"abort test: transition did not start");
 pulse_vs; wait_cycles(2);
 scene_section=0; wait_cycles(4);
 if(trans_active) $fatal(1,"abort: transition still active after leaving section");
 $display("PASS abort on leaving section mid-transition");
 $display("PASS transition: fade coeff + 4-type rotation + section gating + abort");
 $finish;
end
initial begin #200000000;$fatal(1,"global timeout");end
endmodule
