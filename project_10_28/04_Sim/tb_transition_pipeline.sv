`timescale 1ns/1ps
// Real control path: publication -> display bank -> transition -> SDRAM addresses.
// VS is active low, like the 640x480 timing source. Memory reads start on its
// falling edge; transition frames advance on its rising edge (two lines later).
module tb_transition_pipeline;
reg vc=0,mc=0;always #20 vc=~vc;always #10 mc=~mc;
reg rst=1,vs=1,treq=0,pub=0,kind=1,section=0;
reg [1:0] pbuf=0,pid=0;
wire tack,mreq,mack,ack,display_valid,arrival;
wire [1:0] bank,id;
reg [1:0] previous_bank;
wire image_ready=bank!=previous_bank;
always @(posedge vc or posedge rst)
 if(rst)previous_bank<=0;else previous_bank<=bank;
wire active,done,read_old;
wire [1:0] typ;
wire [5:0] frame;
wire [7:0] fade;
wl_video_commit commit(vc,rst,treq,tack,mreq,mack,pub,pbuf,pid,kind,ack,bank,id,display_valid,arrival);
wl_transition_ctrl #(.COOLDOWN_CLKS(0)) tc(
 .clk(vc),.rst(rst),.vs(vs),.image_ready(image_ready),.in_section(section),
 .trans_active(active),.trans_type(typ),.trans_frame(frame),.fade_coeff(fade),
 .read_old(read_old),.trans_done(done));
wire re,rfinish,rbusy,clr;
wire [20:0] raddr;
frame_fifo_read #(.BURST_SIZE(16)) reader(
 .rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.O_rd_busy(rbusy),.App_rd_en(re),.App_rd_addr(raddr),
 .read_req(mreq),.read_req_ack(mack),.read_finish(rfinish),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_addr_index(bank),.read_len(21'd256),.fifo_aclr(clr),.wrusedw(10'd0),
 .trans_active(active),.trans_type(typ),.trans_frame(frame));

integer count=0,expected_bank=0,frames_checked=0;
reg watch=0,check_fade=0;
always @(posedge mc)if(watch && re)begin
 if(check_fade && raddr!==expected_bank*307200+count)
  $fatal(1,"premature/wrong image: newbank=%d frame=%d fade=%d pixel=%d actual=%d expected bank=%d addr=%d",
         bank,frame,fade,count,raddr,expected_bank,expected_bank*307200+count);
 if(raddr>=614400)$fatal(1,"out of framebuffer range");
 count=count+1;
end

task video_frame;
 input integer want_transition;
 integer watchdog;
 begin
  // Falling VS edge is the actual frame-fetch launch in video_timing_data.
  @(negedge vc);vs=0;treq=1;count=0;watch=1;
  watchdog=0;
  while(!tack)begin @(negedge vc);watchdog=watchdog+1;if(watchdog>100)$fatal(1,"commit timeout");end
  treq=0;
  // The controller starts before the memory request is accepted. Inspect both
  // target directions, rather than accidentally treating every nonzero bank as 1.
  if(want_transition && !active)$fatal(1,"transition started after frame fetch");
  check_fade=!want_transition || typ==0;
  expected_bank=(active && typ==0 && frame<30)?(bank^1):bank;
  // 1600 video clocks = the two-line VS pulse in the real 800-pixel timing.
  repeat(1600-watchdog)@(negedge vc);
  if(!rfinish)begin
   // read_finish is a pulse, so address counting supplies completion evidence.
   if(count!=256)$fatal(1,"frame read count=%d",count);
  end
  watch=0;check_fade=0;frames_checked=frames_checked+1;
  vs=1;repeat(8)@(negedge vc);
 end
endtask

task publish;
 input integer nextbank;
 input integer is_station;
 begin
  @(negedge vc);pbuf=nextbank;kind=is_station;pub=~pub;
  repeat(8)@(negedge vc);
 end
endtask

integer transition,index;
initial begin
 repeat(6)@(negedge vc);rst=0;
 publish(0,1);video_frame(0);
 if(!display_valid || bank!=0)$fatal(1,"initial station publish");
 section=1;
 // First and fifth transitions are fades and run in opposite bank directions.
 for(transition=0;transition<5;transition=transition+1)begin
  publish(bank^1,0);
  video_frame(1);
  if(typ!==transition%4)$fatal(1,"effect rotation");
  if(typ==0 && fade>=255)$display("fade start bank=%d old=%d",bank,bank^1);
  for(index=1;index<60;index=index+1)video_frame(1);
  // End event occurs on the preceding rising VS. The next complete fetch is new.
  video_frame(0);
  if(active)$fatal(1,"transition did not finish");
  // Four effect types would otherwise make every fade use the same bank parity.
  // Insert an ordinary station publication, which must not advance effect type,
  // so the fifth transition is a fade in the opposite physical bank direction.
  if(transition==3)begin
   section=0;publish(bank^1,1);video_frame(0);section=1;
  end
 end
 // A station must publish immediately and must not inherit a promo transition.
 section=0;publish(bank^1,1);video_frame(0);
 if(active)$fatal(1,"station transition");
 $display("PASS transition pipeline: %d frames; real VS phases, commit handoff, both fade bank directions and SDRAM addresses",frames_checked);
 $finish;
end
initial begin #100000000;$fatal(1,"pipeline timeout");end
endmodule
