// 256-point real-input DFT, bins 1..127, grouped into eight continuous bands.
// 48 kHz mono PCM; 25 MHz processing clock. One shared 12x12 multiplier.
// Each sample takes 509 clocks. Valid samples must be >= 510 clocks apart.
// Band bin ranges: 1; 2..3; 4..7; 8..15; 16..31; 32..47; 48..79; 80..127.
// DC and Nyquist are omitted. Rectangular window, 187.5 Hz bin spacing.
// Display is log-compressed mean |I|+|Q|, with fast attack and slow decay;
// it is a music visualization, not calibrated SPL or a precision FFT meter.
// Accumulator RAM is cleared sequentially (127 clocks after enable/reset).
module wl_audio_spectrum #(
 parameter integer DECAY_STEP=2
)(
 input wire clk,input wire rst,input wire enable,
 input wire sample_valid,input wire signed [15:0] sample_pcm,
 output reg [63:0] levels,output reg levels_valid,
 output reg sample_overrun
);
localparam INIT=0,WAIT_SAMPLE=1,MULTIPLY=2,ACCUMULATE=3;
reg [1:0] state;
reg [6:0] clear_index,bin_index;
reg [7:0] sample_index,angle;
reg quadrature;
reg signed [11:0] sample_hold;
reg signed [23:0] product;
reg signed [31:0] acc_i[1:127],acc_q[1:127];
reg signed [31:0] acc_read,current_i;
reg [2:0] band_index;
reg [39:0] band_sum;
reg [63:0] next_levels;
wire signed [31:0] sum=acc_read+{{8{product[23]}},product};
wire [31:0] abs_i=current_i[31] ? -current_i : current_i;
wire [31:0] abs_q=sum[31] ? -sum : sum;
wire [32:0] magnitude={1'b0,abs_i}+{1'b0,abs_q};
wire [39:0] magnitude_sum=band_sum+{{7{1'b0}},magnitude};
wire band_end=(bin_index==1 || bin_index==3 || bin_index==7 || bin_index==15 ||
               bin_index==31 || bin_index==47 || bin_index==79 || bin_index==127);
// Power-of-two normalization; the last (48-bin) band uses /64.
wire [2:0] band_shift=(band_index<5) ? band_index :
                           ((band_index==5) ? 3'd4 : ((band_index==6) ? 3'd5 : 3'd6));
function [7:0] compress;
 input [39:0] value;
 reg [24:0] scaled;
 reg [7:0] fraction;
 integer bit_index,top_bit;
 begin
  scaled=value>>15;top_bit=0;
  for(bit_index=0;bit_index<25;bit_index=bit_index+1)
   if(scaled>>bit_index)top_bit=bit_index;
  if(scaled==0)compress=0;
  else if(top_bit>=15)compress=255;
  else begin
   if(top_bit>=4)fraction=scaled>>(top_bit-4);
   else fraction=scaled<<(4-top_bit);
   compress=((top_bit+1)<<4)+(fraction&8'h0f);
  end
 end
endfunction
wire [7:0] target=compress(magnitude_sum>>band_shift);
wire [7:0] previous=levels[band_index*8 +: 8];
wire [7:0] released=(previous>DECAY_STEP) ? previous-DECAY_STEP : 8'd0;
wire [7:0] display_level=(target>=released) ? target : released;
function signed [11:0] sine;
 input [7:0] phase;
 reg [6:0] offset;
 reg [11:0] amplitude;
 begin
  offset=phase[6] ? 7'd64-{1'b0,phase[5:0]} : {1'b0,phase[5:0]};
  case(offset)
   7'd0:amplitude=12'd0;
   7'd1:amplitude=12'd50;
   7'd2:amplitude=12'd100;
   7'd3:amplitude=12'd151;
   7'd4:amplitude=12'd201;
   7'd5:amplitude=12'd251;
   7'd6:amplitude=12'd300;
   7'd7:amplitude=12'd350;
   7'd8:amplitude=12'd399;
   7'd9:amplitude=12'd449;
   7'd10:amplitude=12'd497;
   7'd11:amplitude=12'd546;
   7'd12:amplitude=12'd594;
   7'd13:amplitude=12'd642;
   7'd14:amplitude=12'd690;
   7'd15:amplitude=12'd737;
   7'd16:amplitude=12'd783;
   7'd17:amplitude=12'd830;
   7'd18:amplitude=12'd875;
   7'd19:amplitude=12'd920;
   7'd20:amplitude=12'd965;
   7'd21:amplitude=12'd1009;
   7'd22:amplitude=12'd1052;
   7'd23:amplitude=12'd1095;
   7'd24:amplitude=12'd1137;
   7'd25:amplitude=12'd1179;
   7'd26:amplitude=12'd1219;
   7'd27:amplitude=12'd1259;
   7'd28:amplitude=12'd1299;
   7'd29:amplitude=12'd1337;
   7'd30:amplitude=12'd1375;
   7'd31:amplitude=12'd1411;
   7'd32:amplitude=12'd1447;
   7'd33:amplitude=12'd1483;
   7'd34:amplitude=12'd1517;
   7'd35:amplitude=12'd1550;
   7'd36:amplitude=12'd1582;
   7'd37:amplitude=12'd1614;
   7'd38:amplitude=12'd1644;
   7'd39:amplitude=12'd1674;
   7'd40:amplitude=12'd1702;
   7'd41:amplitude=12'd1729;
   7'd42:amplitude=12'd1756;
   7'd43:amplitude=12'd1781;
   7'd44:amplitude=12'd1805;
   7'd45:amplitude=12'd1828;
   7'd46:amplitude=12'd1850;
   7'd47:amplitude=12'd1871;
   7'd48:amplitude=12'd1891;
   7'd49:amplitude=12'd1910;
   7'd50:amplitude=12'd1927;
   7'd51:amplitude=12'd1944;
   7'd52:amplitude=12'd1959;
   7'd53:amplitude=12'd1973;
   7'd54:amplitude=12'd1986;
   7'd55:amplitude=12'd1997;
   7'd56:amplitude=12'd2008;
   7'd57:amplitude=12'd2017;
   7'd58:amplitude=12'd2025;
   7'd59:amplitude=12'd2032;
   7'd60:amplitude=12'd2037;
   7'd61:amplitude=12'd2041;
   7'd62:amplitude=12'd2045;
   7'd63:amplitude=12'd2046;
   7'd64:amplitude=12'd2047;
   default:amplitude=0;
  endcase
  sine=phase[7] ? -$signed(amplitude) : $signed(amplitude);
 end
endfunction
wire signed [11:0] coefficient=sine(angle+(quadrature ? 8'd0 : 8'd64));
// Separate synchronous RAM processes, without asynchronous resets on RAM bits.
always @(posedge clk) begin
 if(state==INIT && enable && !rst)begin
  acc_i[clear_index]<=0;acc_q[clear_index]<=0;
 end else if(state==ACCUMULATE && enable && !rst)begin
  if(quadrature)acc_q[bin_index]<=(sample_index==255) ? 32'sd0 : sum;
  else acc_i[bin_index]<=(sample_index==255) ? 32'sd0 : sum;
 end
 if(state==MULTIPLY)acc_read<=quadrature ? acc_q[bin_index] : acc_i[bin_index];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=INIT;clear_index<=1;bin_index<=1;sample_index<=0;angle<=0;quadrature<=0;
  sample_hold<=0;product<=0;current_i<=0;band_index<=0;band_sum<=0;
  levels<=0;next_levels<=0;levels_valid<=0;sample_overrun<=0;
 end else begin
  levels_valid<=0;
  if(!enable)begin
   state<=INIT;clear_index<=1;sample_index<=0;levels<=0;next_levels<=0;
   band_sum<=0;band_index<=0;sample_overrun<=0;
  end else begin
   if(sample_valid && state!=WAIT_SAMPLE && state!=INIT)sample_overrun<=1;
   case(state)
    INIT:if(clear_index==127)state<=WAIT_SAMPLE;else clear_index<=clear_index+1'b1;
    WAIT_SAMPLE:if(sample_valid)begin
     sample_hold<=sample_pcm>>>4;bin_index<=1;angle<=sample_index;
     quadrature<=0;state<=MULTIPLY;
    end
    MULTIPLY:begin product<=sample_hold*coefficient;state<=ACCUMULATE;end
    ACCUMULATE:begin
     if(!quadrature)begin current_i<=sum;quadrature<=1;state<=MULTIPLY;end
     else begin
      if(sample_index==255)begin
       if(band_end)begin
        next_levels[band_index*8 +: 8]<=display_level;band_sum<=0;band_index<=band_index+1'b1;
        if(bin_index==127)begin levels<={display_level,next_levels[55:0]};levels_valid<=1;end
       end else band_sum<=magnitude_sum;
      end
      if(bin_index==127)begin sample_index<=sample_index+1'b1;state<=WAIT_SAMPLE;end
      else begin bin_index<=bin_index+1'b1;angle<=angle+sample_index;quadrature<=0;state<=MULTIPLY;end
     end
    end
    default:state<=INIT;
   endcase
  end
 end
end
endmodule
