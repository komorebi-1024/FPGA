set wl_result [catch {
cd C:/Users/14298/Desktop/WestLake_AV/03_Project/00_Baseline/src/td_project
import_device eagle_s20.db -package EG4S20BG256
open_project -single_run HDMI1.4b_Transmitter_v1.0.al
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
optimize_rtl
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
optimize_gate
report_area -file C:/Users/14298/Desktop/WestLake_AV/05_Build/baseline/gate.area
legalize_phy_inst
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
place
route
report_area -io_info -file C:/Users/14298/Desktop/WestLake_AV/05_Build/baseline/final.area
update_timing -mode final
report_timing_summary -file C:/Users/14298/Desktop/WestLake_AV/05_Build/baseline/timing.rpt
report_clock_summary -file C:/Users/14298/Desktop/WestLake_AV/05_Build/baseline/clocks.rpt
report_timing_exception -file C:/Users/14298/Desktop/WestLake_AV/05_Build/baseline/exceptions.rpt
export_db C:/Users/14298/Desktop/WestLake_AV/05_Build/baseline/routed.db
bitgen -bit C:/Users/14298/Desktop/WestLake_AV/05_Build/baseline/baseline.bit
close_project
} wl_message]
if {$wl_result} {puts "BUILD_FAILED: $wl_message"; puts $::errorInfo; exit 1}
puts BUILD_FLOW_COMPLETE
exit 0
