set script_dir [file dirname [file normalize [info script]]]
set root [file dirname $script_dir]
set wl_build_output [file join $root 05_Build $variant]
file mkdir $wl_build_output
cd [file join $root 03_Project $project_dir src td_project]
set result [catch {
    import_device eagle_s20.db -package EG4S20BG256
    open_project -single_run HDMI1.4b_Transmitter_v1.0.al
    elaborate -top top
    read_adc ../user_source/constraints_source/pin.adc
    optimize_rtl
    read_sdc ../user_source/constraints_source/timing.sdc
    read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
    read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
    optimize_gate
    report_area -file [file join $wl_build_output gate.area]
    legalize_phy_inst
    read_sdc ../user_source/constraints_source/timing.sdc
    read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
    read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
    place
    route
    report_area -io_info -file [file join $wl_build_output final.area]
    update_timing -mode final
    report_timing_summary -file [file join $wl_build_output timing.rpt]
    report_clock_summary -file [file join $wl_build_output clocks.rpt]
    report_timing_exception -file [file join $wl_build_output exceptions.rpt]
    export_db [file join $wl_build_output routed.db]
    bitgen -bit [file join $wl_build_output ${variant}.bit]
    close_project
} message]
set status [open [file join $wl_build_output build_status.txt] w]
if {$result} {
    puts $status "FAILED: $message"
    close $status
    puts "BUILD_FAILED: $message"
    puts $::errorInfo
    exit 1
}
puts $status "FLOW_COMPLETE: inspect timing and warnings before hardware use"
close $status
puts "BUILD_FLOW_COMPLETE"
exit 0

