`timescale 1ns/1ps
module tb_control;
reg sdclk=0,vclk=0;always #5 sdclk=~sdclk;always #17 vclk=~vclk;
reg rst=1,cat=0,err=0,reader_idle=1,source_done=0,wr_toggle=0;
reg next=0,autokey=0,audiokey=0;reg[1:0] sw=0;
wire load,pub,auto_on,testmode,busy,pack;wire[1:0] loadid,wbuf,pbuf,pid,displayed,rbuf,vid;
wire[3:0] dwell;wire[2:0] state;
reg treq=0,mack=0;wire tack,mreq,display_valid,arrival;
wl_playlist_ctrl #(.CLK_HZ(100),.TRANSFER_TIMEOUT(2000)) player(sdclk,rst,cat,err,reader_idle,source_done,wr_toggle,pack,next,autokey,audiokey,sw,load,loadid,wbuf,pub,pbuf,pid,auto_on,testmode,displayed,busy,dwell,state);
wl_video_commit commit(vclk,rst,treq,tack,mreq,mack,pub,pbuf,pid,pack,rbuf,vid,display_valid,arrival);
reg prevpub=0;integer i,loads=0,arrivals=0;
always @(posedge sdclk)begin #1;if(load)loads=loads+1;end
always @(posedge vclk)begin #1;if(arrival)arrivals=arrivals+1;end
task pulse_next;begin @(negedge sdclk);next=1;@(negedge sdclk);next=0;end endtask
task finish_source;begin @(negedge sdclk);source_done=1;@(negedge sdclk);source_done=0;end endtask
task finish_write;begin @(negedge sdclk);wr_toggle=~wr_toggle;repeat(5)@(negedge sdclk);end endtask
task frame_commit(input integer expectedid);
reg oldack;integer steps;
begin
 oldack=pack;repeat(5)@(negedge vclk);
 if(pack!==oldack)$fatal(1,"publication acknowledged without frame request");
 treq=1;@(negedge vclk);
 if(mreq)$fatal(1,"address not allowed to settle");
 wait(mreq);if(rbuf!=pbuf || vid!=expectedid)$fatal(1,"wrong frame payload");
 repeat(7)@(negedge vclk);if(pack!==oldack)$fatal(1,"ack before memory acceptance");
 mack=1;wait(tack);@(negedge vclk);treq=0;repeat(4)@(negedge vclk);mack=0;
 wait(state==3);repeat(5)@(negedge vclk);
 if(pack!=pub||displayed!=expectedid||!display_valid)$fatal(1,"publication failed");
end endtask
task finish_frame(input integer expectedid,input integer reverse);
begin
 prevpub=pub;
 if(reverse)begin finish_write();repeat(10)@(negedge sdclk);if(pub!=prevpub)$fatal(1,"published before source done");finish_source();end
 else begin finish_source();repeat(10)@(negedge sdclk);if(pub!=prevpub)$fatal(1,"published before SDRAM done");finish_write();end
 wait(state==2);frame_commit(expectedid);
end endtask
initial begin
 $dumpfile("control.vcd");$dumpvars(0,tb_control);
 repeat(5)@(negedge sdclk);rst=0;cat=1;wait(load);finish_frame(0,0);
 for(i=1;i<=4;i=i+1)begin
  pulse_next();wait(state==1);if(loadid!=(i%4)||wbuf==rbuf)$fatal(1,"overwrite front buffer");
  finish_frame(i%4,i%2);
 end
 if(loads!=5||arrivals!=5)$fatal(1,"route count");
 // Coalesce repeated presses while loading; one extra transfer follows acknowledgement.
 pulse_next();wait(state==1);pulse_next();pulse_next();
 finish_source();finish_write();wait(state==2);
 // Manually complete handshake, then the queued request can start immediately.
 repeat(5)@(negedge vclk);treq=1;wait(mreq);repeat(3)@(negedge vclk);mack=1;
 wait(tack);@(negedge vclk);treq=0;repeat(4)@(negedge vclk);mack=0;
 wait(state==1);if(loadid!=2)$fatal(1,"pending-next lost");finish_frame(2,1);
 // Select 10 s dwell on next commit and enable automatic playback.
 sw=3;pulse_next();wait(state==1);finish_frame(3,0);if(dwell!=10)$fatal(1,"switch period");
 @(negedge sdclk);autokey=1;@(negedge sdclk);autokey=0;
 repeat(990)@(negedge sdclk);if(state!=3)$fatal(1,"autoplay too early");
 wait(state==1);if(loadid!=0)$fatal(1,"auto wrap");finish_frame(0,0);
 // Manual always stops autoplay, audio button toggles independent of image loading.
 pulse_next();if(auto_on)$fatal(1,"manual did not pause");
 @(negedge sdclk);audiokey=1;@(negedge sdclk);audiokey=0;if(testmode)$fatal(1,"audio mode");
 wait(state==4);if(auto_on)$fatal(1,"timeout did not pause");
 $display("PASS control: route wrap, completion order, frame-boundary handoff, front-buffer protection, pending press, autoplay, 10 s switch, audio toggle, timeout");
 $finish;
end
initial begin #1000000;$fatal(1,"control timeout state=%d",state);end
endmodule
