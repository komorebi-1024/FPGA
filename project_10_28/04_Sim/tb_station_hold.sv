`timescale 1ns/1ps
module tb_station_hold;
reg clk=0;always #5 clk=~clk;
reg rst=1,advance=0,source=0,finish=0,ack=0;
wire load,pub,kind,mode,audio;wire [4:0] id;wire [1:0] wb,pb,pid;wire [3:0] dwell;wire [2:0] state;
wl_scene_ctrl #(.CLK_HZ(1000),.STATION_DWELL_MS(50),.PROMO_DWELL_MS(20),.AUTO_DEPART(0)) dut(
 clk,rst,1'b1,1'b0,1'b1,source,finish,ack,advance,1'b0,
 load,id,wb,pub,pb,pid,kind,mode,audio,dwell,state);
integer step=0,loads=0;reg busy=0;
always @(posedge clk)begin
 if(rst)begin step<=0;busy<=0;source<=0;finish<=0;ack<=0;loads<=0;end
 else begin
  ack<=pub;source<=0;
  if(load)begin busy<=1;step<=0;loads<=loads+1;end
  else if(busy)begin
   step<=step+1;
   if(step==2)source<=1;
   if(step==4)finish<=~finish;
   if(step==6)busy<=0;
  end
 end
end
task press;begin @(negedge clk);advance=1;@(negedge clk);advance=0;end endtask
integer before_count;
initial begin
 repeat(5)@(negedge clk);rst=0;
 wait(state==3);before_count=loads;
 repeat(500)@(negedge clk);
 if(state!=3 || loads!=before_count || !mode)$fatal(1,"station auto-departed before/full narration");
 press();wait(state==6);before_count=loads;
 repeat(160)@(negedge clk);
 if(loads<=before_count || mode)$fatal(1,"section autoplay stopped");
 press();wait(state==3);before_count=loads;
 repeat(500)@(negedge clk);
 if(state!=3 || loads!=before_count || !mode)$fatal(1,"second station auto-departed");
 press();wait(state==6);
 $display("PASS station hold: no timed departure, manual interrupt/depart, section autoplay and repeat arrivals");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
