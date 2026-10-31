`timescale 1ns/1ps
module tb_fade_lookup;
reg clk=0;always #5 clk=~clk;
reg rst=1;
wire active;wire [1:0] kind;wire [5:0] frame;wire [7:0] coeff;wire old,done;
wl_transition_ctrl dut(clk,rst,1'b0,1'b0,1'b0,active,kind,frame,coeff,old,done);
reg [1:0] tested_kind;
reg [5:0] tested_frame;
reg [7:0] expected;
integer t,f,checks=0;
initial begin
 repeat(3)@(negedge clk);
 // Freeze internal selector registers so all representable values are checked,
 // including frames 60..63 and their original eight-bit truncation behavior.
 force dut.trans_type=tested_kind;
 force dut.trans_frame=tested_frame;
 for(t=0;t<4;t=t+1)for(f=0;f<64;f=f+1)begin
  tested_kind=t;tested_frame=f;
  if(tested_kind==0)begin
   if(tested_frame<29)expected=(8'd255*(30-2-tested_frame))/(30-1);
   else expected=(8'd255*(tested_frame+1'b1-30))/(30-1);
  end else expected=255;
  #1;
  if(dut.fade_calc!==expected)
   $fatal(1,"fade LUT mismatch type=%0d frame=%0d got=%0d expected=%0d",t,f,dut.fade_calc,expected);
  checks=checks+1;
 end
 release dut.trans_type;release dut.trans_frame;
 if(checks!=256)$fatal(1,"lookup coverage");
 $display("PASS fade lookup: 4 types x 64 frames, eight-bit equality including unused frame values");$finish;
end
initial begin #10000;$fatal(1,"timeout");end
endmodule
