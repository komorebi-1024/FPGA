// WestLake original audio source. Pixel-clock synchronous PCM, no audio PLL.
// For a 25 MHz pixel clock: exactly 48000 sample-enable events per second.
// N=6144, CTS=25000 => Fs=F_TMDS*N/(128*CTS)=48000 Hz.
module wl_pcm_audio #(
    parameter integer CLK_HZ = 25000000,
    parameter integer SAMPLE_HZ = 48000
)(
    input wire clk, input wire rst,
    input wire test_mode, input wire arrival_event,
    output reg sample_valid,
    output reg [23:0] pcm_left, output reg [23:0] pcm_right,
    output reg acr_valid, output reg [19:0] acr_cts, output reg [19:0] acr_n,
    output wire chime_active
);
reg [31:0] sample_acc;
reg [15:0] phase;
reg [14:0] chime_left;
reg [5:0] acr_sample_count;
wire tick = sample_acc >= CLK_HZ-SAMPLE_HZ;
wire [15:0] phase_step = test_mode ? 16'd601 :
                         ((chime_left > 15'd9600) ? 16'd901 : 16'd1201);
wire [14:0] triangle_u = phase[15] ? ~phase[14:0] : phase[14:0];
wire signed [16:0] triangle_s = $signed({2'b00,triangle_u}) - 17'sd16384;
wire signed [23:0] triangle_pcm = {{7{triangle_s[16]}},triangle_s} <<< 5;
assign chime_active = chime_left != 0;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sample_acc<=0; phase<=0; chime_left<=0; acr_sample_count<=0;
        sample_valid<=0; pcm_left<=0; pcm_right<=0;
        acr_valid<=0; acr_cts<=0; acr_n<=0;
    end else begin
        sample_valid<=0; acr_valid<=0;
        if (arrival_event) chime_left<=15'd19200;
        if (tick) begin
            sample_acc<=sample_acc+SAMPLE_HZ-CLK_HZ;
            sample_valid<=1;
            phase<=phase+phase_step;
            if (test_mode || chime_active) begin
                pcm_left<=triangle_pcm; pcm_right<=triangle_pcm;
            end else begin pcm_left<=0; pcm_right<=0; end
            if (!arrival_event && chime_active) chime_left<=chime_left-1'b1;
            if (acr_sample_count==47) begin
                acr_sample_count<=0; acr_valid<=1;
                acr_n<=20'd6144; acr_cts<=CLK_HZ/1000;
            end else acr_sample_count<=acr_sample_count+1'b1;
        end else sample_acc<=sample_acc+SAMPLE_HZ;
    end
end
endmodule
