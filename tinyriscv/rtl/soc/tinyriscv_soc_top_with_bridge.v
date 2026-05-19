`include "../core/defines.v"

module tinyriscv_soc_top_with_bridge(

    input wire clk,
    input wire rst,

    output wire succ,        // 测试是否成功信号

    input wire uart_debug_pin, // 串口下载使能引脚

    output wire uart_tx_pin, // UART发送引脚
    input wire uart_rx_pin,  // UART接收引脚

    inout wire io_sda, // IIC数据总线
    output io_scl,       // IIC时钟总线
    output wire [2:0] pwm_o 

    );

    wire [`BridgeBus] bmaster_TX_data; // 桥接模块的主接口数据输出总线
    wire [`BridgeBus] bmaster_RX_data; // 桥接模块的主接口
    wire [`BridgeBus] bslave_TX_data;  // 桥接模块的从接口数据输出总线
    wire [`BridgeBus] bslave_RX_data;  // 桥接模块的从接口数据输入总线

    //IIC模块总线
    wire SCL_o ;  
    wire SDA_o ;
    wire SDA_oe_o ;
    wire SDA_i ;

    tinyriscv_soc_top u_tinyriscv_soc_top (
        .clk(clk),
        .rst(rst),
        
        .succ(succ),
        
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),

        // 桥接接口连接
        .bmaster_TX_data(bmaster_TX_data),
        .bmaster_RX_data(bmaster_RX_data),
        // IIC模块接口
        .SCL_o(SCL_o) ,  
        .SDA_o(SDA_o) ,  
        .SDA_oe_o(SDA_oe_o), 
        .SDA_i(SDA_i)  ,
        .pwm_o(pwm_o)

        );

    bridge_slave_top u_bridge_slave_top (
        .clk(clk),
        .rst(rst),
        .bslave_RX_data(bmaster_TX_data), // 连接桥接主接口的输出
        .bslave_TX_data(bmaster_RX_data)  // 连接桥接主接口的输入
    );

    assign io_scl = SCL_o ;
    assign io_sda = SDA_oe_o ? ( SDA_o ? 1'bz : 1'b0 ) : 1'bz ;  // 需要核实正确性
    assign SDA_i = io_sda ;

endmodule

    // inout wire[1:0] gpio,    // GPIO引脚
    // input wire jtag_TCK,     // JTAG TCK引脚
    // input wire jtag_TMS,     // JTAG TMS引脚
    // input wire jtag_TDI,     // JTAG TDI引脚
    // output wire jtag_TDO,    // JTAG TDO引脚
    // input wire spi_miso,     // SPI MISO引脚
    // output wire spi_mosi,    // SPI MOSI引脚
    // output wire spi_ss,      // SPI SS引脚
    // output wire spi_clk     // SPI CLK引脚
    // output wire halted_ind,  // jtag是否已经halt住CPU信号
    // output wire over,        // 测试是否完成信号

    // .gpio(gpio),
    // .jtag_TCK(jtag_TCK),
    // .jtag_TMS(jtag_TMS),
    // .jtag_TDI(jtag_TDI),
    // .jtag_TDO(jtag_TDO),
    // .spi_miso(spi_miso),
    // .spi_mosi(spi_mosi),
    // .spi_ss(spi_ss),
    // .spi_clk(spi_clk),

    // .over(  ),
    // .halted_ind(  ),

    // wire[1:0] gpio;    // GPIO引脚
    // wire jtag_TCK;     // JTAG TCK引脚
    // wire jtag_TMS;     // JTAG TMS引脚
    // wire jtag_TDI;     // JTAG TDI引脚
    // wire jtag_TDO;    // JTAG TDO引脚
    // wire spi_miso;     // SPI MISO引脚
    // wire spi_mosi;    // SPI MOSI引脚
    // wire spi_ss;      // SPI SS引脚
    // wire spi_clk;     // SPI CLK引脚
    // wire halted_ind;  // jtag是否已经halt住CPU信号
    // wire over;        // 测试是否完成信号