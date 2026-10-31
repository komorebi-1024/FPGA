`timescale 1ns/1ps
// Real 100 MHz SD / 25 MHz video / 48 kHz HDMI sample timing, with three
// sector clients and a separate narration FIFO. No encrypted HDMI simulation.
module tb_voice_stream;
reg sc=0,vc=0;always #5 sc=~sc;always #20 vc=~vc;
reg rst=1,sd_ready=0,arrival=0,in_station=0;
reg [1:0] station=0;
wire request,stop,play,active,done,complete,ctrl_error,session;
wire [1:0] request_station,subtitle_phase;wire [5:0] subtitle_reveal;
wire reader_ack,reader_ready,catalog,reader_error;
wire [31:0] total,cue1,cue2;wire [14:0] chars;
wire vr,vv,ve,fw,flush,full,empty,wr_reset,rd_reset;
wire [31:0] va,fd,fq;wire [7:0] vd;wire [9:0] level;
wire voice_pop,music_pop,music_valid,pcm_valid,chime,acr,voice_underrun,music_underrun;
wire [23:0] left,right;wire [19:0] cts,n;
wl_voice_ctrl control(.clk(vc),.rst(rst),.arrival_event(arrival),.station_id(station),.in_station(in_station),
 .reader_ack_toggle_async(reader_ack),.reader_ready_async(reader_ready),.reader_error_async(reader_error),
 .reader_catalog_ready_async(catalog),.voice_fifo_reset(rd_reset),.voice_pop(voice_pop),
 .current_total_frames_async(total),.current_cue1_async(cue1),.current_cue2_async(cue2),.current_chars_async(chars),
 .request_toggle(request),.request_station(request_station),.stop_request(stop),.voice_play(play),.voice_active(active),
 .subtitle_phase(subtitle_phase),.subtitle_reveal(subtitle_reveal),.subtitle_session_toggle(session),
 .voice_done(done),.voice_complete(complete),.voice_error(ctrl_error));
wl_voice_reader reader(.clk(sc),.rst(rst),.sd_ready(sd_ready),.start_toggle_async(request),
 .station_id_async(request_station),.stop_async(stop),.sector_read(vr),.sector_addr(va),
 .sector_data(vd),.sector_valid(vv),.sector_end(ve),.fifo_level(level),.fifo_full(full),
 .fifo_write(fw),.fifo_data(fd),.fifo_flush(flush),.session_ack_toggle(reader_ack),.buffer_ready(reader_ready),
 .catalog_ready(catalog),.voice_error(reader_error),.current_total_frames(total),
 .current_cue1(cue1),.current_cue2(cue2),.current_chars(chars));
wl_reset_sync writer_reset(sc,rst || flush,wr_reset);
wl_reset_sync reader_reset(vc,rst || flush,rd_reset);
wl_audio_fifo #(.ADDR_BITS(9)) fifo(sc,wr_reset,fw,fd,full,level,vc,rd_reset,voice_pop,fq,empty);

// The inner arbiter prioritizes narration over music. Its entire sector request
// is the audio client of the outer arbiter, which also serves image loading.
reg mr=0;reg [31:0] ma=12000;
wire mv,me,ar,av,ae,sr,sv,se,iv,ie;wire [31:0] aa,sa;
wire [7:0] md,ad,sd,id;
reg [31:0] ia=9000;
wl_sd_arbiter inner(sc,rst,mr,ma,md,mv,me,vr,va,vd,vv,ve,ar,aa,ad,av,ae);
wl_sd_arbiter outer(sc,rst,sd_ready,ia,id,iv,ie,ar,aa,ad,av,ae,sr,sa,sd,sv,se);

function [31:0] sample;
 input integer source,frame_id;
 reg [15:0] l,r;
 begin l=100+source*2000+frame_id;r=-100-source*2000-frame_id;sample={r,l};end
endfunction
integer music_index=0;
wire [31:0] music_word=sample(9,music_index);
wl_pcm_audio #(.CHIME_SAMPLES(48)) pcm(.clk(vc),.rst(rst),.test_mode(1'b0),.arrival_event(arrival),
 .sample_valid(pcm_valid),.pcm_left(left),.pcm_right(right),.acr_valid(acr),.acr_cts(cts),.acr_n(n),.chime_active(chime),
 .music_enable(!in_station),.music_ready(1'b1),.music_empty(1'b0),.music_data(music_word),
 .music_pop(music_pop),.music_sample_valid(music_valid),.music_underrun(music_underrun),
 .voice_enable(play),.voice_ready(!rd_reset),.voice_empty(empty),.voice_data(fq),
 .voice_pop(voice_pop),.voice_underrun(voice_underrun));

reg [7:0] meta[0:511];
task put32(input integer offset,input [31:0] value);
 begin meta[offset]=value[7:0];meta[offset+1]=value[15:8];meta[offset+2]=value[23:16];meta[offset+3]=value[31:24];end
endtask
function [7:0] sector_byte;
 input [31:0] lba;input integer offset;
 integer voice_id,frame_id;reg [31:0] word_data;
 begin
  if(lba==2058)sector_byte=meta[offset];
  else if(lba>=3000 && lba<7000)begin
   voice_id=lba/1000-3;frame_id=(lba-(3000+voice_id*1000))*128+offset/4;
   word_data=sample(voice_id,frame_id);sector_byte=word_data[(offset%4)*8 +:8];
  end else sector_byte=8'ha5^lba[7:0]^offset[7:0];
 end
endfunction

reg [2:0] model_state=0;reg [5:0] byte_delay=0;
reg [9:0] byte_index=0;reg [31:0] locked_lba=0;
reg model_valid=0,model_end=0;reg [7:0] model_data=0;
assign sv=model_valid;assign se=model_end;assign sd=model_data;
integer image_offset=0,music_offset=0,image_sectors=0,music_sectors=0,music_delay=0;
always @(posedge sc)begin
 model_valid<=0;model_end<=0;
 if(rst)begin model_state<=0;byte_delay<=0;byte_index<=0;mr<=0;music_delay=0;end
 else begin
  case(model_state)
   0:if(sr)begin locked_lba<=sa;byte_delay<=0;byte_index<=0;model_state<=1;end
   1:begin
    if(!sr || sa!==locked_lba)$fatal(1,"SD request changed within sector");
    if(byte_delay==31)begin
     byte_delay<=0;model_valid<=1;model_data<=sector_byte(locked_lba,byte_index);
     if(byte_index==511)model_state<=2;else byte_index<=byte_index+1'b1;
    end else byte_delay<=byte_delay+1'b1;
   end
   2:begin model_end<=1;model_state<=3;end
   3:model_state<=4;
   4:model_state<=0;
  endcase
  if(!mr && sd_ready)begin
   if(music_delay==0)mr<=1;else music_delay=music_delay-1;
  end
  if(mv)begin
   if(md!==(8'ha5^ma[7:0]^music_offset[7:0]))$fatal(1,"music client received wrong sector bytes");
   music_offset=music_offset+1;
  end
  if(me)begin
   if(music_offset!=512)$fatal(1,"music sector length");
   music_offset=0;music_sectors=music_sectors+1;ma<=ma+1'b1;mr<=0;music_delay=15000;
  end
  if(iv)begin
   if(id!==(8'ha5^ia[7:0]^image_offset[7:0]))$fatal(1,"image client received wrong sector bytes");
   image_offset=image_offset+1;
  end
  if(ie)begin
   if(image_offset!=512)$fatal(1,"image sector length");
   image_offset=0;image_sectors=image_sectors+1;ia<=ia+1'b1;
  end
  if((vv && mv)||(ve && me)||(iv && av)||(ie && ae))$fatal(1,"sector routed to two clients");
 end
end

integer voice_count=0,all_voice_samples=0,music_count=0,tick_count=0,expected_station=0;
integer expected_phase,expected_reveal,session_chime_samples=0;
reg voice_before,music_before,chime_before;reg [31:0] expected_word;
always @(posedge vc)begin
 voice_before=voice_pop;music_before=music_pop;chime_before=chime;
 if(rst)begin music_index=0;voice_count=0;all_voice_samples=0;music_count=0;tick_count=0;end
 else begin
  if(arrival)begin voice_count=0;expected_station=station;session_chime_samples=0;end
  if(voice_before)begin
   if(!in_station || chime_before || arrival || rd_reset || !play)$fatal(1,"illegal voice consumption");
   expected_word=sample(expected_station,voice_count);
   voice_count=voice_count+1;all_voice_samples=all_voice_samples+1;
  end else if(music_before)begin
   if(in_station || chime_before || arrival)$fatal(1,"music did not pause for station");
   expected_word=sample(9,music_index);music_index=music_index+1;music_count=music_count+1;
  end
  #1;
  if(ctrl_error || reader_error || voice_underrun || music_underrun)$fatal(1,"stream error/underrun");
  if(pcm_valid)begin
   tick_count=tick_count+1;
   if(chime_before)session_chime_samples=session_chime_samples+1;
  end
  if(voice_before || music_before)begin
   if(!pcm_valid || {right[23:8],left[23:8]}!==expected_word || left[7:0] || right[7:0])
    $fatal(1,"PCM mismatch station=%0d frame=%0d actual=%h/%h expected=%h",expected_station,voice_count,left,right,expected_word);
  end
  if(voice_before)begin
   if(voice_count<=128)begin expected_phase=0;expected_reveal=(voice_count*8+127)/128;end
   else if(voice_count<=257)begin expected_phase=1;expected_reveal=((voice_count-128)*12+128)/129;end
   else begin expected_phase=2;expected_reveal=((voice_count-257)*10+129)/130;end
   if(subtitle_phase!==expected_phase || subtitle_reveal!==expected_reveal)
    $fatal(1,"subtitle/pop mismatch sample=%d got=%d/%d expected=%d/%d",voice_count,subtitle_phase,subtitle_reveal,expected_phase,expected_reveal);
  end
 end
end

task arrive(input integer stop_id);
 begin
  // Avoid the sample tick itself so the accelerated chime is exactly 48 samples.
  wait(pcm_valid);@(negedge vc);station=stop_id;in_station=1;arrival=1;
  @(negedge vc);arrival=0;
 end
endtask
task wait_voice_end;
 integer snapshot,ticks;
 begin
  wait(complete);@(negedge vc);
  if(voice_count!=387 || session_chime_samples!=48 || !in_station || play || active)
   $fatal(1,"end accounting frames=%d chime=%d",voice_count,session_chime_samples);
  snapshot=music_count;ticks=tick_count;
  wait(tick_count>=ticks+30);
  if(voice_count!=387 || music_count!=snapshot || !complete || subtitle_phase!=2 || subtitle_reveal!=10)
   $fatal(1,"station did not hold final subtitle/music head");
 end
endtask

integer k,j,snapshot,initial_music;
initial begin
 for(k=0;k<512;k=k+1)meta[k]=0;
 meta[0]="W";meta[1]="L";meta[2]="V";meta[3]="O";meta[4]="C";meta[5]="0";meta[6]="0";meta[7]="1";
 meta[8]=4;meta[9]=2;meta[10]=16;meta[11]=3;put32(12,48000);
 for(j=0;j<4;j=j+1)begin
  put32(16+j*32,3000+j*1000);put32(20+j*32,387);put32(24+j*32,128);put32(28+j*32,257);
  meta[36+j*32]=8;meta[37+j*32]=12;meta[38+j*32]=10;
 end
 repeat(8)@(negedge sc);rst=0;sd_ready=1;
 wait(catalog);wait(music_count>=40);
 arrive(0);initial_music=music_count;wait_voice_end();
 if(music_count!=initial_music)$fatal(1,"music head changed during first narration");
 // Repeat the same station without an ID change or intervening departure.
 arrive(0);wait_voice_end();
 @(negedge vc);in_station=0;snapshot=music_count;
 wait(music_count>=snapshot+80);
 // Cancel halfway through a narration SD sector, then immediately request a
 // different station. The old sector must finish without polluting the new FIFO.
 arrive(1);
 wait(model_state==1 && locked_lba>=4000 && locked_lba<4004 && byte_index>80 && byte_index<400);
 @(negedge vc);in_station=0;repeat(6)@(negedge vc);
 station=2;in_station=1;arrival=1;@(negedge vc);arrival=0;
 wait_voice_end();
 if(all_voice_samples!=1161 || image_sectors==0 || music_sectors==0)
  $fatal(1,"integration coverage voice=%d images=%d music sectors=%d",all_voice_samples,image_sectors,music_sectors);
 $display("PASS voice stream: %0d exact PCM samples, pop-aligned three-sentence subtitles, chime priority, music pause/resume, same-stop replay and in-flight cancel; %0d image/%0d music sectors",all_voice_samples,image_sectors,music_sectors);
 $finish;
end
initial begin #100000000;$fatal(1,"voice stream timeout voice=%d station=%d ready=%b play=%b readerstate=%d",voice_count,station,reader_ready,play,reader.state);end
endmodule
