module wl_key_debounce #(
    parameter integer STABLE_CYCLES=2000000
)(input wire clk,input wire rst,input wire key_n,output reg press);
(* async_reg="true" *) reg [1:0] sync;
reg stable;
reg [31:0] count;
always @(posedge clk or posedge rst) begin
    if(rst) begin sync<=2'b11;stable<=1;count<=0;press<=0;end
    else begin
        sync<={sync[0],key_n};press<=0;
        if(sync[1]==stable) count<=0;
        else if(count>=STABLE_CYCLES-1) begin
            stable<=sync[1];count<=0;
            if(stable && !sync[1]) press<=1;
        end else count<=count+1'b1;
    end
end
endmodule
