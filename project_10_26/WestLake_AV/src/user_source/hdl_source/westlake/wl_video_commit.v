// A held payload and toggle cross from SD to video. Switch only at frame start.
// Delay the memory read request until the new buffer address is stable.
// Acknowledge publication only after the memory reader accepted the new frame.
module wl_video_commit(
    input wire clk, input wire rst,
    input wire timing_req, output wire timing_ack,
    output reg memory_req, input wire memory_ack_async,
    input wire publish_toggle_async,
    input wire [1:0] publish_buffer_async, input wire [1:0] publish_id_async,
    input wire publish_kind_async,
    output reg publish_ack_toggle,
    output reg [1:0] read_buffer, output reg [1:0] displayed_id,
    output reg display_valid, output reg arrival_event
);
(* async_reg="true" *) reg [2:0] pub_sync;
(* async_reg="true" *) reg [1:0] ack_sync;
reg [1:0] buf_meta,buf_sync,id_meta,id_sync;
reg kind_meta,kind_sync,frame_is_station;
reg last_consumed, frame_has_publication;
reg [2:0] settle_count;
reg [1:0] state;
localparam IDLE=0,SETTLE=1,WAIT_ACK=2,WAIT_LOW=3;
assign timing_ack = (state==WAIT_LOW);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        pub_sync<=0;ack_sync<=0;buf_meta<=0;buf_sync<=0;id_meta<=0;id_sync<=0;
        kind_meta<=0;kind_sync<=0;frame_is_station<=0;
        last_consumed<=0;frame_has_publication<=0;settle_count<=0;
        state<=IDLE;memory_req<=0;publish_ack_toggle<=0;
        read_buffer<=0;displayed_id<=0;display_valid<=0;arrival_event<=0;
    end else begin
        pub_sync<={pub_sync[1:0],publish_toggle_async};
        ack_sync<={ack_sync[0],memory_ack_async};
        buf_meta<=publish_buffer_async;buf_sync<=buf_meta;
        id_meta<=publish_id_async;id_sync<=id_meta;
        kind_meta<=publish_kind_async;kind_sync<=kind_meta;
        arrival_event<=0;
        case(state)
        IDLE: if(timing_req && !ack_sync[1]) begin
            frame_has_publication<=pub_sync[2]!=last_consumed;
            if(pub_sync[2]!=last_consumed) begin
                read_buffer<=buf_sync; displayed_id<=id_sync;
                frame_is_station<=kind_sync;
                last_consumed<=pub_sync[2];
            end
            settle_count<=0;state<=SETTLE;
        end
        SETTLE: if(settle_count==4) begin memory_req<=1;state<=WAIT_ACK;end
                else settle_count<=settle_count+1'b1;
        WAIT_ACK: if(ack_sync[1]) begin
            memory_req<=0;state<=WAIT_LOW;
            if(frame_has_publication) begin
                display_valid<=1;publish_ack_toggle<=last_consumed;
                arrival_event<=frame_is_station;
            end
        end
        WAIT_LOW: if(!timing_req && !ack_sync[1]) state<=IDLE;
        default: state<=IDLE;
        endcase
    end
end
endmodule
