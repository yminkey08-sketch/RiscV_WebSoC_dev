//-----------------------------------------------------------------
// pll_50m_bypass.v — PLL 旁路 (仿真用)
// 5 路时钟: 50/100/125/200/125_90
//-----------------------------------------------------------------

module pll_50m (
    input  inclk0,
    output c0,
    output c1,
    output c2,
    output c3,
    output c4,
    output locked
);

    // Bypass: 所有输出直通输入 50MHz
    assign c0 = inclk0;  // 50MHz  (CPU)
    assign c1 = inclk0;  // 100MHz (预留, 仿真用50M)
    assign c2 = inclk0;  // 125MHz (MAC)
    assign c3 = inclk0;  // 200MHz (IDELAYCTRL, 仿真用50M)
    assign c4 = inclk0;  // 125MHz 90° (RGMII TX)

    // locked 延迟释放
    reg        locked_r;
    reg [7:0]  cnt;

    initial begin
        locked_r = 1'b0;
        cnt      = 8'd0;
    end

    always @(posedge inclk0) begin
        if (!locked_r) begin
            if (cnt < 8'd200) cnt <= cnt + 1;
            else              locked_r <= 1'b1;
        end
    end

    assign locked = locked_r;

endmodule
