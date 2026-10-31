// One SD sector is indivisible. Audio has priority only between sectors.
// Clients hold read/address until their end pulse, then may request again.
// The two idle clocks let the transport leave READ_END and let clients update
// their requests with nonblocking assignments before the next arbitration.
module wl_sd_arbiter(
 input wire clk,input wire rst,
 input wire image_read,input wire [31:0] image_addr,
 output wire [7:0] image_data,output wire image_valid,output wire image_end,
 input wire audio_read,input wire [31:0] audio_addr,
 output wire [7:0] audio_data,output wire audio_valid,output wire audio_end,
 output reg sector_read,output reg [31:0] sector_addr,
 input wire [7:0] sector_data,input wire sector_valid,input wire sector_end
);
reg owner_audio;
reg [1:0] idle_clocks;
assign image_valid=sector_read && !owner_audio && sector_valid;
assign image_end=sector_read && !owner_audio && sector_end;
assign image_data=image_valid?sector_data:8'd0;
assign audio_valid=sector_read && owner_audio && sector_valid;
assign audio_end=sector_read && owner_audio && sector_end;
assign audio_data=audio_valid?sector_data:8'd0;
always @(posedge clk or posedge rst)begin
 if(rst)begin sector_read<=0;sector_addr<=0;owner_audio<=0;idle_clocks<=0;end
 else if(sector_read)begin
  if(sector_end)begin sector_read<=0;idle_clocks<=2;end
 end else if(idle_clocks!=0)idle_clocks<=idle_clocks-1'b1;
 else if(audio_read)begin sector_read<=1;sector_addr<=audio_addr;owner_audio<=1;end
 else if(image_read)begin sector_read<=1;sector_addr<=image_addr;owner_audio<=0;end
end
endmodule
