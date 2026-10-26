// Asynchronous assertion, three-cycle synchronous release in each destination.
module wl_reset_sync(input wire clk,input wire arst,output wire rst);
(* async_reg="true" *) reg [2:0] release_chain=3'b111;
always @(posedge clk or posedge arst)
 if(arst)release_chain<=3'b111;else release_chain<={release_chain[1:0],1'b0};
assign rst=release_chain[2];
endmodule
