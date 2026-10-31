`timescale 1ns/1ps
module tb_sd_arbiter;
reg clk=0;always #5 clk=~clk;
reg rst=1,image_read=0,audio_read=0;
reg [31:0] image_addr=0,audio_addr=0;
wire [7:0] image_data,audio_data;
wire image_valid,image_end,audio_valid,audio_end,sector_read;
wire [31:0] sector_addr;
reg [1:0] transport_state=0;
reg [2:0] byte_count=0;
reg [31:0] latched_addr=0;
wire sector_valid=(transport_state==1);
wire sector_end=(transport_state==2);
wire [7:0] sector_data=latched_addr[7:0]+byte_count;
wl_sd_arbiter dut(.*);
integer clock_count=0,last_end=-100,accepted=0,completed=0,bytes_seen=0;
reg expected_audio[0:7];reg [31:0] expected_addr[0:7];
reg drop_image=0,drop_audio=0;
reg [31:0] next_image_addr=0,next_audio_addr=0;
// Model the vendor READ -> READ_END -> WAIT_READ_WRITE states. Requests
// presented during READ_END must not start a duplicate transaction.
always @(posedge clk)begin
 clock_count=clock_count+1;
 if(rst)begin transport_state<=0;byte_count<=0;end
 else begin
  if(image_valid && audio_valid)$fatal(1,"data delivered to both clients");
  if(image_end && audio_end)$fatal(1,"end delivered to both clients");
  if(transport_state!=0 && sector_addr!==latched_addr)$fatal(1,"address changed within sector");
  if(sector_valid)begin
   if(image_valid!==!expected_audio[completed] || audio_valid!==expected_audio[completed])
    $fatal(1,"wrong data owner at transaction %0d",completed);
   if((expected_audio[completed]?audio_data:image_data)!==sector_data)$fatal(1,"corrupt routed byte");
   bytes_seen=bytes_seen+1;
  end else if(image_valid || audio_valid)$fatal(1,"spurious valid");
  if(sector_end)begin
   if(image_end!==!expected_audio[completed] || audio_end!==expected_audio[completed])
    $fatal(1,"wrong completion owner");
   if(bytes_seen!=4)$fatal(1,"byte count %0d",bytes_seen);
   bytes_seen=0;completed=completed+1;last_end=clock_count;
  end else if(image_end || audio_end)$fatal(1,"spurious end");
  case(transport_state)
   0:if(sector_read)begin
    if(clock_count-last_end<3)$fatal(1,"missing two idle clocks");
    if(accepted>=8 || sector_addr!==expected_addr[accepted])
     $fatal(1,"unexpected sector %0d address %0d",accepted,sector_addr);
    latched_addr<=sector_addr;byte_count<=0;accepted=accepted+1;transport_state<=1;
   end
   1:if(byte_count==3)transport_state<=2;else byte_count<=byte_count+1'b1;
   2:transport_state<=0;
  endcase
  // Typical clients update read and the next address on their end edge.
  if(image_end)begin image_read<=!drop_image;image_addr<=next_image_addr;end
  if(audio_end)begin audio_read<=!drop_audio;audio_addr<=next_audio_addr;end
 end
end
task wait_done(input integer count);
 begin wait(completed==count);@(negedge clk);end
endtask
initial begin
 expected_audio[0]=1;expected_addr[0]=100;
 expected_audio[1]=0;expected_addr[1]=200;
 expected_audio[2]=1;expected_addr[2]=101;
 expected_audio[3]=1;expected_addr[3]=102;
 expected_audio[4]=0;expected_addr[4]=201;
 expected_audio[5]=0;expected_addr[5]=202;
 expected_audio[6]=1;expected_addr[6]=103;
 expected_audio[7]=0;expected_addr[7]=203;
 repeat(3)@(negedge clk);rst=0;
 // Simultaneous requests: audio wins; its req falls with NBA at end.
 image_read=1;image_addr=200;audio_read=1;audio_addr=100;
 drop_audio=1;drop_image=1;next_image_addr=201;
 wait_done(1);
 // Image starts next. Later audio arrival cannot preempt that sector.
 wait(accepted==2);@(negedge clk);
 image_addr=32'hdeadbeef;audio_addr=101;audio_read=1;
 drop_audio=0;next_audio_addr=102;
 wait_done(2);wait_done(3);
 // The audio client keeps req high and advances address on end.
 drop_audio=1;
 wait_done(4);
 // A sustained image request can also advance at end, without duplicates.
 image_read=1;image_addr=201;drop_image=0;next_image_addr=202;
 wait_done(5);drop_image=1;next_image_addr=203;
 wait_done(6);
 // One last simultaneous pair verifies arbitration after several gaps.
 image_read=1;image_addr=203;audio_read=1;audio_addr=103;
 drop_audio=1;drop_image=1;
 wait_done(8);
 repeat(10)@(negedge clk);
 if(accepted!=8 || completed!=8 || sector_read)$fatal(1,"duplicate or missing request");
 $display("PASS sd_arbiter: priority, nonpreemption, NBA request release, continuous requests, stable address and isolated streams");
 $finish;
end
initial begin #10000;$fatal(1,"arbiter timeout");end
endmodule
