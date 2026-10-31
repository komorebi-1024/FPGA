`timescale 1ns/1ps
module tb_music_pcm;
reg clk=0,rst=1,test_mode=0,arrival_event=0;
reg music_enable=1,music_ready=1,music_empty=0;
wire sample_valid,acr_valid,chime_active,music_pop,music_sample_valid,music_underrun;
wire [23:0] pcm_left,pcm_right;
wire [19:0] acr_cts,acr_n;
reg [31:0] words[0:3];
integer fifo_index=0,cycles=0,samples=0,acrs=0,pops=0,chime_samples=0;
wire [31:0] music_data=words[fifo_index%4];
always #5 clk=~clk;
// Ten clocks per sample keeps the full 19200-sample chime inexpensive to test.
wl_pcm_audio #(.CLK_HZ(480000),.SAMPLE_HZ(48000)) dut(
 .clk(clk),.rst(rst),.test_mode(test_mode),.arrival_event(arrival_event),
 .sample_valid(sample_valid),.pcm_left(pcm_left),.pcm_right(pcm_right),
 .acr_valid(acr_valid),.acr_cts(acr_cts),.acr_n(acr_n),.chime_active(chime_active),
 .music_enable(music_enable),.music_ready(music_ready),.music_empty(music_empty),.music_data(music_data),
 .music_pop(music_pop),.music_sample_valid(music_sample_valid),.music_underrun(music_underrun),.voice_enable(1'b0),.voice_ready(1'b0),.voice_empty(1'b1),.voice_data(32'd0),.voice_pop(),.voice_underrun());
reg pop_before,priority_before;
reg [31:0] expected_word;
always @(posedge clk)begin
 if(rst)begin cycles=0;samples=0;acrs=0;pops=0;fifo_index<=0;chime_samples=0;end
 else begin
  cycles=cycles+1;
  pop_before=music_pop;priority_before=test_mode || chime_active || arrival_event;
  expected_word=music_data;
  if(pop_before)begin
   if(cycles%10!=0)$fatal(1,"FIFO pop outside 48kHz sample boundary");
   if(!music_enable || !music_ready || music_empty || priority_before)$fatal(1,"Illegal FIFO consumption");
   fifo_index<=fifo_index+1;pops=pops+1;
  end
  #1;
  if(sample_valid!==(cycles%10==0))$fatal(1,"Sample clock stopped or changed during mode switch");
  if(music_sample_valid!==pop_before)$fatal(1,"PCM publication and FIFO consumption differ");
  if(sample_valid)begin
   samples=samples+1;
   if(pop_before)begin
    if(pcm_left!=={expected_word[15:0],8'h00} || pcm_right!=={expected_word[31:16],8'h00})
     $fatal(1,"Stereo sample order/sign/24-bit alignment mismatch");
   end else if(priority_before)begin
    if(pcm_left!==pcm_right)$fatal(1,"Test/chime priority must produce equal stereo channels");
    if(!test_mode)chime_samples=chime_samples+1;
   end else if(pcm_left!==0 || pcm_right!==0)$fatal(1,"Paused/unready/underrun output must be silent");
  end
  if(acr_valid)begin
   acrs=acrs+1;
   if(!sample_valid || samples%48!=0 || acr_n!=6144 || acr_cts!=480)$fatal(1,"ACR cadence/ratio changed");
  end
  if(acrs!=samples/48)$fatal(1,"Missing/extra ACR packet");
 end
end
task wait_cycles;
 input integer count;
 begin repeat(count)@(negedge clk);end
endtask
task wait_samples;
 input integer count;
 integer target;
 begin target=samples+count;while(samples<target)@(negedge clk);end
endtask
integer held_index,held_pops,held_chimes;
initial begin
 // Little-endian stereo framing: {right16,left16}, including full negative scale.
 words[0]=32'h7fff8000;words[1]=32'h0001ffff;
 words[2]=32'hfedc1234;words[3]=32'h80007fff;
 wait_cycles(4);rst=0;wait_samples(8);
 if(pops!=8)$fatal(1,"Music did not start");
 held_index=fifo_index;held_pops=pops;music_enable=0;wait_samples(20);
 if(fifo_index!=held_index || pops!=held_pops)$fatal(1,"Pause advanced FIFO position");
 if(music_underrun)$fatal(1,"Pause must not report underrun");
 music_enable=1;wait_samples(1);
 if(fifo_index!=held_index+1)$fatal(1,"Resume did not consume the retained next sample");
 held_index=fifo_index;music_ready=0;wait_samples(5);
 if(fifo_index!=held_index || music_underrun)$fatal(1,"Unready buffer must pause without underrun");
 music_ready=1;music_empty=1;wait_samples(5);
 if(fifo_index!=held_index || !music_underrun)$fatal(1,"Empty buffer must report underrun without consumption");
 music_empty=0;wait_samples(5);
 if(!music_underrun)$fatal(1,"Underrun diagnostic must remain latched until reset");
 held_index=fifo_index;test_mode=1;wait_samples(8);
 if(fifo_index!=held_index || pcm_left==0)$fatal(1,"Test tone did not override/pause music");
 test_mode=0;wait_samples(1);
 // Trigger between sample edges: full chime remains exactly 19200 samples.
 arrival_event=1;wait_cycles(1);arrival_event=0;
 held_index=fifo_index;held_chimes=chime_samples;
 while(chime_active)@(negedge clk);
 if(chime_samples-held_chimes!=19200)$fatal(1,"Chime sample duration changed: %0d",chime_samples-held_chimes);
 if(fifo_index!=held_index)$fatal(1,"Arrival chime consumed background music");
 wait_samples(1);
 if(fifo_index!=held_index+1)$fatal(1,"Music did not resume after chime");
 // Arrival coincident with a sample must prevent even one unwanted music pop.
 while(cycles%10!=9)@(negedge clk);
 held_index=fifo_index;arrival_event=1;wait_cycles(1);
 if(fifo_index!=held_index || music_sample_valid)$fatal(1,"Coincident arrival lost priority");
 arrival_event=0;wait_samples(1);
 if(acrs!=samples/48)$fatal(1,"ACR packet count mismatch");
 rst=1;wait_cycles(2);
 if(music_underrun || music_sample_valid || sample_valid)$fatal(1,"Reset did not clear music diagnostics/valids");
 $display("PASS music_pcm: signed stereo PCM, timed pop, pause/resume, unready/empty, priority, 19200-sample chime, ACR");
 $finish;
end
initial begin #5000000;$fatal(1,"Music PCM simulation timed out");end
endmodule
