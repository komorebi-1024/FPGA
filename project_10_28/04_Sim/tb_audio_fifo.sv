`timescale 1ns/1ps
module tb_audio_fifo;
reg wc=0,rc=0;always #5 wc=~wc;always #20 rc=~rc;
reg rst=1,we=0,re=0;reg [31:0] wd=0;
wire [31:0] q;wire full,empty;wire [4:0] level;
wl_audio_fifo #(.ADDR_BITS(4)) dut(wc,rst,we,wd,full,level,rc,rst,re,q,empty);
integer sent=0,got=0,k;
task push;
 begin
  @(negedge wc);while(full)@(negedge wc);
  wd=32'h12340000+sent;we=1;@(negedge wc);we=0;sent=sent+1;
 end
endtask
task pop;
 begin
  @(negedge rc);while(empty)@(negedge rc);
  if(q!==32'h12340000+got)$fatal(1,"FIFO order got=%d q=%h",got,q);
  re=1;@(negedge rc);re=0;got=got+1;
  // The synchronous prefetch contract requires a clock between reads.
  @(negedge rc);
 end
endtask
initial begin
 repeat(5)@(negedge rc);rst=0;
 for(k=0;k<16;k=k+1)push();
 repeat(5)@(negedge wc);
 if(!full || level!=16)$fatal(1,"full flag/level");
 // Writes while full cannot overwrite the oldest sample.
 we=1;wd=32'hdeadbeef;repeat(4)@(negedge wc);we=0;
 for(k=0;k<16;k=k+1)pop();
 repeat(5)@(negedge rc);if(!empty)$fatal(1,"empty flag");
 fork
  begin repeat(300)push();end
  begin repeat(300)pop();end
 join
 repeat(5)@(negedge rc);
 if(!empty || sent!=got)$fatal(1,"wrap accounting");
 rst=1;repeat(5)@(negedge rc);rst=0;
 repeat(5)@(negedge rc);if(!empty || level!=0)$fatal(1,"reset");
 $display("PASS audio FIFO: unrelated clocks, full protection, order, pointer wrap, reset");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
