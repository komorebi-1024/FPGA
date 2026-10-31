// Dual-clock stereo PCM FIFO. Gray pointers cross through two flip-flops.
// Synchronous RAM read prefetches the current head every read clock. Consumers
// must leave one read clock between pops (48 kHz PCM has >500 clocks available).
module wl_audio_fifo #(
 parameter integer ADDR_BITS=10
)(
 input wire wr_clk,input wire wr_rst,input wire wr_en,input wire [31:0] wr_data,
 output wire wr_full,output wire [ADDR_BITS:0] wr_level,
 input wire rd_clk,input wire rd_rst,input wire rd_en,
 output reg [31:0] rd_data,output wire rd_empty
);
localparam integer DEPTH=1<<ADDR_BITS;
(* ram_style="block" *) reg [31:0] memory[0:DEPTH-1];
reg [ADDR_BITS:0] wr_bin,wr_gray,rd_bin,rd_gray;
(* async_reg="true" *) reg [ADDR_BITS:0] rd_gray_meta,rd_gray_sync;
(* async_reg="true" *) reg [ADDR_BITS:0] wr_gray_meta,wr_gray_sync;
function [ADDR_BITS:0] ungray;
 input [ADDR_BITS:0] value;
 integer b;
 begin
  ungray[ADDR_BITS]=value[ADDR_BITS];
  for(b=ADDR_BITS-1;b>=0;b=b-1)ungray[b]=ungray[b+1]^value[b];
 end
endfunction
assign wr_full=(wr_gray=={~rd_gray_sync[ADDR_BITS:ADDR_BITS-1],rd_gray_sync[ADDR_BITS-2:0]});
assign wr_level=wr_bin-ungray(rd_gray_sync);
assign rd_empty=(rd_gray==wr_gray_sync);
always @(posedge wr_clk)if(wr_en && !wr_full)memory[wr_bin[ADDR_BITS-1:0]]<=wr_data;
always @(posedge rd_clk)rd_data<=memory[rd_bin[ADDR_BITS-1:0]];
always @(posedge wr_clk or posedge wr_rst)begin
 if(wr_rst)begin wr_bin<=0;wr_gray<=0;rd_gray_meta<=0;rd_gray_sync<=0;end
 else begin
  rd_gray_meta<=rd_gray;rd_gray_sync<=rd_gray_meta;
  if(wr_en && !wr_full)begin
   wr_bin<=wr_bin+1'b1;wr_gray<=((wr_bin+1'b1)>>1)^(wr_bin+1'b1);
  end
 end
end
always @(posedge rd_clk or posedge rd_rst)begin
 if(rd_rst)begin rd_bin<=0;rd_gray<=0;wr_gray_meta<=0;wr_gray_sync<=0;end
 else begin
  wr_gray_meta<=wr_gray;wr_gray_sync<=wr_gray_meta;
  if(rd_en && !rd_empty)begin
   rd_bin<=rd_bin+1'b1;rd_gray<=((rd_bin+1'b1)>>1)^(rd_bin+1'b1);
  end
 end
end
endmodule
