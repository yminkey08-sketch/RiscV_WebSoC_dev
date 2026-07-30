# RiscV WebSoC 逻辑设计方案

**文档编号**：ED002R01

| 项目 | 内容 |
|------|------|
| 产品名称 | RiscV WebSoC |
| 密级 | 内部 |
| 总页数 | 待定 |

---

**RiscV WebSoC 项目组**

版权所有 侵权必究

---

## 修订记录 Revision Record

| 日期 Date | 修订版本 Revision Version | 修改描述 Change Description | 作者 Author |
|-----------|--------------------------|----------------------------|-------------|
| 2026-07-27 | V1.0 | 初版 — RISC-V + RGMII 以太网 Web SoC 集成架构 | haitaoz |

---

## 参考资料清单 List of Reference

1. [fpga_web 设计文档](https://buckfpga.uk/index_blog.php?post=fpga_web) — WebServer 架构参考
2. `fpga_cpu-master` — RISC-V SoC 已验证参考设计 (UART/LED 已验证)
3. `lcpu_rgmii` — RGMII 数据通路已验证参考设计 (RGMII 回环已验证)
4. `WebServer-FPGA-main` — WebServer 完整参考设计 (TCP/IP + HTTP 协议栈)
5. `ip_common/doc/常见标准接口时序.md` — 标准接口时序参考
6. `ip_common/doc/常用LRIP接口时序.md` — LRIP 内部接口时序参考
7. RTL8211F Datasheet — Realtek 千兆以太网 PHY

---

# 1 介绍

## 1.1 目的

本文档详细介绍 **RiscV WebSoC** 的 FPGA 逻辑实现原理。项目基于已验证的 PicoRV32 RISC-V 软核和 RGMII 以太网数据通路，集成为可通过网页浏览器控制 FPGA 外设（LED）的 Web 服务器 SoC。

核心技术链路：**浏览器 HTTP 请求 → 以太网帧 → RGMII PHY → FPGA MAC → 包 FIFO → RISC-V 协议栈解析 → 外设寄存器操作 → LED 控制**。

## 1.2 选型分析

### 1.2.1 FPGA 芯片

| 属性 | 内容 |
|------|------|
| 型号 | Xilinx XC7A35T-FGG484-2 |
| 系列 | Artix-7 |
| Logic Cells | 33,280 |
| Block RAM | 1,800 Kb (225 KB) |
| DSP Slices | 90 |
| GTP Transceivers | 4 |
| 速度等级 | -2 |

**选型理由**：资源满足 RISC-V SoC + 千兆以太网 MAC + TCP/IP 协议栈的完整实现，剩余资源 > 70% 可供扩展。

### 1.2.2 以太网 PHY 芯片

| 属性 | 内容 |
|------|------|
| 型号 | Realtek RTL8211F |
| 接口 | RGMII (125MHz DDR, 4-bit 数据) |
| 速率 | 10/100/1000 Mbps |
| 管理接口 | MDIO Clause 22 |
| 时钟源 | PHY 输出 RXC 125MHz (从网络链路恢复) |

**Feature**：
- 支持 10/100/1000M 自适应
- RGMII 接口：TXC/TX_CTL/TXD[3:0] + RXC/RX_CTL/RXD[3:0]
- MDIO 管理接口用于 PHY 寄存器配置 (Auto-Negotiation / Link Status)
- MDI/MDIX 自动交叉

---

# 2 设计的体系结构

## 2.1 总体结构框图

```mermaid
flowchart TB
    subgraph FPGA["FPGA (XC7A35T-FGG484)"]
        PLL["pll_50m (MMCM)
50M / 100M / 125M
(计划扩展: +200M +125M_90°)"]

        subgraph CPU_Subsys["RISC-V 子系统 (50MHz)"]
            LCPU["LCPU
JTAG/UART 调试"]
            RISCV["PicoRV32
RV32IC"]
            MERGE["lcpu_merge
双主总线仲裁"]
        end

        subgraph Periph["外设与寄存器 (50MHz)"]
            REG["reg_riscweb
LED / MDIO / CPU_FIFO"]
            BUILD["fpga_build_time
版本时间戳"]
        end

        subgraph EthPath["以太网数据通路 (125MHz)"]
            CPUCH["cpu_channel
包 FIFO 通道"]
            MAC["gmii2mac
MAC 层处理"]
            BRIDGE["rgmii_gmii_bridge
RGMII ↔ GMII + IDELAY"]
        end
    end

    PHY["RTL8211F PHY"] <-->|"RGMII
(rxc/rxd/rx_ctl)
(txc/txd/tx_ctl)"| BRIDGE
    BRIDGE <-->|"GMII
(rx_clk/rxd/rx_dv)
(txd/tx_en)"| MAC
    MAC <-->|"MAC 包流
(sop/en/data/eop)"| CPUCH
    CPUCH <-->|"CPU 读/写 FIFO
(CDC: 125M↔50M)"| REG
    LCPU -->|"LCPU 总线
(固件加载)"| MERGE
    RISCV -->|"RISC-V 总线
(协议栈访问)"| MERGE
    MERGE -->|"合并总线"| REG

    PLL -->|"50MHz"| CPU_Subsys
    PLL -->|"50MHz"| Periph
    PLL -->|"125MHz"| EthPath
    PLL -->|"200MHz"| BRIDGE

    PC["PC 浏览器"] <-->|"HTTP/TCP/IP
网线"| PHY
    UART["USB-UART"] <-->|"115200 8N1
固件加载/调试"| LCPU
    LED["LED[3:0]"] --> REG

    style PLL fill:#f9f,stroke:#333
    style EthPath fill:#bbf,stroke:#333
    style CPU_Subsys fill:#bfb,stroke:#333
```

## 2.2 数据处理流程

### 2.2.1 收包路径 (RX)

```mermaid
flowchart LR
    A["RTL8211F
PHY"] -->|"RGMII DDR"| B["rgmii_gmii_bridge
DDR→SDR
IDELAY+IDDR"]
    B -->|"GMII SDR"| C["gmii2mac
CDC + 前导码剥离
CRC32 校验"]
    C -->|"MAC 包流"| D["cpu_channel
ram2pktfifo_int
字节流→包 FIFO 写"]
    D -->|"125MHz"| E["package_fifo_v2 (RX)
异步包 FIFO
CDC: 125M→50M"]
    E -->|"50MHz"| F["reg_riscweb
CPU 读接口
(addr 0x6000-0x600F)"]
    F -->|"LCPU 总线"| G["RISC-V CPU
协议栈解析
ARP/IP/ICMP/TCP/HTTP"]
```

### 2.2.2 发包路径 (TX)

```mermaid
flowchart RL
    G2["RISC-V CPU
构造回包
HTTP 响应"] -->|"LCPU 总线"| F2["reg_riscweb
CPU 写接口
(addr 0x6100-0x610F)"]
    F2 -->|"50MHz"| E2["package_fifo_v2 (TX)
异步包 FIFO
CDC: 50M→125M"]
    E2 -->|"125MHz"| D2["cpu_channel
pktfifo2ram_int_v2 + sop_eop_gen
包 FIFO→字节流→SOP/EOP"]
    D2 -->|"MAC 包流"| C2["gmii2mac
CRC32 插入
前导码添加"]
    C2 -->|"GMII SDR"| B2["rgmii_gmii_bridge
SDR→DDR
ODDR"]
    B2 -->|"RGMII DDR"| A2["RTL8211F
PHY"]
```

## 2.3 时钟域规划

| 时钟名 | 频率 | 来源 | 使用者 |
|--------|------|------|--------|
| `clk_50m` | 50 MHz | pll_50m c0 | RISC-V CPU, LCPU, reg_riscweb, lcpu_mdio, fpga_build_time |
| `clk_125m` | 125 MHz | pll_50m c2 | gmii2mac (MAC 域), cpu_channel 数据面 |
| `clk_200m` | 200 MHz | pll_50m (计划新增) | IDELAYCTRL 参考时钟 (RGMII RX IDELAYE2) |
| `clk_125m_tx` | 125 MHz / 90° | pll_50m (计划新增) | RGMII TX ODDR (相对于 TXD/TX_CTL 偏移 90°) |
| `gmii_rx_clk` | 125 MHz | PHY RXC (经 BUFG) | gmii2mac 内部 CDC 写侧 |

**pll_50m 输出规划**：

| 输出 | 频率 | 相位 | 用途 |
|------|------|------|------|
| c0 | 50 MHz | 0° | CPU 子系统 + 外设寄存器 |
| c1 | 100 MHz | 0° | (预留) |
| c2 | 125 MHz | 0° | MAC + cpu_channel 数据面 |
| c3 (新增) | 200 MHz | 0° | IDELAYCTRL 参考时钟 |
| c4 (新增) | 125 MHz | 90° | RGMII TX ODDR 时钟 |

**跨时钟域 (CDC)**：

| 源域 | 目的域 | CDC 方式 | 所在模块 |
|------|--------|----------|----------|
| `gmii_rx_clk` (125M) | `clk_125m` (125M) | dual_clock_fifo (Gray-code 指针) | gmii2mac 内部 |
| `clk_125m` | `clk_50m` | package_fifo_v2 (双口RAM + pulse_clock_region_pass) | cpu_channel (RX) |
| `clk_50m` | `clk_125m` | package_fifo_v2 (双口RAM + pulse_clock_region_pass) | cpu_channel (TX) |

## 2.4 模块层次树

```
webserver_cpu_top.v (顶层 — 新建)
├── pll_50m (时钟管理 MMCM)                    ← fpga_cpu-master/ip_vendor (需扩展输出)
├── rgmii_gmii_bridge (RGMII ↔ GMII)           ← lcpu_rgmii 已验证
│   ├── rgmii_to_gmii (RX: DDR→SDR + IDELAYE2 + IDDR)
│   └── gmii_to_rgmii (TX: SDR→DDR + ODDR)
├── gmii2mac (MAC 层)                          ← ip_common/rtl
│   ├── dual_clock_fifo (CDC: gmii_rx_clk → clk_125m)
│   ├── eth_presemble ×2 (前导码: 剥离/插入)
│   ├── mac_rx (CRC32 校验 + SOP/EOP 生成)
│   └── mac_tx (CRC32 计算 + 4 字节 FCS 追加)
├── cpu_channel (CPU-FIFO 通道)                ← ip_common/rtl
│   ├── ram2pktfifo_int (RX 字节流→包 FIFO 写接口)
│   ├── package_fifo_v2 (RX: 125M→50M 异步包 FIFO)
│   ├── package_fifo_v2 (TX: 50M→125M 异步包 FIFO)
│   ├── pktfifo2ram_int_v2 (TX 包 FIFO 读→字节流 + IPG)
│   └── sop_eop_gen (TX 字节流→SOP/EOP 包流)
├── lcpu_riscv_wrapper (RISC-V 子系统)          ← fpga_cpu-master 已验证
│   ├── lcpu_top (JTAG/UART LCPU 调试接口)
│   ├── riscv32_top (PicoRV32 CPU 核)
│   │   ├── riscv32_localbus (本地总线译码)
│   │   ├── riscv_reg (总线寄存器桥)
│   │   ├── picorv32 (PicoRV32 RV32IC 处理器)
│   │   ├── riscv32intfbridge (内部总线桥)
│   │   └── single_clock_true_dual_port_ram (指令 RAM, 双端口)
│   └── lcpu_merge (双主 [LCPU + RISC-V] 总线仲裁)
├── reg_riscweb (寄存器映射 + CPU FIFO 接口)    ← WebServer-FPGA-main 参考
│   ├── lcpu_mdio (MDIO Clause 22 控制器)
│   └── ramintf (调试 RAM 总线接口)
└── fpga_build_time (FPGA 编译时间戳)           ← fpga_cpu-master
```

---

# 3 模块结构详细说明

## 3.1 零级模块 — RTL8211F PHY

### 3.1.1 功能描述（Feature）

- 千兆以太网 PHY (Realtek RTL8211F)
- RGMII 接口：125MHz DDR，4-bit 双向数据 + 控制信号
- MDIO Clause 22 管理接口：PHY 寄存器读写 (Auto-Negotiation, Link Status)
- TXC 由 FPGA 输出 (需 90° 相移)，RXC 由 PHY 输出 (从线路时钟恢复)

### 3.1.2 接口说明（Interface）

**表1 RTL8211F RGMII 接口信号**

| 信号名 | 位宽 | IO | 说明 |
|--------|------|----|------|
| **RGMII 发送 (FPGA → PHY)** |
| rgmii_txc | 1 | O | 125MHz TX 时钟 (90° 相移) |
| rgmii_txd | 4 | O | TX 数据 (DDR, 上升沿=bit[3:0], 下降沿=bit[7:4]) |
| rgmii_tx_ctl | 1 | O | TX 控制 (上升沿=TXEN, 下降沿=TXEN⊕TXER) |
| **RGMII 接收 (PHY → FPGA)** |
| rgmii_rxc | 1 | I | 125MHz RX 时钟 |
| rgmii_rxd | 4 | I | RX 数据 (DDR) |
| rgmii_rx_ctl | 1 | I | RX 控制 (上升沿=RXDV, 下降沿=RXDV⊕RXER) |
| **MDIO 管理** |
| Eth0_MDC | 1 | O | MDIO 时钟 (≤2.5MHz) |
| Eth0_MDIO | 1 | IO | MDIO 双向数据 |
| **复位** |
| rgmii_reset_l | 1 | O | PHY 硬件复位 (低有效, 需保持 ≥16ms) |

> **⚠️ PHY 地址待确认**：RTL8211F 的 MDIO 地址由 PHYAD[4:0] 引脚电平决定 (默认 0x01)。需查阅原理图确认。`lcpu_mdio` 模块的 `phy_addr` 参数需匹配。

## 3.2 一级 pll_50m — 时钟管理

### 3.2.1 功能描述（Feature）

| 属性 | 值 |
|------|-----|
| 模块名称 | pll_50m |
| 来源 | fpga_cpu-master/ip_vendor/xilinx_xc7a35tfgg484/pll_50m.xci |
| 原语 | Xilinx MMCME2_ADV (Clocking Wizard v6.0) |
| 输入 | 50 MHz 板载晶振 (W19) |

- 当前版本：3 路输出 (50MHz / 100MHz / 125MHz)
- 计划扩展：增加 c3=200MHz (IDELAYCTRL) + c4=125MHz 90° (RGMII TX)
- locked 信号驱动系统复位释放 (PLL 未锁定时系统保持复位)

### 3.2.2 接口说明（Interface）

**表2 pll_50m 接口信号 (扩展后)**

| 信号名 | 位宽 | IO | 说明 |
|--------|------|----|------|
| inclk0 | 1 | I | 50MHz 板载晶振输入 |
| c0 | 1 | O | 50MHz (CPU 子系统) |
| c1 | 1 | O | 100MHz (预留) |
| c2 | 1 | O | 125MHz (MAC + cpu_channel) |
| c3 | 1 | O | 200MHz (IDELAYCTRL) — **新增** |
| c4 | 1 | O | 125MHz / 90° (RGMII TX ODDR) — **新增** |

**MMCM 参数表**：

| 参数 | 值 | 说明 |
|------|-----|------|
| CLKFBOUT_MULT_F | 20.0 | VCO = 50 × 20 = 1000 MHz |
| DIVCLK_DIVIDE | 1 | 不分频 |
| CLKOUT0_DIVIDE_F | 20.0 | c0 = 1000 / 20 = 50 MHz |
| CLKOUT1_DIVIDE | 10 | c1 = 1000 / 10 = 100 MHz |
| CLKOUT2_DIVIDE_F | 8.0 | c2 = 1000 / 8 = 125 MHz |
| CLKOUT3_DIVIDE | 5 | c3 = 1000 / 5 = 200 MHz (新增) |
| CLKOUT4_DIVIDE_F | 8.0 | c4 = 125 MHz / 90° (新增) |

| locked | 1 | O | PLL 锁定指示 |

## 3.3 一级 webserver_cpu_top — 顶层

### 3.3.1 功能描述（Feature）

| 属性 | 值 |
|------|-----|
| 模块名称 | webserver_cpu_top |
| 文件路径 | rtl/webserver_cpu_top.v |
| 目标器件 | XC7A35T-FGG484-2 |

- 系统顶层，例化所有子模块并互联
- pll_50m 产生全部时钟；locked=1 后系统释放复位
- RISC-V 通过合并总线 (lcpu_merge) 访问 reg_riscweb，间接读写以太网包 FIFO
- JTAG/UART 接口用于初始固件加载
- RGMII 接口直连外部 RTL8211F PHY

### 3.3.2 内部结构

```mermaid
flowchart TB
    subgraph top["webserver_cpu_top"]
        PLL["pll_50m
(MMCM)"]
        BRIDGE["rgmii_gmii_bridge"]
        MAC["gmii2mac"]
        CPUCH["cpu_channel"]
        WRAP["lcpu_riscv_wrapper
(LCPU + RISC-V + merge)"]
        REG["reg_riscweb"]
        BUILD["fpga_build_time"]
    end

    clk_in["clk_50m_in"] --> PLL
    PLL -->|"c0:50M"| WRAP
    PLL -->|"c0:50M"| REG
    PLL -->|"c2:125M"| MAC
    PLL -->|"c2:125M"| CPUCH
    PLL -->|"c3:200M"| BRIDGE
    PLL -->|"c4:125M_90"| BRIDGE

    rgmii["RGMII"] <--> BRIDGE
    BRIDGE <-->|"GMII"| MAC
    MAC <-->|"MAC包流"| CPUCH
    CPUCH <-->|"CPU FIFO"| REG
    WRAP -->|"LCPU Bus
(req/rhwl/addr/wdata/rdata/ack)"| REG
    WRAP -->|"pram_*"| REG
    REG -->|"LED"| led["led_o[3:0]"]
    REG -->|"MDIO"| mdio["Eth0_MDC/MDIO"]
    BUILD -->|"date/time"| REG

    uart["uart_rx/tx"] <--> WRAP
```

### 3.3.3 接口说明（Interface）

**表3 webserver_cpu_top 顶层接口信号**

| 信号名 | 位宽 | IO | 说明 |
|--------|------|----|------|
| **系统** |
| clk_50m_in | 1 | I | 50MHz 板载晶振 (W19) |
| reset_l | 1 | I | 系统复位 (低有效, D21) |
| **RGMII** |
| rgmii_txc | 1 | O | TX 时钟 125MHz (AB21) |
| rgmii_txd | 4 | O | TX 数据 (AB20/Y19/AB22/W20) |
| rgmii_tx_ctl | 1 | O | TX 控制 (AA19) |
| rgmii_rxc | 1 | I | RX 时钟 125MHz (Y18) |
| rgmii_rxd | 4 | I | RX 数据 (P20/N15/AA18/AB18) |
| rgmii_rx_ctl | 1 | I | RX 控制 (T20) |
| **MDIO** |
| Eth0_MDC | 1 | O | MDIO 时钟 (R14) |
| Eth0_MDIO | 1 | IO | MDIO 数据 (U21) |
| **PHY 控制** |
| rgmii_reset_l | 1 | O | PHY 复位 (P14) |
| **UART** |
| uart_rx | 1 | I | UART RX (L21) |
| uart_tx | 1 | O | UART TX (M21) |
| **LED** |
| led_o | 4 | O | LED 输出 (U22/V22/W21/W22) |

## 3.4 一级 rgmii_gmii_bridge — RGMII ↔ GMII 桥

### 3.4.1 功能描述（Feature）

| 属性 | 值 |
|------|-----|
| 模块名称 | rgmii_gmii_bridge |
| 来源 | lcpu_rgmii/rtl/RGMII2GMIII/rgmii_gmii_bridge.v |
| 子模块 | rgmii_to_gmii, gmii_to_rgmii |

- RGMII DDR (4-bit × 250Mbps) ↔ GMII SDR (8-bit × 125MHz) 双向转换
- **RX 方向**：IDELAYE2 可调延迟 (参考 200MHz) + IDDR SAME_EDGE_PIPELINED 采样 → 8-bit GMII SDR
- **TX 方向**：ODDR OPPOSITE_EDGE (clk_125m_tx 90° 相移) → 4-bit RGMII DDR
- IDELAYCTRL 必须例化并接 200MHz 参考时钟

> **⚠️ IDELAY_VALUE 需校准**：当前 `IDELAY_TYPE="FIXED"`，20 tap × 78 ps ≈ 1.56 ns。实际值取决于 PCB 走线长度，**上板后需用示波器测量 RGMII RX 时序**，必要时调整 tap 数。`lcpu_rgmii` 用 20，`WebServer-FPGA-main` 用 16。

### 3.4.2 接口说明（Interface）

**表4 rgmii_gmii_bridge 接口信号**

| 信号名 | 位宽 | IO | 说明 |
|--------|------|----|------|
| **GMII TX (SDR 输入)** |
| gmii_tx_clk | 1 | I | 125MHz / 90° TX 时钟 |
| gmii_txd | 8 | I | 发送数据 |
| gmii_tx_en | 1 | I | 发送使能 |
| gmii_tx_er | 1 | I | 发送错误 |
| **GMII RX (SDR 输出)** |
| gmii_rx_clk | 1 | O | 恢复的接收时钟 (接 BUFG) |
| gmii_rxd | 8 | O | 接收数据 |
| gmii_rx_dv | 1 | O | 接收数据有效 |
| gmii_rx_er | 1 | O | 接收错误 |
| **RGMII (DDR)** |
| rgmii_txc | 1 | O | TX 时钟 |
| rgmii_txd | 4 | O | TX 数据 |
| rgmii_tx_ctl | 1 | O | TX 控制 |
| rgmii_rxc | 1 | I | RX 时钟 |
| rgmii_rxd | 4 | I | RX 数据 |
| rgmii_rx_ctl | 1 | I | RX 控制 |
| **控制** |
| idelay_refclk | 1 | I | IDELAYCTRL 参考时钟 200MHz |
| rst_n | 1 | I | 复位 (低有效) |

## 3.5 一级 gmii2mac — MAC 层

### 3.5.1 功能描述（Feature）

| 属性 | 值 |
|------|-----|
| 模块名称 | gmii2mac |
| 来源 | ip_common/rtl/gmii2mac.v |
| 子模块 | dual_clock_fifo, eth_presemble×2, mac_rx, mac_tx, sop_eop_gen |

- GMII SDR ↔ 内部 MAC 包流 (sop/en/data/eop/err) 双向转换
- **RX**：异步 FIFO CDC (gmii_rx_clk→clk_125m) → 前导码/SPD 剥离 → CRC32 校验
- **TX**：CRC32 计算插入 (追加 4 字节 FCS) → 前导码/SPD 插入 → GMII TX
- CRC32 多项式：`x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1`
- 统计计数器：RX/TX 正确包、CRC 错误包、FIFO 溢出计数

### 3.5.2 内部结构

```mermaid
flowchart LR
    subgraph gmii2mac["gmii2mac"]
        subgraph rx["RX Path"]
            AFIFO["dual_clock_fifo
CDC: rx_clk→125M"]
            PRE_RX["eth_presemble
剥离 7×0x55+0xD5"]
            MAC_RX["mac_rx
CRC32 check
sop/eop/err"]
        end
        subgraph tx["TX Path"]
            MAC_TX["mac_tx
CRC32 calc
append 4B FCS"]
            PRE_TX["eth_presemble
插入 7×0x55+0xD5"]
        end
    end
    GMII_RX["GMII RX
(rx_clk域)"] --> AFIFO --> PRE_RX --> MAC_RX --> MS_RX["MAC RX包流
(125M域)"]
    MS_TX["MAC TX包流
(125M域)"] --> MAC_TX --> PRE_TX --> GMII_TX["GMII TX"]
```

### 3.5.3 接口说明（Interface）

**表5 gmii2mac 接口信号**

| 信号名 | 位宽 | IO | 说明 |
|--------|------|----|------|
| **系统** |
| clk | 1 | I | 125MHz MAC 系统时钟 |
| reset_l | 1 | I | 复位 (低有效) |
| **GMII RX (gmii_rx_clk 域)** |
| Eth_RXC | 1 | I | 接收时钟 125MHz |
| Eth_RXDV | 1 | I | 接收数据有效 |
| Eth_RXER | 1 | I | 接收错误 |
| Eth_RXD | 8 | I | 接收数据 |
| **GMII TX (clk 域)** |
| Eth_TXD | 8 | O | 发送数据 |
| Eth_TXEN | 1 | O | 发送使能 |
| Eth_TXER | 1 | O | 发送错误 |
| **MAC RX 包流输出 (clk 域)** |
| mac_rx_sop | 1 | O | 包起始脉冲 |
| mac_rx_en | 1 | O | 数据有效 |
| mac_rx_data | 8 | O | 数据字节 |
| mac_rx_eop | 1 | O | 包结束脉冲 |
| mac_rx_err | 1 | O | 包错误标志 |
| **MAC TX 包流输入 (clk 域)** |
| mac_tx_sop | 1 | I | 包起始脉冲 |
| mac_tx_en | 1 | I | 数据有效 |
| mac_tx_data | 8 | I | 数据字节 |
| mac_tx_eop | 1 | I | 包结束脉冲 |
| mac_tx_err | 1 | I | 错误标志 |
| **统计 (可选)** |
| rx_correct_pkt_cnt | 32 | O | RX 正确包计数 |
| rx_crc_err_pkt_cnt | 32 | O | RX CRC 错误计数 |
| tx_correct_pkt_cnt | 32 | O | TX 正确包计数 |

## 3.6 一级 cpu_channel — CPU-FIFO 通道

### 3.6.1 功能描述（Feature）

| 属性 | 值 |
|------|-----|
| 模块名称 | cpu_channel |
| 来源 | ip_common/rtl/cpu_channel.v |
| 参数 | addr_width=11, data_width=8, para_width=1, block_mode=false |
| 子模块 | ram2pktfifo_int, package_fifo_v2×2, pktfifo2ram_int_v2, sop_eop_gen |

- CPU 与以太网 MAC 之间的双向包 FIFO 桥
- **RX (MAC→CPU)**：MAC 字节流 → ram2pktfifo_int (字节流→包写) → RX package_fifo_v2 (125M→50M CDC) → CPU 读端口
- **TX (CPU→MAC)**：CPU 写端口 → TX package_fifo_v2 (50M→125M CDC) → pktfifo2ram_int_v2 (包读→字节流+IPG) → sop_eop_gen → MAC 包流
- CDC 使用异步双口 RAM + pulse_clock_region_pass (脉冲跨时钟域)
- 支持可选包过滤 (字节偏移匹配)
- 默认包缓冲：2048 字节 / 包

### 3.6.2 数据流结构

```mermaid
flowchart TB
    subgraph cpu_channel["cpu_channel"]
        subgraph rx["RX: MAC→CPU (125MHz→50MHz)"]
            R2P["ram2pktfifo_int
字节流转包写接口"]
            PKT_RX["package_fifo_v2
RX异步包FIFO
(125M→50M CDC)"]
        end
        subgraph tx["TX: CPU→MAC (50MHz→125MHz)"]
            PKT_TX["package_fifo_v2
TX异步包FIFO
(50M→125M CDC)"]
            P2R["pktfifo2ram_int_v2
包读→字节流
+ IPG=12 cycles"]
            SOP["sop_eop_gen
字节流→SOP/EOP"]
        end
    end
    MAC_RX["MAC RX包流
(125MHz)"] --> R2P --> PKT_RX --> CPU_RD["CPU 读接口
(50MHz)"]
    CPU_WR["CPU 写接口
(50MHz)"] --> PKT_TX --> P2R --> SOP --> MAC_TX["MAC TX包流
(125MHz)"]
```

### 3.6.3 接口说明（Interface）

**表6 cpu_channel 接口信号**

| 信号名 | 位宽 | IO | 说明 |
|--------|------|----|------|
| **系统** |
| clk | 1 | I | MAC 侧时钟 125MHz |
| cpu_clk | 1 | I | CPU 侧时钟 50MHz |
| reset_l | 1 | I | 复位 (低有效) |
| **MAC RX 输入 (125MHz)** |
| mac_rx_sop/eop/en/err | 1 | I | MAC 包流控制 |
| mac_rx_data | 8 | I | 接收数据字节 |
| **MAC TX 输出 (125MHz)** |
| mac_tx_sop/eop/en/err | 1 | O | MAC 包流控制 |
| mac_tx_data | 8 | O | 发送数据字节 |
| **CPU 读 (50MHz)** |
| cpu_rd_empty | 1 | O | 读 FIFO 空 (1=无包) |
| cpu_rd_rpkt_pop | 1 | I | 弹出当前包 (脉冲) |
| cpu_rd_rpkt_len | 12 | O | 包长度 (字节数) |
| cpu_rd_ren | 1 | I | 读使能 (电平) |
| cpu_rd_raddr | 11 | I | 字节偏移地址 |
| cpu_rd_rdata | 8 | O | 读出数据字节 |
| cpu_rd_reop_pre | 1 | O | EOP 前 1 周期指示 |
| **CPU 写 (50MHz)** |
| cpu_wr_full | 1 | O | 写 FIFO 满 (1=满) |
| cpu_wr_wen | 1 | I | 写使能 (脉冲) |
| cpu_wr_waddr | 11 | I | 写地址 |
| cpu_wr_wdata | 8 | I | 写数据字节 |
| cpu_wr_wpkt_len | 12 | I | 包长度 |
| cpu_wr_wpkt_push | 1 | I | 推送包 (脉冲) |
| **过滤/调试** |
| recv_pkt_drop_cnt | 8 | O | 被过滤丢弃的包计数 |

## 3.7 一级 lcpu_riscv_wrapper — RISC-V 子系统

### 3.7.1 功能描述（Feature）

| 属性 | 值 |
|------|-----|
| 模块名称 | lcpu_riscv_wrapper |
| 来源 | fpga_cpu-master/rtl/lcpu_riscv_wrapper.v (已验证) |
| 子模块 | lcpu_top, riscv32_top, lcpu_merge |

- RISC-V 子系统完整封装
- **LCPU**：JTAG/UART 调试接口，固件加载到指令 RAM
- **PicoRV32**：RV32IC 处理器，从指令 RAM 取指，通过 intfbridge 访问外设总线
- **lcpu_merge**：双主 (LCPU + RISC-V) 总线仲裁，合并后输出到 reg_riscweb

**关键参数**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| lcpu_type | "xilinx" | LCPU 接口类型 |
| riscv_inst_en | 1 | 使能 RISC-V CPU |
| instr_databits | 32 | 指令位宽 |
| init_addr_width | 13 | 指令 RAM 地址位宽 (8K words) |
| init_addr_depth | 8192 | 指令 RAM 深度 |
| device_vendor | "xilinx" | 目标器件 |
| instr_ram_type | "block" | Block RAM 类型 |

### 3.7.2 接口说明（Interface）

**表7 lcpu_riscv_wrapper 接口信号**

| 信号名 | 位宽 | IO | 说明 |
|--------|------|----|------|
| clk | 1 | I | 50MHz 时钟 |
| reset_l | 1 | I | 复位 |
| uart_rx/tx | 1 | I/O | UART |
| riscv_reset_l | 1 | I | RISC-V 复位控制 |
| pram_wr/addr/wdata/rdata | — | — | 指令 RAM 写接口 |
| req/rhwl/wdata/address | — | O | 合并总线请求 |
| ack/rdata | — | I | 合并总线响应 |

## 3.8 一级 reg_riscweb — 寄存器映射

### 3.8.1 功能描述（Feature）

| 属性 | 值 |
|------|-----|
| 模块名称 | reg_riscweb |
| 来源 | WebServer-FPGA-main/rtl/reg_riscweb.v (参考) |
| 子模块 | lcpu_mdio, ramintf |

- LCPU 总线地址译码 (address[15:0])，映射到内部寄存器 / 子总线 / CPU FIFO
- LED 控制寄存器
- MDIO 子总线 (地址 0x1000-0x1FFF) 透传
- CPU 读 FIFO 寄存器组 (地址 0x6000-0x600F)
- CPU 写 FIFO 寄存器组 (地址 0x6100-0x610F)
- 以太网统计计数器
- 总线请求超时保护 (>0xF000 周期 → 返回 0xDEADDEAD)

### 3.8.2 寄存器地址映射

**表8 reg_riscweb 寄存器映射**

| 地址 | 寄存器 | R/W | 说明 |
|------|--------|-----|------|
| **系统 (0x0000-0x0FFF)** |
| 0x00 | version_time | R | FPGA 编译时间 |
| 0x01 | Eth_GRESET | R/W | 以太网 PHY 复位 [0] |
| 0x10 | debug_RW_0 | R/W | [31:16]=filter_data, [15:0]=filter_offset |
| 0x30 | **Led** | **R/W** | **LED 控制 [3:0]** |
| **以太网统计 (0x100-0x1FF)** |
| 0x100 | eth_rx_good | R | RX 正确包计数 |
| 0x101 | eth_rx_crc_err | R | RX CRC 错误计数 |
| 0x102 | eth_tx_good | R | TX 正确包计数 |
| **MDIO 子总线 (0x1000-0x1FFF)** |
| 0x1000 | mdio_reg_* | R/W | MDIO 控制器 (透传 lcpu_mdio) |
| **CPU 读 FIFO (0x6000-0x600F)** |
| 0x6000 | cpu_rd_empty | R | 空标志 (1=无包) |
| 0x6001 | cpu_rd_rpkt_pop | W | 弹出包 (脉冲) |
| 0x6002 | cpu_rd_rpkt_len | R | 包长 (字节) |
| 0x6005 | cpu_rd_raddr | W | 读地址 |
| 0x6006 | cpu_rd_rdata | R | 读数据 [7:0] |
| **CPU 写 FIFO (0x6100-0x610F)** |
| 0x6100 | cpu_wr_full | R | 满标志 (1=满) |
| 0x6102 | cpu_wr_waddr | W | 写地址 |
| 0x6103 | cpu_wr_wdata | W | 写数据 [7:0] |
| 0x6104 | cpu_wr_wpkt_len | W | 包长 |
| 0x6106 | cpu_wr_wpkt_push | W | 推送包 (脉冲) |

---

# 4 C 固件软件架构

## 4.1 协议栈层次

```
reset_entry (0x00000000) → program_main()
  ├─ designInit()           ← SW 版本号 / PHY 初始化 (MDIO)
  └─ while(1):
       ├─ eth_proc()        ← 以太网帧处理
       │    ├─ arp_reply()  ← ARP 请求 → 应答
       │    └─ ip_proc()    ← IP 包处理
       │         ├─ icmp_reply()    ← Ping 响应
       │         └─ tcp_handler()   ← TCP 状态机
       │              ├─ LISTEN → SYN_RECEIVED → ESTABLISHED
       │              ├─ DATA → http_handler()
       │              │    ├─ GET  → 返回 HTML 页面 (LED 状态)
       │              │    └─ POST → 解析 JSON → 写 LED 寄存器
       │              └─ FIN → CLOSE
       └─ heart_beat()      ← LED 心跳指示
```

## 4.2 CPU 操作包 FIFO 流程

### 读包 (RX)

```
1. while (LCPU_RD_EMPTY())    // 轮询地址 0x6000, 等待 =0
2. len = LCPU_RD_PKT_LEN()    // 读地址 0x6002, 获取包长度
3. for i in 0..len-1:
     LCPU_WR_RADDR(i)         // 写地址 0x6005, 设置字节偏移
     byte[i] = LCPU_RD_DATA() // 读地址 0x6006, 获取字节
4. LCPU_RD_POP()              // 写地址 0x6001=1, 释放包
```

### 写包 (TX)

```
1. while (LCPU_WR_FULL())     // 轮询地址 0x6100, 等待 =0
2. for i in 0..len-1:
     LCPU_WR_ADDR(i)          // 写地址 0x6102, 设置字节偏移
     LCPU_WR_DATA(byte[i])    // 写地址 0x6103, 写入字节
3. LCPU_WR_PKT_LEN(len)       // 写地址 0x6104, 设置包长度
4. LCPU_WR_PKT_PUSH()         // 写地址 0x6106=1, 推送发送
```

## 4.3 C 固件内存映射

```c
#define LCPU_BASE       0x80000000  // 外设总线基址
#define REG_LED         0x00000030  // LED [3:0]
#define REG_ETH_RESET   0x00000001  // 以太网复位
// CPU 读 FIFO
#define REG_RD_EMPTY    0x00006000
#define REG_RD_POP      0x00006001
#define REG_RD_LEN      0x00006002
#define REG_RD_RADDR    0x00006005
#define REG_RD_DATA     0x00006006
// CPU 写 FIFO
#define REG_WR_FULL     0x00006100
#define REG_WR_WADDR    0x00006102
#define REG_WR_WDATA    0x00006103
#define REG_WR_PKT_LEN  0x00006104
#define REG_WR_PUSH     0x00006106
```

---

# 5 引脚约束

| 信号 | 引脚 | IOSTANDARD |
|------|------|------------|
| clk_50m_in | W19 | LVCMOS33 |
| reset_l | D21 | LVCMOS33 |
| uart_rx | L21 | LVCMOS33 |
| uart_tx | M21 | LVCMOS33 |
| led_o[3:0] | U22/V22/W21/W22 | LVCMOS33 |
| rgmii_txc | AB21 | LVCMOS33 |
| rgmii_txd[3:0] | AB20/Y19/AB22/W20 | LVCMOS33 |
| rgmii_tx_ctl | AA19 | LVCMOS33 |
| rgmii_rxc | Y18 | LVCMOS33 |
| rgmii_rxd[3:0] | P20/N15/AA18/AB18 | LVCMOS33 |
| rgmii_rx_ctl | T20 | LVCMOS33 |
| rgmii_reset_l | P14 | LVCMOS33 |
| Eth0_MDC | R14 | LVCMOS33 |
| Eth0_MDIO | U21 | LVCMOS33 |

## 5.1 时序约束

```tcl
# ===== 输入时钟 =====
create_clock -period 20.000 -name clk_50m_in [get_ports clk_50m_in]

# RGMII RXC (来自 PHY, 125MHz 源同步)
create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]

# ===== RGMII RX 输入延迟 (源同步) =====
set_input_delay -clock [get_clocks rgmii_rxc] -max 2.000 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock [get_clocks rgmii_rxc] -min 4.000 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock [get_clocks rgmii_rxc] -clock_fall -max 2.000 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock [get_clocks rgmii_rxc] -clock_fall -min -1.000 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]

# ===== RGMII TX 输出延迟 (源同步) =====
set_output_delay -clock [get_clocks clk_125m_tx] -max 2.000 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock [get_clocks clk_125m_tx] -min -1.000 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock [get_clocks clk_125m_tx] -clock_fall -max 2.000 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock [get_clocks clk_125m_tx] -clock_fall -min -1.000 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]

# 保持时间多周期约束
set_multicycle_path -hold -from [get_clocks clk_125m_tx] -to [get_ports {rgmii_txd[*] rgmii_tx_ctl}] 1

# ===== 异步时钟域 false path =====
set_false_path -from [get_clocks rgmii_rxc] -to [get_clocks -of [get_pins pll_inst/*/CLKOUT0]]
set_false_path -from [get_clocks -of [get_pins pll_inst/*/CLKOUT0]] -to [get_clocks rgmii_rxc]
```

---

## 表目录 List of Tables

| 表编号 | 表名 |
|--------|------|
| 表1 | RTL8211F RGMII 接口信号 |
| 表2 | pll_50m 接口信号 (扩展后) |
| 表3 | webserver_cpu_top 顶层接口信号 |
| 表4 | rgmii_gmii_bridge 接口信号 |
| 表5 | gmii2mac 接口信号 |
| 表6 | cpu_channel 接口信号 |
| 表7 | lcpu_riscv_wrapper 接口信号 |
| 表8 | reg_riscweb 寄存器映射 |

## 图目录 List of Figures

| 图编号 | 图名 |
|--------|------|
| 图1 | 总体结构框图 |
| 图2 | 数据处理流程 (RX/TX) |
| 图3 | webserver_cpu_top 内部结构 |
| 图4 | gmii2mac RX/TX 路径 |
| 图5 | cpu_channel 数据流结构 |
| 图6 | C 固件协议栈层次 |

## 缩略语清单 List of Abbreviations

| 缩略语 | 英文全名 | 中文解释 |
|--------|----------|----------|
| RISC-V | — | 开源 RISC 指令集架构 |
| SoC | System on Chip | 片上系统 |
| RGMII | Reduced Gigabit Media Independent Interface | 精简千兆介质无关接口 |
| GMII | Gigabit Media Independent Interface | 千兆介质无关接口 |
| MAC | Media Access Control | 媒体访问控制 |
| PHY | Physical Layer | 物理层 |
| MDIO | Management Data Input/Output | 管理数据输入输出 |
| MMCM | Mixed-Mode Clock Manager | 混合模式时钟管理器 |
| CDC | Clock Domain Crossing | 跨时钟域 |
| CRC | Cyclic Redundancy Check | 循环冗余校验 |
| TCP | Transmission Control Protocol | 传输控制协议 |
| IP | Internet Protocol | 互联网协议 |
| HTTP | Hypertext Transfer Protocol | 超文本传输协议 |
| ARP | Address Resolution Protocol | 地址解析协议 |
| ICMP | Internet Control Message Protocol | 互联网控制消息协议 |
| LCPU | Link-Real CPU | LRIP 调试 CPU 接口协议 |
| BFM | Bus Functional Model | 总线功能模型 |
| IPG | Inter-Packet Gap | 包间间隔 |
| SOP | Start of Packet | 包起始 |
| EOP | End of Packet | 包结束 |
| DDR | Double Data Rate | 双边沿数据速率 |
| SDR | Single Data Rate | 单边沿数据速率 |
