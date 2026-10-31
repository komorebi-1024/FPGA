`timescale 1ns/1ps
module tb_scene;
reg clk=0;always #5 clk=~clk;
reg rst=1,catalog=0,media_err=0,advance=0,audio=0;
reg source=0,wrfin=0,puback=0;
wire load_start,ptoggle,pkind,scene_mode,test_audio,idle;
wire[4:0] load_id;wire[1:0] wbuf,pbuffer,pid;wire[3:0] dwell;wire[2:0] state;
wl_scene_ctrl #(.CLK_HZ(1000),.STATION_DWELL_MS(50),.PROMO_DWELL_MS(10),.TRANSFER_TIMEOUT(1000000))
 dut(clk,rst,catalog,media_err,idle,source,wrfin,puback,advance,audio,
     load_start,load_id,wbuf,ptoggle,pbuffer,pid,pkind,scene_mode,test_audio,dwell,state);

// mock media + frame handshake: on load_start, pulse source_done then toggle write_finish
reg [3:0] loadcnt;reg busy;
always @(posedge clk)begin
 if(rst)begin busy<=0;loadcnt<=0;source<=0;wrfin<=0;end
 else begin
  source<=0;
  if(load_start)begin busy<=1;loadcnt<=0;end
  if(busy)begin
   if(loadcnt==3)source<=1;
   if(loadcnt==6)wrfin<=~wrfin;
   if(loadcnt==8)busy<=0;
   loadcnt<=loadcnt+1;
  end
 end
end
assign idle=~busy;
always @(posedge clk)if(rst)puback<=0;else puback<=ptoggle;

integer load_id_seen[0:63];integer nloads=0;
always @(posedge clk)if(load_start && !rst)begin
 load_id_seen[nloads]=load_id;nloads=nloads+1;
 $display("t=%0t LOAD id=%0d",$time,load_id);
end
integer pub_kind_seen[0:63];integer pub_id_seen[0:63];integer npubs=0;
reg pt_prev;
always @(posedge clk)begin
 if(rst)pt_prev<=0;
 else begin
  if(ptoggle!=pt_prev)begin
   pub_kind_seen[npubs]=pkind;pub_id_seen[npubs]=pid;npubs=npubs+1;
   $display("t=%0t PUB id=%0d kind=%b",$time,pid,pkind);
  end
  pt_prev<=ptoggle;
 end
end

task wait_state(input [2:0] s); while(state!==s)@(negedge clk); endtask
task pulse_advance; begin advance=1;@(negedge clk);advance=0; end endtask

initial begin
 integer k;
 rst=1;catalog=0;advance=0;repeat(8)@(negedge clk);rst=0;
 repeat(4)@(negedge clk);catalog=1;
 // station 0
 wait_state(3'd3); // STATION_HOLD
 if(load_id_seen[0]!==0)$fatal(1,"station0 load %0d",load_id_seen[0]);
 if(pub_kind_seen[0]!==1)$fatal(1,"station0 kind");
 $display("PASS station0 (load0, kind1)");
 // full cycle: advance through stations 1,2,3 and wrap back to 0
 for(k=1;k<=4;k=k+1)begin
  pulse_advance;wait_state(3'd6); // depart -> section
  pulse_advance;wait_state(3'd3); // arrive -> next station (wrap 3->0)
  if(k<=3 && load_id_seen[nloads-1]!==k)$fatal(1,"station%0d load %0d",k,load_id_seen[nloads-1]);
  if(k==4 && load_id_seen[nloads-1]!==0)$fatal(1,"WRAP load %0d expected 0",load_id_seen[nloads-1]);
  $display("cycle %0d: last load_id=%0d",k,load_id_seen[nloads-1]);
 end
 $display("PASS scene: full cycle + wrap (station3 -> station0 = load 0)");
 $finish;
end
initial begin #20000000;$fatal(1,"global timeout");end
endmodule
