`timescale 1ns/1ps
module tb_media;
reg clk=0;always #5 clk=~clk;
reg rst=1,ready=0,valid=0,secend=0,start=0,wack=0;
reg[7:0] data=0;reg[4:0] id=0;
wire req,cat,error,idle,done,wreq,pvalid;wire[31:0] addr;wire[23:0] pixel;wire[3:0] status;
wl_media_reader #(.TIMEOUT_CYCLES(3000)) dut(clk,rst,ready,req,addr,data,valid,secend,cat,error,status,start,id,idle,done,wreq,wack,pvalid,pixel);
reg[7:0] sector[0:511],expected[0:921653];
integer fd,ef,n,k,rc,pixels=0,mode=0,which=0;
integer iv,jj;string fname[0:23];
reg monitor=0;reg[23:0] want;
initial begin
 fd=$fopen("../01_Assets/WestLake_TF_128MiB.img","rb");if(!fd)$fatal(1,"disk open");
 forever begin
  @(negedge clk);
  if(req && !rst) begin
   if(mode==3) begin wait(!req || rst);end
   else begin
    rc=$fseek(fd,addr*512,0);rc=$fread(sector,fd);if(rc!=512)$fatal(1,"short sector");
    if(mode==1 && addr==2056)sector[0]=0;
    if(mode==2 && addr==11549)sector[28]=16;
    for(n=0;n<512;n=n+1)begin
     @(negedge clk);data=sector[n];valid=1;
     @(negedge clk);valid=0;
     if(n%37==0)repeat(2)@(negedge clk);
    end
    @(negedge clk);secend=1;@(negedge clk);secend=0;
    wait(!req); // transport does not re-accept a request until deasserted
   end
  end
 end
end
initial forever begin
 @(negedge clk);
 if(wreq && mode!=4)begin repeat(4)@(negedge clk);wack=1;wait(!wreq);repeat(3)@(negedge clk);wack=0;end
end
always @(posedge clk)begin
 #1;
 if(monitor && pvalid)begin
  want={expected[54+pixels*3+2],expected[54+pixels*3+1],expected[54+pixels*3]};
  if(pixel!==want)$fatal(1,"pixel %0d actual %h expected %h",pixels,pixel,want);
  pixels=pixels+1;if(pixels>307200)$fatal(1,"extra pixels");
 end
end
task reset;
begin @(negedge clk);rst=1;ready=0;start=0;monitor=0;repeat(8)@(negedge clk);rst=0;ready=1;end
endtask
initial begin
 reset();wait(cat);if(error)$fatal(1,"catalog rejected");
 for(k=0;k<4;k=k+1)begin
  case(k)
   0:fname[k]="../01_Assets/TF_BMP/01_duanqiao.bmp";
   1:fname[k]="../01_Assets/TF_BMP/02_yongjinmen.bmp";
   2:fname[k]="../01_Assets/TF_BMP/03_leifeng.bmp";
   3:fname[k]="../01_Assets/TF_BMP/04_yuemiao.bmp";
  endcase
 end
 for(iv=0;iv<4;iv=iv+1)for(jj=0;jj<5;jj=jj+1)
  fname[4+iv*5+jj]=$sformatf("../01_Assets/TF_BMP/promo_%0d_%0d.bmp",iv,jj);
 for(k=0;k<24;k=k+1)begin
  ef=$fopen(fname[k],"rb");
  rc=$fread(expected,ef);$fclose(ef);if(rc!=921654)$fatal(1,"expected file %0d",k);
  @(negedge clk);pixels=0;monitor=1;id=k;start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);if(error||pixels!=307200)$fatal(1,"load incomplete %d",pixels);
  monitor=0;$display("PASS image %0d: all 307200 RGB pixels",k);repeat(5)@(negedge clk);
 end
 mode=1;reset();wait(error);if(status!=14)$fatal(1,"bad catalog status");
 mode=2;reset();wait(error);if(status!=13||cat)$fatal(1,"fourth header validation");
 mode=3;reset();wait(error);if(status!=12)$fatal(1,"read timeout");
 mode=0;reset();wait(cat);mode=4;
 @(negedge clk);start=1;@(negedge clk);start=0;wait(error);if(status!=12)$fatal(1,"write ack timeout");
 $display("PASS media: bad catalog, bad fourth BMP, read timeout, write timeout");$finish;
end
initial begin #3000000000;$fatal(1,"global timeout");end
endmodule
