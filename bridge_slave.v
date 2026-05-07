 =-/*                                                                      
 Copyright 2026 Dickens Liu, [EMAIL_ADDRESS]
                                                                         
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

module bridge_slave (

    // 时钟和复位信号
    input  wire               clk , 
    input  wire               rst ,
    // 处理器总线桥接设备的数据信号
    input  wire [`BridgeBus]  bslave_RX_data ,
    output reg  [`BridgeBus]  bslave_TX_data ,
    // 与RAM相交互的信号组
    output reg                ram_we_o ,                   
    output reg  [`MemAddrBus] ram_addr_o ,    
    output reg  [`MemBus]     ram_data_o ,
    input  wire [`MemBus]     ram_data_i ,     
    // 与ROM相交互的信号组
    output reg                rom_we_o ,                   
    output reg  [`MemAddrBus] rom_addr_o ,    
    output reg  [`MemBus]     rom_data_o ,
    input  wire [`MemBus]     rom_data_i ,    

) ;

    // 空闲状态
    parameter IDLE        = 5'b00000 ;
    // 总线读出状态
    parameter RD_RX_CMD   = 5'b00001 ;
    parameter RD_RX_ADDR0 = 5'b00010 ;
    parameter RD_RX_ADDR1 = 5'b00011 ;
    parameter RD_RX_ADDR2 = 5'b00100 ;
    parameter RD_RX_ADDR3 = 5'b00101 ;
    parameter RD_RX_WAIT  = 5'b00110 ;
    parameter RD_TX_DATA0 = 5'b00111 ;
    parameter RD_TX_DATA1 = 5'b01000 ;
    parameter RD_TX_DATA2 = 5'b01001 ;
    parameter RD_TX_DATA3 = 5'b01010 ;
    // 总线写入状态
    parameter WE_RX_CMD   = 5'b01011 ;
    parameter WE_RX_ADDR0 = 5'b01100 ;
    parameter WE_RX_ADDR1 = 5'b01101 ;
    parameter WE_RX_ADDR2 = 5'b01110 ;
    parameter WE_RX_ADDR3 = 5'b01111 ;
    parameter WE_RX_DATA0 = 5'b10000 ;
    parameter WE_RX_DATA1 = 5'b10001 ;
    parameter WE_RX_DATA2 = 5'b10010 ;
    parameter WE_RX_DATA3 = 5'b10011 ;
    parameter WE_TX_RESP  = 5'b10100 ;

    reg [`StatusBus]        cs, ns ;
    reg [`BridgeBus]        master_dataout_reg ;
    reg [`MemBus]           data_temp;
    reg [`MemAddrBus]       addr_temp;

    always @ (posedge clk) begin
        if ( rst == `RstEnable ) begin
            cs <= IDLE ;
        end
        else begin
            cs <= ns ;
        end
    end

    always @ (*) begin
        case (cs) 

            IDLE:begin
                if ( bslave_RX_data == `ReadCmd ) begin
                    ns = RD_RX_ADDR0 ;
                end
                else if ( bslave_RX_data == `WriteCmd ) begin
                    ns = WE_RX_ADDR0 ;
                end
                else begin
                    ns = IDLE ;
                end
            end

            RD_RX_ADDR0: begin ns = RD_RX_ADDR1 ; end
            RD_RX_ADDR1: begin ns = RD_RX_ADDR2 ; end
            RD_RX_ADDR2: begin ns = RD_RX_ADDR3 ; end
            RD_RX_ADDR3: begin ns = RD_RX_WAIT  ; end
            RD_RX_WAIT:  begin ns = RD_TX_DATA0 ; end
            RD_TX_DATA0: begin ns = RD_TX_DATA1 ; end
            RD_TX_DATA1: begin ns = RD_TX_DATA2 ; end
            RD_TX_DATA2: begin ns = RD_TX_DATA3 ; end
            RD_TX_DATA3: begin ns = IDLE        ; end

            WE_RX_ADDR0: begin ns = WE_RX_ADDR1 ; end
            WE_RX_ADDR1: begin ns = WE_RX_ADDR2 ; end
            WE_RX_ADDR2: begin ns = WE_RX_ADDR3 ; end
            WE_RX_ADDR3: begin ns = WE_RX_DATA0 ; end
            WE_RX_DATA0: begin ns = WE_RX_DATA1 ; end
            WE_RX_DATA1: begin ns = WE_RX_DATA2 ; end
            WE_RX_DATA2: begin ns = WE_RX_DATA3 ; end
            WE_RX_DATA3: begin ns = WE_TX_RESP  ; end
            WE_TX_RESP:  begin ns = IDLE        ; end

            default:     begin ns = IDLE        ; end

        endcase
    end

    // cs状态下的寄存器动作
    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            addr_temp <= `ZeroWord ;
        end
    end



endmodule