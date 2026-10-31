`timescale 1ns/1ps
module tb_osd;
reg clk=0;always #5 clk=~clk;
reg rst=1,hs=1,vs=1,de=0;reg[23:0] rgb=0;reg[1:0] station=0;
wire ho,vo,dout;wire[23:0] out;
wl_osd #(.CAPTION_FILE("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/captions.hex"),.FONT_FILE("../03_Project/WestLake_AV/src/user_source/hdl_source/westlake/ascii_font.hex"),.TYPE_CHAR_MS(1)) dut(clk,rst,hs,vs,de,rgb,station,1'b0,1'b1,4'd3,ho,vo,dout,out,2'd0,6'd0);
reg[23:0] source[0:307199],expected[0:307199];
integer st,x,y,count=0,fd;reg monitor=0;string filename;
always @(posedge clk)begin #1;
 if(monitor && dout)begin
  if(out!==expected[count])$fatal(1,"station %0d pixel %0d got %h expected %h",st,count,out,expected[count]);
  $fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);count=count+1;
 end
end
initial begin
 for(st=0;st<4;st=st+1)begin
  rst=1;monitor=0;de=0;vs=1;repeat(4)@(negedge clk);rst=0;station=st;
  repeat(1000000)@(negedge clk); // let typewriter fully reveal before capture
  filename=$sformatf("input_%0d.hex",st);$readmemh(filename,source);
  filename=$sformatf("expected_%0d.hex",st);$readmemh(filename,expected);
  filename=$sformatf("osd_rtl_%0d.rgb",st);fd=$fopen(filename,"wb");
  repeat(4)@(negedge clk);vs=0;repeat(3)@(negedge clk);vs=1;
  count=0;monitor=1;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin @(negedge clk);de=1;rgb=source[y*640+x];end
   @(negedge clk);de=0;repeat(160)@(negedge clk);
  end
  repeat(5)@(negedge clk);monitor=0;$fclose(fd);
  if(count!=307200)$fatal(1,"OSD count %d",count);
  $display("PASS OSD station %0d: 307200 pixels match independent software renderer",st);
 end
 $finish;
end
endmodule
