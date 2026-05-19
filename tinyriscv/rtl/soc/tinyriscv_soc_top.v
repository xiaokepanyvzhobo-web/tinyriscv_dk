 /*                                                                      
 Copyright 2020 Blue Liang, liangkangnan@163.com
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
 Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */

`include "../core/defines.v"

// tinyriscv soc椤跺眰妯″潡
module tinyriscv_soc_top(

    input wire clk,
    input wire rst,

    output reg succ,         // 娴嬭瘯鏄惁鎴愬姛淇″彿

    input wire uart_debug_pin, // 涓插彛涓嬭浇浣胯兘寮曡剼

    output wire uart_tx_pin, // UART鍙戦€佸紩鑴?
    input wire uart_rx_pin,  // UART鎺ユ敹寮曡剼

    output wire [`BridgeBus] bmaster_TX_data, // 渚沯tag妯″潡浣跨敤鐨勬ˉ鎺ヤ富鎺ュ彛鏁版嵁鎬荤嚎
    input wire [`BridgeBus] bmaster_RX_data,   // 渚沯tag妯″潡浣跨敤鐨勬ˉ鎺ヤ富鎺ュ彛鏁版嵁鎬荤嚎

    output wire SCL_o ,  
    output wire SDA_o ,  
    output wire SDA_oe_o, 
    input  wire SDA_i  

    // inout wire[1:0] gpio,    // GPIO寮曡剼

    // input wire jtag_TCK,     // JTAG TCK寮曡剼
    // input wire jtag_TMS,     // JTAG TMS寮曡剼
    // input wire jtag_TDI,     // JTAG TDI寮曡剼
    // output wire jtag_TDO,    // JTAG TDO寮曡剼

    // input wire spi_miso,     // SPI MISO寮曡剼
    // output wire spi_mosi,    // SPI MOSI寮曡剼
    // output wire spi_ss,      // SPI SS寮曡剼
    // output wire spi_clk     // SPI CLK寮曡剼

    // output reg over,         // 娴嬭瘯鏄惁瀹屾垚淇″彿
    // output wire halted_ind,  // jtag鏄惁宸茬粡halt浣廋PU淇″彿

    );

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            //over <= 1'b1;
            succ <= 1'b1;
        end else begin
            //over <= ~u_tinyriscv.u_regs.regs[26];  // when = 1, run over
            succ <= ~u_tinyriscv.u_regs.regs[27];  // when = 1, run succ, otherwise fail
        end
    end

    // master 0 interface
    wire m0_req_i;
    wire m0_we_i;
    wire m0_ack_o;
    wire[`MemAddrBus] m0_addr_i;
    wire[`MemBus] m0_data_i;
    wire[`MemBus] m0_data_o;

    // master 1 interface
    wire m1_req_i;
    wire m1_we_i;
    wire m1_ack_o;
    wire[`MemAddrBus] m1_addr_i;
    wire[`MemBus] m1_data_i;
    wire[`MemBus] m1_data_o;

    // master 2 interface
    wire[`MemAddrBus] m2_addr_i;
    wire[`MemBus] m2_data_i;
    wire[`MemBus] m2_data_o;
    wire m2_req_i;
    wire m2_we_i;

    // master 3 interface
    wire[`MemAddrBus] m3_addr_i;
    wire[`MemBus] m3_data_i;
    wire[`MemBus] m3_data_o;
    wire m3_req_i;
    wire m3_we_i;
    wire m3_ack_o;

    // slave 0 interface
    wire s0_req_o;
    wire s0_we_o;
    wire s0_ack_i;
    wire[`MemAddrBus] s0_addr_o;
    wire[`MemBus] s0_data_o;
    wire[`MemBus] s0_data_i;

    // slave 1 interface
    wire s1_req_o;
    wire s1_we_o;
    wire s1_ack_i;
    wire[`MemAddrBus] s1_addr_o;
    wire[`MemBus] s1_data_o;
    wire[`MemBus] s1_data_i;

    // slave 2 interface
    wire[`MemAddrBus] s2_addr_o;
    wire[`MemBus] s2_data_o;
    wire[`MemBus] s2_data_i;
    wire s2_we_o;

    // slave 3 interface
    wire[`MemAddrBus] s3_addr_o;
    wire[`MemBus] s3_data_o;
    wire[`MemBus] s3_data_i;
    wire s3_we_o;

    // slave 4 interface
    wire[`MemAddrBus] s4_addr_o;
    wire[`MemBus] s4_data_o;
    wire[`MemBus] s4_data_i;
    wire s4_we_o;

    // slave 5 interface
    wire[`MemAddrBus] s5_addr_o;
    wire[`MemBus] s5_data_o;
    wire[`MemBus] s5_data_i;
    wire s5_we_o;

    // slave 6 interface
    wire[`MemAddrBus] s6_addr_o;
    wire[`MemBus] s6_data_o;
    wire[`MemBus] s6_data_i;
    wire s6_we_o;

    // slave 7 interface
    wire s7_req_o;
    wire[`MemAddrBus] s7_addr_o;
    wire[`MemBus] s7_data_o;
    wire[`MemBus] s7_data_i;
    wire s7_we_o;
    wire s7_ack_i;

    // rib
    wire rib_hold_flag_o;

    // jtag
    // wire jtag_halt_req_o;
    // wire jtag_reset_req_o;
    // wire[`RegAddrBus] jtag_reg_addr_o;
    // wire[`RegBus] jtag_reg_data_o;
    // wire jtag_reg_we_o;
    // wire[`RegBus] jtag_reg_data_i;

    // tinyriscv
    // wire[`INT_BUS] int_flag;

    // timer0
    // wire timer0_int;

    // gpio
    // wire[1:0] io_in;
    // wire[31:0] gpio_ctrl;
    // wire[31:0] gpio_data;

    //assign int_flag = {7'h0, timer0_int};

    // 浣庣數骞崇偣浜甃ED
    // 浣庣數骞宠〃绀哄凡缁廻alt浣廋PU
    //assign halted_ind = ~jtag_halt_req_o;



    // tinyriscv澶勭悊鍣ㄦ牳妯″潡渚嬪寲
    tinyriscv u_tinyriscv(
        .clk(clk),
        .rst(rst),

        .rib_ex_addr_o(m0_addr_i),
        .rib_ex_data_i(m0_data_o),
        .rib_ex_data_o(m0_data_i),
        .rib_ex_req_o(m0_req_i),
        .rib_ex_we_o(m0_we_i),
        .rib_ex_ack_i(m0_ack_o),

        .rib_pc_addr_o(m1_addr_i),
        .rib_pc_data_i(m1_data_o),
        .rib_pc_req_o(m1_req_i),
        .rib_pc_ack_i(m1_ack_o),

        .jtag_reg_addr_i(`ZeroReg),
        .jtag_reg_data_i(`ZeroWord),
        .jtag_reg_we_i(`WriteDisable),
        .jtag_reg_data_o(),

        .rib_hold_flag_i(rib_hold_flag_o),
        .jtag_halt_flag_i(`HoldDisable),
        .jtag_reset_flag_i(1'b0),

        .int_i(`INT_NONE)
    );

/*
    // timer妯″潡渚嬪寲
    timer timer_0(
        .clk(clk),
        .rst(rst),
        .data_i(s2_data_o),
        .addr_i(s2_addr_o),
        .we_i(s2_we_o),
        .data_o(s2_data_i),
        .int_sig_o(timer0_int)
    );
*/

    // uart妯″潡渚嬪寲
    uart uart_0(
        .clk(clk),
        .rst(rst),
        .we_i(s3_we_o),
        .addr_i(s3_addr_o),
        .data_i(s3_data_o),
        .data_o(s3_data_i),
        .tx_pin(uart_tx_pin),
        .rx_pin(uart_rx_pin)
    );

    // io0
    // assign gpio[0] = (gpio_ctrl[1:0] == 2'b01)? gpio_data[0]: 1'bz;
    // assign io_in[0] = gpio[0];
    // // io1
    // assign gpio[1] = (gpio_ctrl[3:2] == 2'b01)? gpio_data[1]: 1'bz;
    // assign io_in[1] = gpio[1];

/*
    // gpio妯″潡渚嬪寲
    gpio gpio_0(
        .clk(clk),
        .rst(rst),
        .we_i(s4_we_o),
        .addr_i(s4_addr_o),
        .data_i(s4_data_o),
        .data_o(s4_data_i),
        .io_pin_i(io_in),
        .reg_ctrl(gpio_ctrl),
        .reg_data(gpio_data)
    );
*/

/*
    // spi妯″潡渚嬪寲
    spi spi_0(
        .clk(clk),
        .rst(rst),
        .data_i(s5_data_o),
        .addr_i(s5_addr_o),
        .we_i(s5_we_o),
        .data_o(s5_data_i),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_ss(spi_ss),
        .spi_clk(spi_clk)
    );
*/
    // rib妯″潡渚嬪寲
    rib u_rib(
        .clk(clk),
        .rst(rst),

        // master 0 interface
        .m0_addr_i(m0_addr_i),
        .m0_data_i(m0_data_i),
        .m0_data_o(m0_data_o),
        .m0_req_i(m0_req_i),
        .m0_we_i(m0_we_i),
        .m0_ack_o(m0_ack_o),

        // master 1 interface
        .m1_addr_i(m1_addr_i),
        .m1_data_i(`ZeroWord),
        .m1_data_o(m1_data_o),
        .m1_req_i(m1_req_i),
        .m1_we_i(`WriteDisable),
        .m1_ack_o(m1_ack_o),

        // master 2 interface
        .m2_addr_i(`ZeroWord),
        .m2_data_i(`ZeroWord),
        .m2_data_o(),
        .m2_req_i(`RIB_NREQ),
        .m2_we_i(`WriteDisable),

        // master 3 interface
        .m3_addr_i(m3_addr_i),
        .m3_data_i(m3_data_i),
        .m3_data_o(m3_data_o),
        .m3_req_i(m3_req_i),
        .m3_we_i(m3_we_i),
        .m3_ack_o(m3_ack_o),

        // slave 0 interface
        .s0_addr_o(s0_addr_o),
        .s0_data_o(s0_data_o),
        .s0_data_i(s0_data_i),
        .s0_we_o(s0_we_o),
        .s0_req_o(s0_req_o),
        .s0_ack_i(s0_ack_i),

        // slave 1 interface
        .s1_addr_o(s1_addr_o),
        .s1_data_o(s1_data_o),
        .s1_data_i(s1_data_i),
        .s1_we_o(s1_we_o),
        .s1_ack_i(s1_ack_i),

        // slave 2 interface
        .s2_addr_o(),
        .s2_data_o(),
        .s2_data_i(`ZeroWord),
        .s2_we_o(),

        // slave 3 interface
        .s3_addr_o(s3_addr_o),
        .s3_data_o(s3_data_o),
        .s3_data_i(s3_data_i),
        .s3_we_o(s3_we_o),

        // slave 4 interface
        .s4_addr_o(),
        .s4_data_o(),
        .s4_data_i(`ZeroWord),
        .s4_we_o(),

        // slave 5 interface
        .s5_addr_o(),
        .s5_data_o(),
        .s5_data_i(`ZeroWord),
        .s5_we_o(),

        // slave 6 interface
        .s6_addr_o(),
        .s6_data_o(),
        .s6_data_i(`ZeroWord),
        .s6_we_o(),

        // slave 7 interface
        .s7_req_o(s7_req_o),
        .s7_addr_o(s7_addr_o),     // 从设备7读、写地址
        .s7_data_o(s7_data_o),         // 从设备7写数据
        .s7_data_i(s7_data_i),         // 从设备7读取到的数据
        .s7_we_o(s7_we_o),                    // 从设备7写标志
        .s7_ack_i(s7_ack_i),

        .hold_flag_o(rib_hold_flag_o)
    );

    // Bridge妯″潡渚嬪寲
    bridge_master u_bridge_master(
        .clk(clk),
        .rst(rst),

        // rib鎺ュ彛
        .rib_req_i(s0_req_o),
        .rib_we_i(s0_we_o),
        .rib_ack_o(s0_ack_i),
        .rib_addr_i(s0_addr_o),
        .rib_data_i(s0_data_o),
        .rib_data_o(s0_data_i),

        // jtag鎺ュ彛
        .bmaster_RX_data(bmaster_RX_data),
        .bmaster_TX_data(bmaster_TX_data),
        .hold_flag_o()
        );

    // 涓插彛涓嬭浇妯″潡渚嬪寲
    uart_debug u_uart_debug(
        .clk(clk),
        .rst(rst),
        .debug_en_i(uart_debug_pin),
        .req_o(m3_req_i),
        .mem_we_o(m3_we_i),
        .mem_addr_o(m3_addr_i),
        .mem_wdata_o(m3_data_i),
        .mem_rdata_i(m3_data_o),
        .mem_write_ack_i(m3_ack_o)
    );

    iic_dk u_iic_dk ( 

    .clk(clk), 
    .rst(rst),
    .req_i({s7_req_o, 1'b1}), 
    .we_i(s7_we_o),
    .addr_i(s7_addr_o),
    .data_i(s7_data_o),
    .data_o(s7_data_i),   
    .ack_o(s7_ack_i),  
    .SCL_o(SCL_o) ,  
    .SDA_o(SDA_o) ,  
    .SDA_oe_o(SDA_oe_o), 
    .SDA_i(SDA_i)  

    // jtag妯″潡渚嬪寲
    // jtag_top #(
    //     .DMI_ADDR_BITS(6),
    //     .DMI_DATA_BITS(32),
    //     .DMI_OP_BITS(2)
    // ) u_jtag_top(
    //     .clk(clk),
    //     .jtag_rst_n(rst),
    //     .jtag_pin_TCK(jtag_TCK),
    //     .jtag_pin_TMS(jtag_TMS),
    //     .jtag_pin_TDI(jtag_TDI),
    //     .jtag_pin_TDO(jtag_TDO),
    //     .reg_we_o(jtag_reg_we_o),
    //     .reg_addr_o(jtag_reg_addr_o),
    //     .reg_wdata_o(jtag_reg_data_o),
    //     .reg_rdata_i(jtag_reg_data_i),
    //     .mem_we_o(m2_we_i),
    //     .mem_addr_o(m2_addr_i),
    //     .mem_wdata_o(m2_data_i),
    //     .mem_rdata_i(m2_data_o),
    //     .op_req_o(m2_req_i),
    //     .halt_req_o(jtag_halt_req_o),
    //     .reset_req_o(jtag_reset_req_o)
    // );

  ) ;

endmodule
