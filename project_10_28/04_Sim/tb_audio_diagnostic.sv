`timescale 1ns/1ps
module tb_audio_diagnostic;
reg clk=0;always #5 clk=~clk;
reg rst=1,test_mode=1,arrival=0,music_enable=0;
wire valid,acr,chime,pop,music_valid,underrun;
wire [23:0] left,right;wire [19:0] cts,n;
wl_pcm_audio #(.CLK_HZ(480000),.CHIME_SAMPLES(48000),.CHIME_SHIFT(7)) dut(
 .clk(clk),.rst(rst),.test_mode(test_mode),.arrival_event(arrival),
 .sample_valid(valid),.pcm_left(left),.pcm_right(right),.acr_valid(acr),.acr_cts(cts),.acr_n(n),.chime_active(chime),
 .music_enable(music_enable),.music_ready(1'b1),.music_empty(1'b0),.music_data(32'h34561234),
 .music_pop(pop),.music_sample_valid(music_valid),.music_underrun(underrun),.voice_enable(1'b0),.voice_ready(1'b0),.voice_empty(1'b1),.voice_data(32'd0),.voice_pop(),.voice_underrun());
integer samples=0,positive_crossings=0,maximum=-8388608,minimum=8388607;
integer chime_samples=0,first_note=0,second_note=0;
reg tick_before,pop_before;
reg signed [23:0] previous=0;
initial begin
 repeat(5)@(negedge clk);rst=0;
 while(samples<1024)begin
  @(posedge clk);#1;
  if(valid)begin
   if(left!==right || pop || music_valid || underrun)$fatal(1,"diagnostic routing");
   if($signed(left)>maximum)maximum=$signed(left);
   if($signed(left)<minimum)minimum=$signed(left);
   if(previous<0 && $signed(left)>=0)positive_crossings=positive_crossings+1;
   previous=left;samples=samples+1;
  end
 end
 if(maximum<2000000 || minimum> -2000000 || maximum>2097152 || minimum< -2097152)
  $fatal(1,"diagnostic amplitude min=%d max=%d",minimum,maximum);
 // 1024 samples at 48k are 21.33ms: approximately 9.39 periods of 440Hz.
 if(positive_crossings<9 || positive_crossings>10)$fatal(1,"tone frequency %d",positive_crossings);
 @(negedge clk);test_mode=0;repeat(12)@(negedge clk);
 if(left!=0 || right!=0)$fatal(1,"diagnostic did not stop");
 $display("PASS diagnostic: sustained 440Hz triangle, -12dBFS peak, no SD dependency, switch-off silence");
 // Trigger between sample ticks so the programmable countdown represents the
 // entire audible chime. The musical FIFO is ready to verify chime priority.
 @(negedge clk);while(dut.tick)@(negedge clk);
 music_enable=1;arrival=1;
 @(negedge clk);arrival=0;
 if(!chime || dut.chime_left!=48000)$fatal(1,"16-bit programmable countdown load");
 maximum=-8388608;minimum=8388607;
 while(chime)begin
  @(posedge clk);
  tick_before=dut.tick;pop_before=pop;
  if(tick_before)begin
   if(dut.phase_step==901)first_note=first_note+1;
   else if(dut.phase_step==1201)second_note=second_note+1;
   else $fatal(1,"unexpected arrival note");
  end
  #1;
  if(valid)begin
   if(left!==right || pop_before || music_valid)$fatal(1,"arrival priority over ready music");
   if($signed(left)>maximum)maximum=$signed(left);
   if($signed(left)<minimum)minimum=$signed(left);
   chime_samples=chime_samples+1;
  end
 end
 if(chime_samples!=48000 || first_note!=24000 || second_note!=24000)
  $fatal(1,"programmable chime count %d, notes %d/%d",chime_samples,first_note,second_note);
 if(maximum<2000000 || minimum> -2000000 || maximum>2097152 || minimum< -2097152)
  $fatal(1,"programmable chime amplitude min=%d max=%d",minimum,maximum);
 // No music is requested after completion: the next sample must be silent.
 @(negedge clk);music_enable=0;
 repeat(12)@(negedge clk);
 if(left!=0 || right!=0)$fatal(1,"programmable arrival did not end in silence");
 $display("PASS diagnostic: 48000-sample arrival, equal 24000-sample notes, -12dBFS peak, music priority and silence");$finish;
end
initial begin #6000000;$fatal(1,"timeout");end
endmodule
