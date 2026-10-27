`timescale 1ns/1ps
module tb_status;
reg clk=0;always #5 clk=~clk;
reg rst=1;wire hs,vs,de;wire[23:0] rgb;
wl_osd #(.CLK_HZ(10),.CAPTION_FILE("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/captions.hex"),.FONT_FILE("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/ascii_font.hex")) dut(clk,rst,1'b1,1'b1,1'b0,24'd0,2'd0,1'b0,1'b1,4'd3,hs,vs,de,rgb);
initial begin
 repeat(4)@(negedge clk);rst=0;
 repeat(600)@(negedge clk);if({dut.mt,dut.mu,dut.st,dut.su}!==16'h0100)$fatal(1,"minute carry");
 repeat(59400)@(negedge clk);if({dut.mt,dut.mu,dut.st,dut.su}!==0)$fatal(1,"99:59 wrap");
 $display("PASS status: 00:59 to 01:00, 99:59 to 00:00 at configured clock rate");$finish;
end
endmodule
