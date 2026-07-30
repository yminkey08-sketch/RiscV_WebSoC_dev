set proj_name [lindex $argv 0]
set proj_dir  [lindex $argv 1]
set rtl_dir   [lindex $argv 2]

create_project -force $proj_name $proj_dir -part xc7a35tfgg484-2
puts "\[OK\] Project created"

# Add all Verilog/SystemVerilog sources
set vfiles [glob -nocomplain ${rtl_dir}/*.v ${rtl_dir}/*.sv]
foreach f [lsort $vfiles] {
    add_files -norecurse $f
}
# Mark all source files as SystemVerilog (project uses SV constructs throughout)
set_property FILE_TYPE SYSTEMVERILOG [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog}]
puts "\[OK\] Added [llength $vfiles] source files (SystemVerilog)"

# FPGA build time
add_files -norecurse [file normalize "$proj_dir/fpga_build_time.v"]

# Top module
set_property top webserver_cpu_top [current_fileset]
update_compile_order -fileset sources_1
puts "\[OK\] Top: webserver_cpu_top"

# Constraints
add_files -fileset constrs_1 -norecurse [file normalize "$proj_dir/pins.xdc"]
add_files -fileset constrs_1 -norecurse [file normalize "$proj_dir/timing.xdc"]

# Synthesis
puts "Running Synthesis..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Implementation + Bitstream
puts "Running Implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Copy bitstream
set bit_src "$proj_dir/${proj_name}.runs/impl_1/webserver_cpu_top.bit"
set bit_dst "$proj_dir/${proj_name}.bit"
if {[file exists $bit_src]} {
    file copy -force $bit_src $bit_dst
    puts "Bitstream: $bit_dst"
}

# Reports
open_run impl_1
report_timing_summary -file "$proj_dir/timing_summary.rpt"
report_utilization    -file "$proj_dir/utilization.rpt"
close_design

puts "============================================"
puts " Build Complete!"
puts " Bitstream: $bit_dst"
puts "============================================"
