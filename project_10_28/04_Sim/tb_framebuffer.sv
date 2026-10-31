`timescale 1ns/1ps
module tb_framebuffer;
reg clk=0;always #10 clk=~clk;
reg rst=1,wr=0,rd=0;reg[1:0] bank=0;
wire wack,wfinish,wbusy,we,wclr,rack,rfinish,rbusy,re,rclr;
wire[20:0] waddr,raddr;
integer wc=0,rc=0,expected_addr;reg watch=0;
frame_fifo_write #(.BURST_SIZE(256)) writer(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(rbusy),.O_wr_busy(wbusy),.App_wr_en(we),.App_wr_addr(waddr),.write_req(wr),.write_req_ack(wack),.write_finish(wfinish),.write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(bank),.write_len(21'd307200),.fifo_aclr(wclr),.rdusedw(10'd400));
frame_fifo_read #(.BURST_SIZE(256)) reader(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(wbusy),.O_rd_busy(rbusy),.App_rd_en(re),.App_rd_addr(raddr),.read_req(rd),.read_req_ack(rack),.read_finish(rfinish),.read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(bank),.read_len(21'd307200),.fifo_aclr(rclr),.wrusedw(10'd0),.trans_active(1'b0),.trans_type(2'd0),.trans_frame(6'd0));
always @(posedge clk) if(watch)begin
 if(we)begin
  expected_addr=bank*307200+(479-wc/640)*640+wc%640;
  if(waddr!==expected_addr)$fatal(1,"flip address %d got %d expected %d",wc,waddr,expected_addr);
  wc=wc+1;
 end
 if(re)begin if(raddr!==bank*307200+rc)$fatal(1,"read address %d got %h",rc,raddr);rc=rc+1;end
 if(we && re)$fatal(1,"read/write command collision");
end
initial begin
 repeat(4)@(negedge clk);rst=0;watch=1;
 for(integer b=0;b<2;b=b+1)begin
  bank=b;wc=0;rc=0;wr=1;rd=1;
  fork
   begin wait(wack);@(negedge clk);wr=0;wait(wfinish);@(negedge clk);if(wc!=307200)$fatal(1,"write count %d",wc);end
   begin wait(rack);@(negedge clk);rd=0;wait(rfinish);@(negedge clk);if(rc!=307200)$fatal(1,"read count %d",rc);end
  join
  repeat(10)@(negedge clk);
 end
 $display("PASS framebuffer: both full buffers, 614400 vertically flipped write addresses, 614400 sequential read addresses, burst arbitration");$finish;
end
initial begin #100000000;$fatal(1,"framebuffer timeout");end
endmodule
