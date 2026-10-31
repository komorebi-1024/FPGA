`timescale 1ns/1ps
module tb_key;
reg clk=0;always #5 clk=~clk;
reg rst=1,keyn=1;wire press;integer presses=0;
wl_key_debounce #(.STABLE_CYCLES(8)) dut(clk,rst,keyn,press);
always @(posedge clk)begin #1;if(press)presses=presses+1;end
initial begin
 repeat(3)@(negedge clk);rst=0;
 keyn=0;repeat(2)@(negedge clk);keyn=1;repeat(3)@(negedge clk);keyn=0;
 repeat(30)@(negedge clk);if(presses!=1)$fatal(1,"bounce or hold counted wrong");
 keyn=1;repeat(20)@(negedge clk);keyn=0;repeat(20)@(negedge clk);
 if(presses!=2)$fatal(1,"second press missed");
 $display("PASS key: contact bounce rejected, long hold produces one event, second press accepted");$finish;
end
endmodule
