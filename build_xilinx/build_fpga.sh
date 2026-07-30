#!/bin/bash
#=============================================================================
# RiscV_WebSoC Xilinx XC7A35T-FGG484 构建脚本
#=============================================================================
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version_hex>"
    echo "  e.g. $0 0001"
    exit 1
fi

VERSION_RAW="$1"
if [[ ! "${VERSION_RAW}" =~ ^[0-9a-fA-F]{1,4}$ ]]; then
    echo "ERROR: Version must be 1~4 hex digits"
    exit 1
fi

VERSION=$(printf '%04s' "$(echo "${VERSION_RAW}" | tr '[:upper:]' '[:lower:]')" | tr ' ' '0')

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PROJ_NAME="RiscV_WebSoC_v${VERSION}_${TIMESTAMP}"
BUILD_DIR="${PROJ_DIR}/build_${PROJ_NAME}"

echo "============================================"
echo " RiscV_WebSoC FPGA Build"
echo " Target : XC7A35T-FGG484-2"
echo " Version: ${VERSION}"
echo " Build  : ${BUILD_DIR}"
echo "============================================"

mkdir -p "${BUILD_DIR}"

#-----------------------------------------------------------------
# 生成 fpga_build_time.v
#-----------------------------------------------------------------
echo "[1/5] Generating fpga_build_time.v..."
BUILD_DATE=$(printf "32'h%04d%02d%02d" "$((10#$(date +%Y)))" "$((10#$(date +%m)))" "$((10#$(date +%d)))")
BUILD_TIME=$(printf "32'h%02d%02d%04s" "$((10#$(date +%H)))" "$((10#$(date +%M)))" "${VERSION}" | tr ' ' '0')

cat > "${BUILD_DIR}/fpga_build_time.v" << EOF
module fpga_build_time (
    output wire [31:0] build_date,
    output wire [31:0] build_time
);
    assign build_date = ${BUILD_DATE};
    assign build_time = ${BUILD_TIME};
endmodule
EOF
echo "  build_date = ${BUILD_DATE}"
echo "  build_time = ${BUILD_TIME}"

#-----------------------------------------------------------------
# 复制约束文件
#-----------------------------------------------------------------
echo "[2/5] Copying constraints..."
cp "${SCRIPT_DIR}/pins.xdc"   "${BUILD_DIR}/"
cp "${SCRIPT_DIR}/timing.xdc" "${BUILD_DIR}/"
cp "${SCRIPT_DIR}/webserver.xdc" "${BUILD_DIR}/" 2>/dev/null || true

#-----------------------------------------------------------------
# 生成 Vivado TCL 脚本
#-----------------------------------------------------------------
echo "[3/5] Generating Vivado TCL..."
cat > "${BUILD_DIR}/build.tcl" << 'TCL_EOF'
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
TCL_EOF

#-----------------------------------------------------------------
# 复制 RTL 文件到构建目录
#-----------------------------------------------------------------
echo "[4/5] Copying RTL files..."
cp "${PROJ_DIR}/rtl/"*.v "${PROJ_DIR}/rtl/"*.sv "${BUILD_DIR}/" 2>/dev/null || true

#-----------------------------------------------------------------
# 启动 Vivado
#-----------------------------------------------------------------
echo "[5/5] Launching Vivado..."
cd "${BUILD_DIR}"
vivado -mode batch -source build.tcl \
    -log vivado.log -journal vivado.jou \
    -tclargs "${PROJ_NAME}" "${BUILD_DIR}" "${PROJ_DIR}/rtl"

echo ""
echo "============================================"
echo " Build Complete"
echo " Bitstream: ${BUILD_DIR}/${PROJ_NAME}.bit"
echo "============================================"
