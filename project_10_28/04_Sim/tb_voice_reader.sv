`timescale 1ns/1ps
module tb_voice_reader;
reg clk=0;always #5 clk=~clk;
reg rst=1,sd_ready=0,start_toggle=0,stop=1;
reg [1:0] station=0;
wire req,wr,flush,ack,ready,catalog,error;
wire [31:0] addr,wd,total,c1,c2;wire [14:0] chars;
reg [7:0] data=0;reg valid=0,secend=0;
reg [9:0] level=0;wire full=level==512;
wl_voice_reader dut(
 .clk(clk),.rst(rst),.sd_ready(sd_ready),.start_toggle_async(start_toggle),.station_id_async(station),.stop_async(stop),
 .sector_read(req),.sector_addr(addr),.sector_data(data),.sector_valid(valid),.sector_end(secend),
 .fifo_level(level),.fifo_full(full),.fifo_write(wr),.fifo_data(wd),.fifo_flush(flush),
 .session_ack_toggle(ack),.buffer_ready(ready),.catalog_ready(catalog),.voice_error(error),
 .current_total_frames(total),.current_cue1(c1),.current_cue2(c2),.current_chars(chars));
reg [7:0] metadata[0:511];integer lengths[0:3];
integer written=0,consumed=0,all_writes=0,requests=0,payload_requests=0;
integer sd_byte=0,cycle=0,active_station=0;
reg consume=0,busy=0;
reg [31:0] transport_addr,word_value;
integer p,s,f,probe,k,mode,old_requests;
function [31:0] sample_word;
 input integer sid,n;
 reg [15:0] l,r;
 begin l=16'h1000+sid*1024+n;r=16'ha000+sid*1024+n;sample_word={r,l};end
endfunction
task put32;
 input integer offset;input [31:0] value;
 begin metadata[offset]=value[7:0];metadata[offset+1]=value[15:8];
  metadata[offset+2]=value[23:16];metadata[offset+3]=value[31:24];end
endtask
task make_catalog;
 integer n,base;reg [63:0] magic;
 begin
  for(n=0;n<512;n=n+1)metadata[n]=0;
  magic=64'h313030434f564c57;
  for(n=0;n<8;n=n+1)metadata[n]=magic[n*8 +:8];
  metadata[8]=4;metadata[9]=2;metadata[10]=16;metadata[11]=3;put32(12,48000);
  for(n=0;n<4;n=n+1)begin
   base=16+n*32;put32(base,10000+n*16);put32(base+4,lengths[n]);
   put32(base+8,lengths[n]/3);put32(base+12,lengths[n]*2/3);
   metadata[base+20]=10+n;metadata[base+21]=11+n;metadata[base+22]=12+n;
  end
 end
endtask
// Byte-valid gaps and end timing model the real client's held-request contract.
initial forever begin
 @(negedge clk);
 if(req && !rst)begin: transaction
  busy=1;transport_addr=addr;requests=requests+1;
  if(addr!=2058)payload_requests=payload_requests+1;
  for(p=0;p<512;p=p+1)begin
   if(rst)begin valid=0;secend=0;busy=0;disable transaction;end
   if(!req || addr!==transport_addr)$fatal(1,"request withdrawn or address changed inside sector");
   if(transport_addr==2058)data=metadata[p];
   else begin
    s=(transport_addr-10000)/16;f=(transport_addr-(10000+s*16))*128+p/4;
    if(s<0 || s>3)$fatal(1,"unexpected voice sector %d",transport_addr);
    word_value=sample_word(s,f);
    data=f<lengths[s] ? (word_value>>(p%4*8)) : 8'hef;
   end
   sd_byte=p;valid=1;@(negedge clk);valid=0;repeat(2)@(negedge clk);
  end
  secend=1;@(negedge clk);secend=0;busy=0;wait(!req || rst);
 end
end
// Independent FIFO occupancy model; every committed sample is checked in order.
always @(posedge clk or posedge flush)begin
 if(flush)begin level<=0;written<=0;consumed<=0;end
 else begin
  cycle=cycle+1;
  case(total)
   130:active_station=0;600:active_station=1;129:active_station=2;3:active_station=3;
   default:active_station=-1;
  endcase
  if(wr)begin
   if(active_station<0 || written>=lengths[active_station])$fatal(1,"extra voice data / invalid session");
   if(wd!==sample_word(active_station,written))
    $fatal(1,"voice byte order/session sid=%d frame=%d got=%h",active_station,written,wd);
   if(full)$fatal(1,"FIFO overflow");
   written<=written+1;all_writes=all_writes+1;
  end
  if(consume && level!=0)consumed<=consumed+1;
  case({wr,consume && level!=0})
   2'b10:level<=level+1'b1;
   2'b01:level<=level-1'b1;
  endcase
 end
end
task reset_reader;
 begin
  @(negedge clk);rst=1;sd_ready=0;stop=1;start_toggle=0;consume=0;
  repeat(8)@(negedge clk);rst=0;sd_ready=1;
  probe=0;while(!catalog)begin @(negedge clk);probe=probe+1;if(probe>20000)$fatal(1,"catalog timeout");end
 end
endtask
task command;
 input integer sid;
 begin
  @(negedge clk);station=sid;repeat(2)@(negedge clk);start_toggle=~start_toggle;
 end
endtask
task wait_session;
 input integer sid;
 integer steps;
 begin
  steps=0;
  while(flush || ack!==start_toggle || total!==lengths[sid])begin
   @(negedge clk);steps=steps+1;if(steps>20000)$fatal(1,"session timeout sid=%d",sid);
  end
  if(c1!==lengths[sid]/3 || c2!==lengths[sid]*2/3 ||
     chars!==((12+sid)*1024+(11+sid)*32+10+sid))$fatal(1,"cue/character payload");
 end
endtask
task play_whole;
 input integer sid;
 integer steps,at_end;
 begin
  command(sid);repeat(8)@(negedge clk);wait_session(sid);
  steps=0;
  while(!ready)begin @(negedge clk);steps=steps+1;if(steps>20000)$fatal(1,"ready timeout");end
  consume=1;steps=0;
  while(consumed!=lengths[sid])begin @(negedge clk);steps=steps+1;if(steps>50000)$fatal(1,"playback timeout");end
  consume=0;repeat(8)@(negedge clk);
  if(written!=lengths[sid] || level!=0 || error)$fatal(1,"wrong voice frame count");
  at_end=payload_requests;repeat(2000)@(negedge clk);
  if(payload_requests!=at_end)$fatal(1,"voice loops after EOF");
 end
endtask
initial begin
 lengths[0]=130;lengths[1]=600;lengths[2]=129;lengths[3]=3;
 make_catalog();reset_reader();if(error)$fatal(1,"valid catalog rejected");
 stop=0;repeat(5)@(negedge clk);
 for(k=0;k<4;k=k+1)play_whole(k);
 play_whole(0); // same station ID still restarts at PCM frame zero
 $display("PASS voice: four stations, exact partial EOF/no loop, same-station replay and cue metadata");

 // No consumption: prefetch stops above the low-water threshold (384 frames).
 command(1);repeat(8)@(negedge clk);wait_session(1);
 wait(level==384);old_requests=payload_requests;repeat(2000)@(negedge clk);
 if(payload_requests!=old_requests || !ready || full)$fatal(1,"watermark prefetch");
 consume=1;wait(consumed==600);consume=0;repeat(10)@(negedge clk);
 $display("PASS voice: 512-frame FIFO watermark without overflow");

 // Re-trigger while a sector is in flight: it must drain, discard and flush.
 command(1);repeat(8)@(negedge clk);wait_session(1);
 wait(busy && addr!=2058 && sd_byte>100 && sd_byte<200);
 command(2);repeat(8)@(negedge clk);
 if(!flush || ready || !req)$fatal(1,"inflight command did not flush/hold sector");
 wait_session(2);wait(written==129);if(error)$fatal(1,"switch error");

 // Two observed toggles during an old sector retain only the newest payload.
 command(1);repeat(8)@(negedge clk);wait_session(1);
 wait(busy && sd_byte>100 && sd_byte<200);command(0);
 repeat(12)@(negedge clk);command(3);repeat(8)@(negedge clk);
 wait_session(3);wait(written==3);if(error)$fatal(1,"latest command lost");

 // A start observed while stopped is consumed, not played later on stop release.
 command(1);repeat(8)@(negedge clk);wait_session(1);
 wait(busy && sd_byte>100 && sd_byte<200);stop=1;
 repeat(8)@(negedge clk);command(0);repeat(12)@(negedge clk);stop=0;
 wait(!busy);repeat(1000)@(negedge clk);old_requests=payload_requests;
 repeat(1000)@(negedge clk);
 if(!flush || ready || payload_requests!=old_requests)$fatal(1,"stopped command played late");
 // Flip back to the former token; it must still be treated as a fresh session.
 play_whole(2);
 $display("PASS voice: inflight restart, latest command, stop/start and toggle wrap");

 // Stop crosses the synchronizer exactly when FLUSH hands off to WAIT_DATA.
 // No orphan sector may launch while the cancellation overrides the FSM state.
 command(1);wait(dut.state==5 && dut.flush_count==62);@(negedge clk);stop=1;
 old_requests=payload_requests;repeat(100)@(negedge clk);
 if(req || busy || payload_requests!=old_requests || !flush)$fatal(1,"orphan request on FLUSH/WAIT_DATA cancellation");
 stop=0;repeat(5)@(negedge clk);play_whole(0);
 $display("PASS voice: cancellation on request-launch boundary");

 for(mode=0;mode<10;mode=mode+1)begin
  make_catalog();
  case(mode)
   0:metadata[0]=0;
   1:put32(12,44100);
   2:metadata[36]=0;
   3:metadata[36]=32;
   4:put32(24,0);
   5:put32(28,130);
   6:put32(16,2058);
   7:begin put32(20,32'hffffffff);put32(24,1);put32(28,2);end
   8:metadata[39]=1;
   9:metadata[8]=3;
  endcase
  reset_reader();if(!error || !flush || ready)$fatal(1,"bad metadata accepted mode=%d",mode);
  stop=0;repeat(4)@(negedge clk);command(1);repeat(100)@(negedge clk);
  if(req || wr || !flush)$fatal(1,"bad catalog requested data");
 end
 $display("PASS voice: malformed magic/rate/chars/cues/LBA/overflow/reserved/count rejected");
 $display("PASS voice reader: all scenarios; committed sample writes=%d",all_writes);$finish;
end
initial begin #10000000;$fatal(1,"voice reader timeout state=%d byte=%d",dut.state,sd_byte);end
endmodule
