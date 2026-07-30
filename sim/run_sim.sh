#!/bin/bash
# RiscV_WebSoC 仿真脚本
# RTL: ../rtl/*.v    (硬件代码, 44 个文件)
# SIM: ./*.v ./*.sv  (仿真模型: pll_bypass, vendor_stubs, xpm, lcpu_bfm)
set -e
cd "$(dirname "$0")"

echo "=== 编译 RiscV_WebSoC 仿真 ==="

iverilog -g2012 -I ../rtl -s tb_webserver_cpu_top \
  -o tb_webserver.vvp \
  ../rtl/*.v \
  ./*.v ./*.sv

echo "编译成功！运行仿真..."
echo ""

vvp tb_webserver.vvp

echo ""
echo "=== 仿真完成 ==="
