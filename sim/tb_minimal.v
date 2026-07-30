`timescale 1ns/1ps
module tb_minimal;
  reg clk, rst_n;
  wire [3:0] led;
  wire pll_locked, riscv_reset_l;
  wire pram_wr, pram_rlwh; wire [15:0] pram_addr; wire [31:0] pram_wdata, pram_rdata;
  wire bus_req, bus_rhwl, bus_ack;
  wire [31:0] bus_wdata, bus_address, bus_rdata;
  wire uart_tx;
  wire [31:0] cpu_rd_len, cpu_rd_rdata, cpu_rd_raddr, cpu_wr_waddr, cpu_wr_wdata, cpu_wr_len;
  wire [0:0] cpu_rd_empty, cpu_rd_reop, cpu_wr_full, cpu_rd_pop, cpu_rd_ren, cpu_wr_wen, cpu_wr_push;

  initial clk = 0; always #10 clk = ~clk;
  initial begin rst_n = 0; #200; rst_n = 1; end

  assign pll_locked = 1'b1;
  assign cpu_rd_empty = 1'b1; assign cpu_rd_len = 0; assign cpu_rd_rdata = 0;
  assign cpu_rd_reop = 0; assign cpu_wr_full = 0;

  lcpu_riscv_wrapper #(
      .sim_mod(1), .lcpu_type("xilinx"), .uart_baud_rate(115200),
      .riscv_inst_en(1), .instr_databits(32), .init_addr_width(13),
      .init_addr_depth(2048), .device_vendor("xilinx"),
      .instr_ram_type("block"), .init_blockram_size(8)
  ) u_riscv (
      .clk(clk), .reset_l(rst_n), .uart_rx(1'b1), .uart_tx(uart_tx),
      .riscv_reset_l(riscv_reset_l),
      .pram_wr(pram_wr), .pram_addr(pram_addr),
      .pram_wdata(pram_wdata), .pram_rdata(pram_rdata),
      .req(bus_req), .rhwl(bus_rhwl), .wdata(bus_wdata),
      .address(bus_address), .ack(bus_ack), .rdata(bus_rdata)
  );

  lcpu_fpga_test u_reg (
      .clk(clk), .rst_n(rst_n),
      .req(bus_req), .rhwl(bus_rhwl), .wdata(bus_wdata),
      .address(bus_address), .rdata(bus_rdata), .ack(bus_ack),
      .RAMIF_program_ram_Ram_RlWh(pram_rlwh),
      .RAMIF_program_ram_Ram_Addr(pram_addr),
      .RAMIF_program_ram_Ram_WrData(pram_wdata),
      .RAMIF_program_ram_Ram_RdData(pram_rdata),
      .fpga_build_date(32'h20260727), .fpga_build_time(32'h00000001),
      .led(led), .pll_locked(pll_locked),
      .riscv_reset_l(riscv_reset_l),
      .cpu_rd_empty(cpu_rd_empty), .cpu_rd_rpkt_len(cpu_rd_len),
      .cpu_rd_rdata(cpu_rd_rdata), .cpu_rd_reop_pre(cpu_rd_reop),
      .cpu_wr_full(cpu_wr_full)
  );
  assign pram_wr = pram_rlwh;

  initial begin
    $display("=== MINIMAL TEST ===");
    #50000; $display("[%0t] LED=%b rst=%b", $time, led, riscv_reset_l);
    #5000000; $display("[%0t] LED=%b rst=%b", $time, led, riscv_reset_l);
    #5000000;
    if (led !== 4'hf) $display("SUCCESS: LED changed!");
    else $display("FAIL: LED = %b (unchanged)", led);
    $finish;
  end
endmodule
