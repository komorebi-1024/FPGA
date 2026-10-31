`timescale 1ns/1ps
module tb_image_adjust;
reg clk=0;always #5 clk=~clk;
reg rst=1,hs=1,vs=1,de=0;
reg [23:0] rgb=0;
reg [8:0] config_data=9'b0_00_010_010;
reg config_toggle=0;
wire ho,vo,dout,config_ack;wire [23:0] out;wire [8:0] frame_config;
wl_image_adjust dut(clk,rst,hs,vs,de,rgb,config_data,config_toggle,ho,vo,dout,out,frame_config,config_ack);
integer model_b=2,model_c=2;
reg [8:0] model_config=9'b0_00_010_010;
reg [23:0] expected_rgb[0:2];
reg expected_hs[0:2],expected_vs[0:2],expected_de[0:2];
reg [2:0] valid=0;
integer q,compared=0;
function [7:0] reference_channel;
 input integer channel;
 input integer brightness;
 input integer contrast;
 integer value;
 begin
  // Independent full-width multiply/reference, rather than the DUT shift cases.
  value=(((channel-128)*(contrast+2)+2)>>>2)+128+(brightness-2)*32;
  if(value<0)reference_channel=0;
  else if(value>255)reference_channel=255;
  else reference_channel=value;
 end
endfunction
always @(posedge clk)begin
 if(rst)valid<=0;
 else begin
  for(q=2;q>0;q=q-1)begin
   expected_rgb[q]<=expected_rgb[q-1];expected_hs[q]<=expected_hs[q-1];
   expected_vs[q]<=expected_vs[q-1];expected_de[q]<=expected_de[q-1];
  end
  expected_rgb[0]<={reference_channel(rgb[23:16],model_b,model_c),
                    reference_channel(rgb[15:8],model_b,model_c),
                    reference_channel(rgb[7:0],model_b,model_c)};
  expected_hs[0]<=hs;expected_vs[0]<=vs;expected_de[0]<=de;
  valid<={valid[1:0],1'b1};
  #1;
  if(valid[2])begin
   if(out!==expected_rgb[2])$fatal(1,"RGB b=%0d c=%0d got=%h expected=%h",model_b,model_c,out,expected_rgb[2]);
   if({ho,vo,dout}!=={expected_hs[2],expected_vs[2],expected_de[2]})
    $fatal(1,"sync/DE did not follow exact three-stage RGB pipeline");
   compared=compared+1;
  end
 end
end
task cycles(input integer count);begin repeat(count)@(negedge clk);end endtask
task send_config(input [8:0] value);
 begin
  config_data=value;config_toggle=~config_toggle;cycles(8);
  if(frame_config!==model_config)$fatal(1,"configuration changed in the middle of a frame");
 end
endtask
task start_frame(input [8:0] value);
 begin
  model_config=value;model_b=value[5:3];model_c=value[2:0];vs=0;
  cycles(1);
  if(frame_config!==value)$fatal(1,"new frame did not apply latest stable configuration");
  vs=1;cycles(1);
 end
endtask
integer b,c,v,k,random_value;
reg [8:0] setting;
initial begin
 cycles(4);rst=0;
 // Startup is bit-exact with no configuration event at all.
 for(v=0;v<256;v=v+1)begin rgb={v[7:0],v[7:0],v[7:0]};de=1;cycles(1);end
 for(b=0;b<5;b=b+1)for(c=0;c<5;c=c+1)begin
  setting={1'b1,c[1:0],b[2:0],c[2:0]};
  send_config(setting);start_frame(setting);
  for(v=0;v<256;v=v+1)begin
   rgb={v[7:0],v[7:0],v[7:0]};hs=(v%12)!=0;de=(v%9)!=0;cycles(1);
  end
  for(k=0;k<64;k=k+1)begin random_value=$random;rgb=random_value[23:0];hs=k[0];de=k[1];cycles(1);end
 end
 // Several completed source events before VS: apply the latest, never a mixture.
 send_config(9'b1_00_000_100);
 send_config(9'b1_01_100_000);
 start_frame(9'b1_01_100_000);
 cycles(6);
 // Unsupported levels fall back to neutral; UI bits remain intact.
 send_config(9'b1_10_111_101);start_frame(9'b1_10_010_010);
 for(v=0;v<256;v=v+1)begin rgb={v[7:0],(8'd255-v[7:0]),v[7:0]};de=1;cycles(1);end
 // A fresh source event coincident with VS must wait for a later frame.
 config_data=9'b0_11_000_000;config_toggle=~config_toggle;
 start_frame(9'b1_10_010_010);cycles(8);
 if(frame_config!==9'b1_10_010_010)$fatal(1,"new event escaped frame latch");
 start_frame(9'b0_11_000_000);cycles(4);
 // Reset restores a neutral frame even after a non-default frame configuration.
 rst=1;cycles(3);rgb=24'h0a80f0;hs=1;vs=1;de=1;
 config_data=9'b0_00_010_010;config_toggle=0;
 model_b=2;model_c=2;model_config=9'b0_00_010_010;rst=0;cycles(10);
 if(frame_config!==model_config)$fatal(1,"reset did not restore defaults");
 $display("PASS image adjust: 256 values x 25 settings, random RGB, clamps, neutral identity, three-stage sync/blanking, frame-only updates and reset; %0d samples compared",compared);
 $finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
