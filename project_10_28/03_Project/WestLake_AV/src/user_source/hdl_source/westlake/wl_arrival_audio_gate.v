// Let the HDMI sink lock before the first station's chime and narration.
// Subsequent arrivals keep their normal timing, including after a cancelled wait.
module wl_arrival_audio_gate #(
    parameter integer CLK_HZ = 25000000,
    parameter integer INITIAL_DELAY_CYCLES = CLK_HZ * 5
) (
    input  wire clk,
    input  wire rst,
    input  wire arrival_event,
    input  wire in_station,
    output reg  audio_arrival_event,
    output wire boot_waiting
);
    localparam integer COUNT_WIDTH = (INITIAL_DELAY_CYCLES > 1)
                                   ? $clog2(INITIAL_DELAY_CYCLES) : 1;
    reg first_arrival_seen;
    reg waiting;
    reg [COUNT_WIDTH-1:0] delay_left;

    assign boot_waiting = waiting && in_station;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            first_arrival_seen <= 1'b0;
            waiting <= 1'b0;
            delay_left <= 0;
            audio_arrival_event <= 1'b0;
        end else begin
            audio_arrival_event <= 1'b0;
            if (!in_station) begin
                waiting <= 1'b0;
                delay_left <= 0;
            end else if (arrival_event) begin
                first_arrival_seen <= 1'b1;
                if (!first_arrival_seen && INITIAL_DELAY_CYCLES > 0) begin
                    waiting <= 1'b1;
                    delay_left <= INITIAL_DELAY_CYCLES - 1;
                end else begin
                    // A new committed station supersedes any pending event.
                    waiting <= 1'b0;
                    delay_left <= 0;
                    audio_arrival_event <= 1'b1;
                end
            end else if (waiting) begin
                if (delay_left == 0) begin
                    waiting <= 1'b0;
                    audio_arrival_event <= 1'b1;
                end else begin
                    delay_left <= delay_left - 1'b1;
                end
            end
        end
    end
endmodule
