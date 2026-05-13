`include "../core/defines.v"

module tinyriscv_soc_top_with_bridge(

    input wire clk,
    input wire rst,

    output wire over,        // 测试是否完成信号
    output wire succ,        // 测试是否成功信号

    output wire halted_ind,  // jtag是否已经halt住CPU信号

    input wire uart_debug_pin, // 串口下载使能引脚

    output wire uart_tx_pin, // UART发送引脚
    input wire uart_rx_pin,  // UART接收引脚
    inout wire[1:0] gpio,    // GPIO引脚

    input wire jtag_TCK,     // JTAG TCK引脚
    input wire jtag_TMS,     // JTAG TMS引脚
    input wire jtag_TDI,     // JTAG TDI引脚
    output wire jtag_TDO,    // JTAG TDO引脚

    input wire spi_miso,     // SPI MISO引脚
    output wire spi_mosi,    // SPI MOSI引脚
    output wire spi_ss,      // SPI SS引脚
    output wire spi_clk     // SPI CLK引脚

    );

    wire [`BridgeBus] bmaster_TX_data; // 桥接模块的主接口数据输出总线
    wire [`BridgeBus] bmaster_RX_data; // 桥接模块的主接口
    wire [`BridgeBus] bslave_TX_data;  // 桥接模块的从接口数据输出总线
    wire [`BridgeBus] bslave_RX_data;  // 桥接模块的从接口数据输入总线

    tinyriscv_soc_top u_tinyriscv_soc_top (
        .clk(clk),
        .rst(rst),
        .over(over),
        .succ(succ),
        .halted_ind(halted_ind),
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .gpio(gpio),
        .jtag_TCK(jtag_TCK),
        .jtag_TMS(jtag_TMS),
        .jtag_TDI(jtag_TDI),
        .jtag_TDO(jtag_TDO),
        .spi_miso(spi_miso),
        .spi_mosi(spi_mosi),
        .spi_ss(spi_ss),
        .spi_clk(spi_clk),

        // 桥接接口连接
        .bmaster_TX_data(bmaster_TX_data),
        .bmaster_RX_data(bmaster_RX_data)
    );

    bridge_slave_top u_bridge_slave_top (
        .clk(clk),
        .rst(rst),
        .bslave_RX_data(bmaster_TX_data), // 连接桥接主接口的输出
        .bslave_TX_data(bmaster_RX_data)  // 连接桥接主接口的输入
    );

endmodule
