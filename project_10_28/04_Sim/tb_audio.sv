`timescale 1ns/1ps
module tb_audio;
reg clk=0;always #1 clk=~clk;
reg rst=1,testmode=1,arrival=0;wire valid,acr,chime;wire[23:0] left,right;wire[19:0] cts,n;
wl_pcm_audio dut(.clk(clk),.rst(rst),.test_mode(testmode),.arrival_event(arrival),
 .sample_valid(valid),.pcm_left(left),.pcm_right(right),.acr_valid(acr),.acr_cts(cts),.acr_n(n),
 .chime_active(chime),.music_enable(1'b0),.music_ready(1'b0),.music_empty(1'b1),.music_data(32'd0),
 .music_pop(),.music_sample_valid(),.music_underrun(),.voice_enable(1'b0),.voice_ready(1'b0),.voice_empty(1'b1),.voice_data(32'd0),.voice_pop(),.voice_underrun());
integer k,samples=0,acrs=0,interval=0,lasttick=0;reg active=0;
always @(posedge clk)begin #0.1;if(active)begin
 interval=interval+1;
 if(valid)begin
  if(left!==right)$fatal(1,"stereo mismatch");
  if(samples>0 && interval-lasttick!=520 && interval-lasttick!=521)$fatal(1,"sample spacing");
  samples=samples+1;lasttick=interval;
 end
 if(acr)begin acrs=acrs+1;if(cts!=25000||n!=6144||!valid)$fatal(1,"ACR ratio");end
 end end
initial begin
 repeat(4)@(negedge clk);rst=0;active=1;
 repeat(25000000)@(negedge clk);
 if(samples!=48000||acrs!=1000)$fatal(1,"1 second counts %d %d",samples,acrs);
 $display("PASS audio: 25000000 clocks -> 48000 samples, 1000 ACR packets");active=0;
 testmode=0;repeat(600)@(negedge clk);if(left!=0||right!=0)$fatal(1,"not silent");
 arrival=1;@(negedge clk);arrival=0;samples=0;
 while(chime)begin @(posedge clk);#0.1;if(valid)samples=samples+1;end
 if(samples!=19200)$fatal(1,"chime duration %d",samples);
 repeat(600)@(negedge clk);if(left!=0)$fatal(1,"chime did not stop");
 $display("PASS audio: chime 19200 samples = 0.4 seconds, silence after completion");$finish;
end
initial begin #100000000;$fatal(1,"audio timeout");end
endmodule
