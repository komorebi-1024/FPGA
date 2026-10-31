`timescale 1ns/1ps
module tb_key_gesture;
localparam integer STABLE=3,LONG=20;
reg clk=0;always #5 clk=~clk;
reg rst=1,key_n=1;
wire short_press,long_press;
integer short_count=0,long_count=0,i;
wl_key_gesture #(.STABLE_CYCLES(STABLE),.LONG_CYCLES(LONG)) dut(
 .clk(clk),.rst(rst),.key_n(key_n),.short_press(short_press),.long_press(long_press));
always @(posedge clk)begin
 #1;
 if(rst)begin short_count=0;long_count=0;end
 else begin
  if(short_press && long_press)$fatal(1,"simultaneous short and long events");
  if(short_press)short_count=short_count+1;
  if(long_press)long_count=long_count+1;
 end
end
task cycles(input integer n);begin repeat(n)begin @(posedge clk);#2;end end endtask
task drive(input reg value);begin @(negedge clk);key_n=value;end endtask
task check(input integer shorts,input integer longs);
 begin
  if(short_count!=shorts || long_count!=longs)
   $fatal(1,"gesture counts short=%0d long=%0d expected=%0d/%0d",short_count,long_count,shorts,longs);
 end
endtask
initial begin
 cycles(3);@(negedge clk);rst=0;
 cycles(10);check(0,0);
 // Sub-debounce press chatter must never become a gesture.
 drive(0);cycles(2);drive(1);cycles(2);drive(0);cycles(1);drive(1);
 cycles(10);check(0,0);
 // A short press fires only after a fully debounced release.
 drive(0);cycles(8);check(0,0);
 drive(1);cycles(2);check(0,0);
 drive(0);cycles(2);check(0,0);
 drive(1);cycles(STABLE+2);check(1,0);
 cycles(10);check(1,0);
 // Stable press acceptance takes two synchronizer cycles plus debounce.
 drive(0);
 for(i=1;i<=STABLE+2+LONG;i=i+1)begin
  cycles(1);
  if(i<STABLE+2+LONG)check(1,0);else check(1,1);
 end
 cycles(LONG*3);check(1,1);
 drive(1);cycles(2);drive(0);cycles(2);drive(1);
 cycles(STABLE+5);check(1,1);
 // The next short press is independent of the previous long press.
 drive(0);cycles(8);drive(1);cycles(STABLE+2);check(2,1);
 // Release accepted exactly at the long threshold must not emit a short.
 drive(0);cycles(STABLE+2+LONG-(STABLE+2));
 drive(1);cycles(STABLE+2);check(2,2);
 cycles(8);check(2,2);
 // Reset cancels a held key and restores a clean, released initial state.
 drive(0);cycles(8);@(negedge clk);rst=1;key_n=1;
 cycles(3);@(negedge clk);rst=0;cycles(10);check(0,0);
 drive(0);cycles(8);drive(1);cycles(STABLE+2);check(1,0);
 $display("PASS key gesture: debounce, release-only short, exact long threshold, single long, no release short, reset");
 $finish;
end
initial begin #20000;$fatal(1,"timeout");end
endmodule
