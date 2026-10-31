`timescale 1ns/1ps
module tb_station_departure;
reg clk=0;always #5 clk=~clk;
reg rst=1,in_station=0,complete=0;
wire depart;
wl_station_departure #(.HOLD_CYCLES(30)) dut(clk,rst,in_station,complete,depart);
task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
initial begin
 cycles(3);rst=0;in_station=1;
 cycles(100);if(depart!==0)$fatal(1,"departed during narration/boot wait");
 complete=1;cycles(29);if(depart!==0)$fatal(1,"departed before final hold elapsed");
 cycles(1);if(depart!==1)$fatal(1,"no departure after exact hold");
 cycles(90);if(depart!==1)$fatal(1,"retriggered while completion stayed high");
 // Manual departure cancels the timer and preserves the toggle for CDC.
 in_station=0;complete=0;cycles(3);in_station=1;complete=1;
 cycles(15);in_station=0;complete=0;cycles(40);
 if(depart!==1)$fatal(1,"cancelled departure leaked into section");
 in_station=1;cycles(50);if(depart!==1)$fatal(1,"previous station completion leaked");
 complete=1;cycles(30);if(depart!==0)$fatal(1,"second station did not depart");
 rst=1;cycles(2);rst=0;complete=0;cycles(50);
 if(depart!==0)$fatal(1,"reset left pending departure");
 $display("PASS station departure: waits for narration, exact post-roll, single event, manual cancel and reset");$finish;
end
initial begin #20000;$fatal(1,"timeout");end
endmodule
