//-----------------------------------------------------------------
// tb_webserver_cpu_top.v — RiscV WebSoC 仿真 Testbench
// sim_mod=1: PLL bypass + LCPU BFM 固件加载
//-----------------------------------------------------------------
`timescale 1ns / 1ps

module tb_webserver_cpu_top;

  // 时钟 / 复位
  reg        clk_50m_in;
  reg        reset_l;

  // RGMII (不接, 只验证编译 + 总线通路)
  wire       rgmii_txc;
  wire [3:0] rgmii_txd;
  wire       rgmii_tx_ctl;
  reg        rgmii_rxc;
  reg  [3:0] rgmii_rxd;
  reg        rgmii_rx_ctl;

  // MDIO
  wire       Eth0_MDC;
  wire       Eth0_MDIO;
  wire       rgmii_reset_l;

  // UART
  reg        uart_rx;
  wire       uart_tx;

  // LED
  wire [3:0] led_o;

  // DUT
  webserver_cpu_top #(
      .sim_mod(1)
  ) u_dut (
      .clk_50m_in    (clk_50m_in),
      .reset_l       (reset_l),
      .rgmii_txc     (rgmii_txc),
      .rgmii_txd     (rgmii_txd),
      .rgmii_tx_ctl  (rgmii_tx_ctl),
      .rgmii_rxc     (rgmii_rxc),
      .rgmii_rxd     (rgmii_rxd),
      .rgmii_rx_ctl  (rgmii_rx_ctl),
      .Eth0_MDC      (Eth0_MDC),
      .Eth0_MDIO     (Eth0_MDIO),
      .rgmii_reset_l (rgmii_reset_l),
      .uart_rx       (uart_rx),
      .uart_tx       (uart_tx),
      .led_o         (led_o)
  );

  // 50MHz 时钟
  initial clk_50m_in = 1'b0;
  always #10 clk_50m_in = ~clk_50m_in;

  // RGMII 输入信号默认值 (不接 PHY)
  initial begin
    rgmii_rxc    = 1'b0;
    rgmii_rxd    = 4'd0;
    rgmii_rx_ctl = 1'b0;
    uart_rx      = 1'b1;
  end

  // RGMII RX 时钟 125MHz (仿真用 50MHz 近似)
  always #10 rgmii_rxc = ~rgmii_rxc;

  // 复位序列
  initial begin
    reset_l = 1'b0;
    #200;
    reset_l = 1'b1;
  end

  // 仿真控制 (不用 VCD 加速仿真)
  initial begin
    $display("============================================================");
    $display(" tb_webserver_cpu_top — RiscV WebSoC 仿真");
    $display(" sim_mod=1 (PLL bypass + LCPU BFM)");
    $display("============================================================");

    @(negedge clk_50m_in);
    $display("[%0t] 复位释放", $time);
  end

  // 超时 (5ms 足够诊断)
  initial begin
    #5_000_000;
    $display("[%0t] 仿真超时", $time);
    $display("  LED = %b", led_o);
    $finish;
  end

  // RISC-V 诊断
  wire riscv_req    = u_dut.u_riscv.riscv_req;
  wire riscv_clk    = u_dut.u_riscv.clk;
  wire riscv_reset  = u_dut.u_riscv.riscv_reset_l;
  wire riscv_pram_wr = u_dut.u_riscv.pram_wr;

  initial begin
    #50000; // after reset
    $display("[%0t] DIAG: riscv_clk=%b riscv_reset_l=%b pram_wr=%b riscv_req=%b",
             $time, riscv_clk, riscv_reset, riscv_pram_wr, riscv_req);

    #1000000;
    $display("[%0t] DIAG: riscv_clk=%b riscv_reset_l=%b pram_wr=%b riscv_req=%b",
             $time, riscv_clk, riscv_reset, riscv_pram_wr, riscv_req);

    #5000000;
    $display("[%0t] DIAG: riscv_clk=%b riscv_reset_l=%b pram_wr=%b riscv_req=%b LED=%b",
             $time, riscv_clk, riscv_reset, riscv_pram_wr, riscv_req, led_o);
  end

  // LED 变化监控
  reg [3:0] prev_led;
  initial prev_led = 4'hf;
  always @(posedge clk_50m_in) begin
    if (led_o !== prev_led) begin
      $display("[%0t] LED: %b → %b  (bus_addr=0x%h bus_req=%b)", $time, prev_led, led_o, u_dut.bus_address, u_dut.bus_req);
      prev_led <= led_o;
    end
  end

endmodule
