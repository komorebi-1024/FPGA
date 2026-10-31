`timescale 1ns/1ps
module tb_arrival_audio_gate;
    reg clk = 0;
    always #20 clk = ~clk;
    reg rst = 1, arrival = 0, in_station = 1;
    wire audio_arrival, waiting, immediate_arrival, immediate_waiting;
    integer i;

    wl_arrival_audio_gate #(.CLK_HZ(25), .INITIAL_DELAY_CYCLES(5)) dut (
        .clk(clk), .rst(rst), .arrival_event(arrival), .in_station(in_station),
        .audio_arrival_event(audio_arrival), .boot_waiting(waiting)
    );
    wl_arrival_audio_gate #(.INITIAL_DELAY_CYCLES(0)) zero_delay (
        .clk(clk), .rst(rst), .arrival_event(arrival), .in_station(in_station),
        .audio_arrival_event(immediate_arrival), .boot_waiting(immediate_waiting)
    );

    task tick;
        begin @(posedge clk); #1; end
    endtask
    task reset_gate;
        begin
            @(negedge clk); rst = 1; arrival = 0; in_station = 1;
            tick();
            if (audio_arrival || waiting) $fatal(1, "reset did not clear gate");
            @(negedge clk); rst = 0;
        end
    endtask
    task first_arrival;
        begin
            @(negedge clk); arrival = 1;
            tick();
            if (audio_arrival || !waiting) $fatal(1, "first arrival was not delayed");
            if (!immediate_arrival || immediate_waiting) $fatal(1, "zero delay parameter");
            @(negedge clk); arrival = 0;
        end
    endtask
    task finish_first_wait;
        begin
            for (i = 1; i <= 5; i = i + 1) begin
                tick();
                if (audio_arrival !== (i == 5) || waiting !== (i != 5))
                    $fatal(1, "initial delay must be exactly 5 cycles; cycle=%0d", i);
            end
            tick();
            if (audio_arrival || waiting) $fatal(1, "initial event repeated");
        end
    endtask
    task later_arrival;
        begin
            @(negedge clk); arrival = 1;
            tick();
            if (!audio_arrival || waiting) $fatal(1, "later arrival must be immediate");
            @(negedge clk); arrival = 0;
            tick();
            if (audio_arrival || waiting) $fatal(1, "later event repeated");
        end
    endtask

    initial begin
        reset_gate();
        repeat (3) begin
            tick();
            if (audio_arrival || waiting) $fatal(1, "delay began before first arrival");
        end
        first_arrival();
        finish_first_wait();
        later_arrival();
        later_arrival();

        // Leaving cancels the old station, but consumes the one boot delay.
        reset_gate();
        first_arrival();
        repeat (2) tick();
        @(negedge clk); in_station = 0;
        tick();
        if (audio_arrival || waiting) $fatal(1, "departure did not cancel initial wait");
        repeat (7) begin
            tick();
            if (audio_arrival || waiting) $fatal(1, "cancelled event leaked");
        end
        @(negedge clk); in_station = 1;
        later_arrival();

        // Departure has priority even on the clock that would release audio.
        reset_gate();
        first_arrival();
        repeat (4) tick();
        @(negedge clk); in_station = 0; arrival = 1;
        tick();
        if (audio_arrival || waiting) $fatal(1, "expiry/departure collision leaked old audio");
        @(negedge clk); in_station = 1; arrival = 0;
        later_arrival();

        // A newer committed station must suppress the old delayed event.
        reset_gate();
        first_arrival();
        repeat (2) tick();
        later_arrival();
        repeat (7) begin
            tick();
            if (audio_arrival || waiting) $fatal(1, "superseded initial event repeated");
        end

        // Reset during a wait restores the initial delay for the next session.
        reset_gate();
        first_arrival();
        repeat (2) tick();
        reset_gate();
        first_arrival();
        finish_first_wait();
        $display("PASS: first arrival exact delay, later immediate, cancellation, replacement, reset, zero delay");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
