#===================================================================
# RiscV_WebSoC Timing Constraints
# Target: XC7A35T-FGG484-2, ALINX ACX750 + RTL8211 PHY
# Based on lcpu_rgmii proven constraints
#===================================================================

#===== 输入时钟 50MHz (板载晶振, W19) =====
create_clock -period 20.000 -name fpga_clk [get_ports clk_50m_in]

#===== RGMII RXC (来自 PHY, 125MHz) =====
create_clock -period 8.000 -name enet1_rx_clk [get_ports rgmii_rxc]

#===== MMCM Generated Clocks =====
# u_pll = mmcm_50_125 instance in webserver_cpu_top
# MMCME2_BASE instance: u_pll/u_mmcm
# f_VCO = 50MHz × 20 / 1 = 1000MHz

# clk_125m: 1000MHz / 8 = 125MHz @ 0°
create_generated_clock -name clk_125m \
    -source [get_pins u_pll/u_mmcm/CLKIN1] \
    -divide_by 8 -multiply_by 20 \
    [get_pins u_pll/u_bufg_125/O]

# clk_200m: 1000MHz / 5 = 200MHz @ 0°
create_generated_clock -name clk_200m \
    -source [get_pins u_pll/u_mmcm/CLKIN1] \
    -divide_by 5 -multiply_by 20 \
    [get_pins u_pll/u_bufg_200/O]

# clk_125m_tx: 1000MHz / 8 = 125MHz @ 90°
create_generated_clock -name clk_125m_tx \
    -source [get_pins u_pll/u_mmcm/CLKIN1] \
    -divide_by 8 -multiply_by 20 \
    [get_pins u_pll/u_bufg_125_tx/O]

# cpu_clk: 1000MHz / 20 = 50MHz @ 0°
create_generated_clock -name cpu_clk \
    -source [get_pins u_pll/u_mmcm/CLKIN1] \
    -divide_by 20 -multiply_by 20 \
    [get_pins u_pll/u_bufg_50_cpu/O]

#===== RGMII RX Input Delay (DDR) =====
# DDR data valid window: rise/fall edge each 4ns (125MHz DDR)
# IDELAYE2 provides ~1.56ns fixed delay compensation

# Rising edge data (lower nibble)
set_input_delay -clock [get_clocks enet1_rx_clk] -max 2.000 \
    [get_ports {{rgmii_rxd[*]} rgmii_rx_ctl}]
set_input_delay -clock [get_clocks enet1_rx_clk] -min 4.000 \
    [get_ports {{rgmii_rxd[*]} rgmii_rx_ctl}]

# Falling edge data (upper nibble)
set_input_delay -clock [get_clocks enet1_rx_clk] -clock_fall \
    -max 2.000 -add_delay \
    [get_ports {{rgmii_rxd[*]} rgmii_rx_ctl}]
set_input_delay -clock [get_clocks enet1_rx_clk] -clock_fall \
    -min 4.000 -add_delay \
    [get_ports {{rgmii_rxd[*]} rgmii_rx_ctl}]

#===== RGMII TX Output Delay (DDR) =====
# ODDR driven by clk_125m_tx@90°, TXC and TXD same source
set_output_delay -clock [get_clocks clk_125m_tx] -max 2.000 \
    [get_ports {{rgmii_txd[*]} rgmii_tx_ctl}]
set_output_delay -clock [get_clocks clk_125m_tx] -min -1.000 \
    [get_ports {{rgmii_txd[*]} rgmii_tx_ctl}]
set_output_delay -clock [get_clocks clk_125m_tx] -clock_fall \
    -max 2.000 -add_delay \
    [get_ports {{rgmii_txd[*]} rgmii_tx_ctl}]
set_output_delay -clock [get_clocks clk_125m_tx] -clock_fall \
    -min -1.000 -add_delay \
    [get_ports {{rgmii_txd[*]} rgmii_tx_ctl}]

# DDR multicycle: each nibble has full 8ns period
set_multicycle_path -setup \
    -from [get_clocks clk_125m_tx] \
    -to [get_ports {{rgmii_txd[*]} rgmii_tx_ctl}] 2
set_multicycle_path -hold \
    -from [get_clocks clk_125m_tx] \
    -to [get_ports {{rgmii_txd[*]} rgmii_tx_ctl}] 1

#===== Clock Groups (Async Domains) =====
# MMCM group: fpga_clk, clk_125m, clk_200m, clk_125m_tx, cpu_clk (same source)
# enet1_rx_clk: RGMII PHY recovered clock (async to MMCM group)
set_clock_groups -asynchronous \
    -group [get_clocks fpga_clk] \
    -group [get_clocks {clk_125m clk_200m clk_125m_tx cpu_clk}] \
    -group [get_clocks enet1_rx_clk]

#===== Timing Exceptions =====
# Async reset — global, no analysis needed
set_false_path -from [get_ports reset_l]

# MDIO is slow (<2.5MHz), no timing constraints needed
set_false_path -to [get_ports Eth0_MDC]
set_false_path -to [get_ports Eth0_MDIO]
set_false_path -from [get_ports Eth0_MDIO]
