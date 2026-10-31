`timescale 1ns/1ps
module tb_spectrum;
reg clk=0,rst=1,enable=0,sample_valid=0;
reg signed [15:0] sample_pcm=0;
wire [63:0] levels;
wire levels_valid,sample_overrun;
integer updates=0;
always #20 clk=~clk;
wl_audio_spectrum #(.DECAY_STEP(8)) dut(
 .clk(clk),.rst(rst),.enable(enable),.sample_valid(sample_valid),.sample_pcm(sample_pcm),
 .levels(levels),.levels_valid(levels_valid),.sample_overrun(sample_overrun));
always @(posedge clk)if(levels_valid)updates=updates+1;
task reset_analyzer;
 begin
  @(negedge clk);rst=1;enable=0;sample_valid=0;
  repeat(3)@(negedge clk);
  rst=0;enable=1;repeat(130)@(negedge clk);
 end
endtask
task frame;
 input integer tone_bin;
 input integer amplitude;
 integer n;
 real wave;
 begin
  for(n=0;n<256;n=n+1)begin
   wave=amplitude*$sin(6.283185307179586*tone_bin*n/256.0);
   sample_pcm=$rtoi(wave);sample_valid=1;
   @(negedge clk);sample_valid=0;
   repeat(519)@(negedge clk);
  end
 end
endtask
integer band,best,index,k,prior_updates;
integer tone_bins[0:7];
reg [7:0] old_level;
initial begin
 tone_bins[0]=1;tone_bins[1]=2;tone_bins[2]=5;tone_bins[3]=12;
 tone_bins[4]=24;tone_bins[5]=40;tone_bins[6]=64;tone_bins[7]=100;
 for(band=0;band<8;band=band+1)begin
  reset_analyzer();prior_updates=updates;frame(tone_bins[band],12000);
  if(updates!=prior_updates+1)$fatal(1,"Missing/duplicate frame publication");
  best=-1;index=-1;
  for(k=0;k<8;k=k+1)begin
   if(int'(levels[k*8 +:8])>best)begin best=levels[k*8 +:8];index=k;end
  end
  $display("tone bin=%0d expected band=%0d winner=%0d levels=%016h",tone_bins[band],band,index,levels);
  if(index!=band || best<32)$fatal(1,"Tone not localized in continuous frequency band");
  if(sample_overrun)$fatal(1,"Legal 520-clock sample interval flagged as overrun");
 end
 old_level=levels[63:56];frame(0,0);frame(0,0);
 if(levels[63:56]>=old_level)$fatal(1,"Silence did not release displayed level");
 @(negedge clk);enable=0;@(negedge clk);
 if(levels!=0)$fatal(1,"Disable must clear all bars");
 reset_analyzer();frame(0,0);
 if(levels!=0)$fatal(1,"Digital silence produced a frequency bar");
 // The throughput contract is checked explicitly, rather than silently dropping samples.
 sample_pcm=1000;sample_valid=1;@(negedge clk);sample_valid=0;
 repeat(10)@(negedge clk);sample_valid=1;@(negedge clk);sample_valid=0;
 repeat(2)@(negedge clk);
 if(!sample_overrun)$fatal(1,"Early sample must raise overrun");
 $display("PASS spectrum: all 8 bands, publication, silence/release, disable/reset and overrun");
 $finish;
end
initial begin #200000000;$fatal(1,"Spectrum simulation timed out");end
endmodule
