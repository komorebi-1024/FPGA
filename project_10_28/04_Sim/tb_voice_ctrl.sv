`timescale 1ns/1ps
module tb_voice_ctrl;
reg clk=0;always #20 clk=~clk;
reg rst=1,arrival=0,in_station=1,ack=0,ready=1,error=0,catalog=1,fifo_reset=0,pop=0;
reg [1:0] station=0;
reg [31:0] total=30,cue1=10,cue2=22;
reg [14:0] chars={5'd5,5'd4,5'd3};
wire request,stop,play,active,session,done,complete,failed;
wire [1:0] requested_station,phase;wire [5:0] reveal;
wl_voice_ctrl #(.CLK_HZ(100),.WAIT_TIMEOUT_CYCLES(40)) dut(
 .clk(clk),.rst(rst),.arrival_event(arrival),.station_id(station),.in_station(in_station),
 .reader_ack_toggle_async(ack),.reader_ready_async(ready),.reader_error_async(error),
 .reader_catalog_ready_async(catalog),.voice_fifo_reset(fifo_reset),.voice_pop(pop),
 .current_total_frames_async(total),.current_cue1_async(cue1),.current_cue2_async(cue2),
 .current_chars_async(chars),.request_toggle(request),.request_station(requested_station),
 .stop_request(stop),.voice_play(play),.voice_active(active),.subtitle_phase(phase),
 .subtitle_reveal(reveal),.subtitle_session_toggle(session),.voice_done(done),
 .voice_complete(complete),.voice_error(failed));
integer i,expected_phase,expected_reveal,timeout;
reg previous_request;

task clocks(input integer n);repeat(n)@(negedge clk);endtask
task start_arrival;
 begin
  @(negedge clk);previous_request=request;arrival=1;pop=1;
  #1;if(play)$fatal(1,"arrival must inhibit old-session pop immediately");
  @(negedge clk);arrival=0;pop=0;
  if(request===previous_request || requested_station!==station || phase!=0 || reveal!=0 || complete || failed)
   $fatal(1,"arrival reset and request");
  if(!active || play || session!==request)$fatal(1,"pending state");
 end
endtask
task service_reader;
 begin
  // Even matching ack cannot accept the old session's sticky ready.
  ack=request;ready=1;clocks(7);
  if(play)$fatal(1,"accepted old ready before flush observation");
  fifo_reset=1;ready=0;clocks(6);
  if(play)$fatal(1,"played while reset asserted");
  fifo_reset=0;clocks(3);ready=1;
  timeout=0;while(!play)begin clocks(1);timeout=timeout+1;if(timeout>12)$fatal(1,"reader ready not accepted");end
  if(phase!=0 || reveal!=0)$fatal(1,"subtitle advanced without audio");
 end
endtask
task consume;
 input integer expected_count;
 begin
  @(negedge clk);pop=1;
  @(posedge clk);#1;
  if(expected_count<=10)begin expected_phase=0;expected_reveal=(expected_count*3+9)/10;end
  else if(expected_count<=22)begin expected_phase=1;expected_reveal=((expected_count-10)*4+11)/12;end
  else begin expected_phase=2;expected_reveal=((expected_count-22)*5+7)/8;end
  if(phase!==expected_phase || reveal!==expected_reveal)
   $fatal(1,"subtitle sample=%0d got=%0d/%0d expected=%0d/%0d",expected_count,phase,reveal,expected_phase,expected_reveal);
  if(expected_count<30 && (!play || done || complete))$fatal(1,"premature finish");
  if(expected_count==30 && (play || !done || !complete))$fatal(1,"exact finish");
  @(negedge clk);pop=0;
 end
endtask

initial begin
 clocks(5);rst=0;clocks(5);
 if(active || play || stop)$fatal(1,"initial idle");
 start_arrival();service_reader();
 for(i=1;i<=30;i=i+1)begin
  consume(i);
  if(i==10 || i==16)begin
   clocks(9);
   if(phase!==expected_phase || reveal!==expected_reveal || dut.played_count!=i)
    $fatal(1,"subtitle advanced during audio stall/priority pause");
  end
 end
 clocks(3);
 if(done || !complete || active || phase!=2 || reveal!=5)$fatal(1,"last subtitle must stay visible");
 // An arrival with an unchanged station ID is a fresh narration session.
 start_arrival();service_reader();
 for(i=1;i<=6;i=i+1)consume(i);
 in_station=0;#1;
 if(play || !stop || active)$fatal(1,"leave must cancel immediately");
 clocks(2);pop=1;clocks(2);pop=0;
 if(phase || reveal || failed || done || complete || dut.played_count)$fatal(1,"cancel state");
 // Metadata error is reported without blocking station operation.
 in_station=1;station=3;start_arrival();error=1;clocks(5);
 if(!failed || active || play || done || complete || phase!=1 || reveal!=32)$fatal(1,"catalog error fallback");
 error=0;clocks(4);
 // A good new arrival clears the old error and may run normally.
 start_arrival();service_reader();consume(1);
 in_station=0;clocks(2);in_station=1;
 // No reader acknowledgement/flush yields a bounded pending failure.
 start_arrival();clocks(45);
 if(!failed || active || play || reveal!=32)$fatal(1,"pending timeout");
 // Invalid metadata must never permit a zero-length/corrupt playback.
 total=20;cue1=10;cue2=22;
 start_arrival();ack=request;fifo_reset=1;ready=0;clocks(7);fifo_reset=0;clocks(3);ready=1;clocks(5);
 if(!failed || play || active)$fatal(1,"invalid metadata accepted");
 // Smallest legal segments exercise adjacent cue/EOF boundaries.
 total=3;cue1=1;cue2=2;chars={5'd1,5'd1,5'd1};
 start_arrival();service_reader();
 for(i=0;i<3;i=i+1)begin
  @(negedge clk);pop=1;@(posedge clk);#1;
  if(phase!==i || reveal!=1 || (i==2 && (!complete || !done || play)))
   $fatal(1,"one-sample sentence boundary i=%d phase=%d reveal=%d",i,phase,reveal);
  @(negedge clk);pop=0;
 end
 // Two fresh requests can return the toggle to a previously acknowledged value.
 // Matching stale ack/ready still cannot revive the previous FIFO session.
 total=30;cue1=10;cue2=22;chars={5'd5,5'd4,5'd3};
 start_arrival();start_arrival();clocks(8);
 if(play)$fatal(1,"two-request toggle wrap consumed stale ready");
 service_reader();consume(1);
 rst=1;clocks(2);
 if(request || play || active || phase || reveal || failed || complete || done)$fatal(1,"reset");
 $display("PASS voice control: epoch/flush handshake, exact pop-driven typewriter cues, stall, same-stop replay, cancel, EOF/error/timeout and reset");
 $finish;
end
initial begin #100000;$fatal(1,"test timeout");end
endmodule
