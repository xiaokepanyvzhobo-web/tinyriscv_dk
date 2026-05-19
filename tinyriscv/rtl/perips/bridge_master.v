 /*                                                                      
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
`include "defines.v"

 module bridge_master(

    // 时钟和复位接口
    input  wire                  clk ,
	input  wire                  rst ,

    // RIB输入接口
    input  wire                  rib_req_i ,     // RIB输入请求标志
    input  wire                  rib_we_i ,      // RIB输入写标志
    input  wire[`MemAddrBus]     rib_addr_i ,    // RIB输入地址
    input  wire[`MemBus]         rib_data_i ,    // RIB输入数据
    output wire[`MemBus]         rib_data_o ,    // RIB输出数据

    // Master接口
    input  wire[`BridgeBus]      bmaster_RX_data ,
    output wire[`BridgeBus]      bmaster_TX_data ,

    // 流水线停止标志信号
    output wire                   rib_ack_o,
    output reg                    hold_flag_o

    );
    // 空闲状态
    parameter IDLE           = 5'b00000 ;
    // 读写命令传输
    parameter RD_TX_CMD      = 5'b00001 ;
    parameter WE_TX_CMD      = 5'b00010 ;
    // 读写地址传输
    parameter WE_RD_TX_ADDR0 = 5'b00011 ;
    parameter WE_RD_TX_ADDR1 = 5'b00100 ;
    parameter WE_RD_TX_ADDR2 = 5'b00101 ;
    parameter WE_RD_TX_ADDR3 = 5'b00110 ;
    // 读过程 (数据等待及传输过程)
    parameter RD_TX_WAIT0    = 5'b00111 ;
    parameter RD_TX_WAIT1    = 5'b01000 ;
    parameter RD_RX_DATA0    = 5'b01001 ;
    parameter RD_RX_DATA1    = 5'b01010 ;
    parameter RD_RX_DATA2    = 5'b01011 ;
    parameter RD_RX_DATA3    = 5'b01100 ;
    // 写过程（数据接收以及写回响应）
    parameter WE_TX_DATA0    = 5'b01101 ;
    parameter WE_TX_DATA1    = 5'b01110 ;
    parameter WE_TX_DATA2    = 5'b01111 ;
    parameter WE_TX_DATA3    = 5'b10000 ;
    parameter WE_RX_RESP     = 5'b10001 ;
    parameter WE_RESP_WAIT   = 5'b10010 ;
    parameter RD_RESP_WAIT   = 5'b10011 ;

    reg [`StatusBus]        cs, ns ;
    reg [`BridgeBus]        bmaster_TX_data_reg ;
    reg [`MemBus]           data_temp;
    reg [`MemAddrBus]       addr_temp;
    reg                     we_temp;

    reg rib_ack_o_reg ;

    always @ ( posedge clk ) begin
        if( rst == `RstEnable )
            cs <= IDLE;
        else
            cs <= ns;
    end

    always @ ( * ) begin
        case(cs)

            // 传输读写过程的命令
            IDLE: begin
                if ( rib_req_i == `RIB_REQ ) begin
                    if ( rib_we_i == `WriteEnable ) begin
                        ns = WE_TX_CMD; // 写命令
                    end
                    else begin
                        ns = RD_TX_CMD; // 读命令
                    end
                end
                else begin
                    ns = IDLE;
                end
            end
            // 传输写过程的地址
            WE_TX_CMD:begin
                ns = WE_RD_TX_ADDR0;
            end
            // 传输读过程的地址
            RD_TX_CMD:begin
                ns = WE_RD_TX_ADDR0 ;
            end
            // 传输读写过程的地址
            WE_RD_TX_ADDR0:begin
                ns = WE_RD_TX_ADDR1;
            end
            WE_RD_TX_ADDR1:begin
                ns = WE_RD_TX_ADDR2;
            end
            WE_RD_TX_ADDR2:begin
                ns = WE_RD_TX_ADDR3;
            end
            // 根据we_temp的值选择后续执行读过程或者写过程
            WE_RD_TX_ADDR3:begin
                if ( we_temp == `WriteEnable ) begin
                    ns = WE_TX_DATA0 ;
                end
                else begin
                    ns = RD_TX_WAIT0 ;
                end
            end
            // 写过程：传输数据（RIB -> RAM/ROM）
            WE_TX_DATA0:begin
                ns = WE_TX_DATA1;
            end
            WE_TX_DATA1:begin
                ns = WE_TX_DATA2;
            end
            WE_TX_DATA2:begin
                ns = WE_TX_DATA3;
            end
            WE_TX_DATA3:begin
                ns = WE_RX_RESP;
            end
            // 写回响应
            WE_RX_RESP:begin
                if ( bmaster_RX_data == `WE_RespCmd ) begin
                    ns = WE_RESP_WAIT ;
                end
                else begin
                    ns = WE_RX_RESP ;
                end
            end
            WE_RESP_WAIT:begin
                ns = IDLE ;
            end

            // 读过程：等待数据读出和数据传输
            
            // 等待数据读出（实际上是等待slave接收到最后一段地址）
            RD_TX_WAIT0:begin
                ns = RD_TX_WAIT1 ;
            end
            // 等待数据读出（实际上是等待RAM/ROM异步读出的数据写入至输出端口的寄存器）
            RD_TX_WAIT1:begin
                ns = RD_RX_DATA0;
            end
            // 实际的数据传输
            RD_RX_DATA0:begin
                ns = RD_RX_DATA1;
            end
            RD_RX_DATA1:begin
                ns = RD_RX_DATA2;
            end
            RD_RX_DATA2:begin
                ns = RD_RX_DATA3;
            end
            RD_RX_DATA3:begin
                ns = RD_RESP_WAIT;
            end
            RD_RESP_WAIT:begin
                ns = IDLE;
            end
            // 默认结果
            default: begin
                ns = IDLE;
            end

        endcase
    end

    always @ ( posedge clk ) begin
        if (rst == `RstEnable) begin
            bmaster_TX_data_reg <= `ZeroTempReg;
        end
        else begin
            case ( cs )
                IDLE:begin
                    bmaster_TX_data_reg <= `ZeroTempReg ;
                end

                WE_TX_CMD:begin
                    bmaster_TX_data_reg <= `WriteCmd ;
                end
                RD_TX_CMD:begin
                    bmaster_TX_data_reg <= `ReadCmd ;
                end

                WE_RD_TX_ADDR0:begin
                    bmaster_TX_data_reg <= addr_temp[`AddrOrDataSlice0] ; 
                end
                WE_RD_TX_ADDR1:begin
                    bmaster_TX_data_reg <= addr_temp[`AddrOrDataSlice1] ; 
                end
                WE_RD_TX_ADDR2:begin
                    bmaster_TX_data_reg <= addr_temp[`AddrOrDataSlice2] ; 
                end
                WE_RD_TX_ADDR3:begin
                    bmaster_TX_data_reg <= addr_temp[`AddrOrDataSlice3] ; 
                end

                WE_TX_DATA0:begin
                    bmaster_TX_data_reg <= data_temp[`AddrOrDataSlice0] ; 
                end
                WE_TX_DATA1:begin
                    bmaster_TX_data_reg <= data_temp[`AddrOrDataSlice1] ; 
                end
                WE_TX_DATA2:begin
                    bmaster_TX_data_reg <= data_temp[`AddrOrDataSlice2] ; 
                end
                WE_TX_DATA3:begin
                    bmaster_TX_data_reg <= data_temp[`AddrOrDataSlice3] ; 
                end
                WE_RX_RESP:begin
                    bmaster_TX_data_reg <= `ZeroTempReg ;
                end

                default:begin
                    bmaster_TX_data_reg <= bmaster_TX_data_reg ;
                end

            endcase 
        end
    end

    always @ ( posedge clk ) begin
        if (rst == `RstEnable) begin
            addr_temp <= `ZeroWord ;
            we_temp <= 1'b0 ;
        end
        else if ( rib_req_i && (cs == IDLE) ) begin
            addr_temp <= rib_addr_i ;
            we_temp <= rib_we_i ;
        end
    end

    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            data_temp <= `ZeroWord ;
        end
        else begin
            if ( rib_we_i && rib_req_i && (cs == IDLE) ) begin
                data_temp <= rib_data_i ;
            end
            else begin
                case (cs) 
                    RD_RX_DATA0:begin
                        data_temp[`AddrOrDataSlice0] <= bmaster_RX_data ;
                    end
                    RD_RX_DATA1:begin
                        data_temp[`AddrOrDataSlice1] <= bmaster_RX_data ;
                    end
                    RD_RX_DATA2:begin
                        data_temp[`AddrOrDataSlice2] <= bmaster_RX_data ;
                    end
                    RD_RX_DATA3:begin
                        data_temp[`AddrOrDataSlice3] <= bmaster_RX_data ;
                    end
                    default:begin
                        data_temp <= data_temp ;
                    end
                endcase
            end
        end
    end

    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            rib_ack_o_reg <= `AckDisable;
        end
        else if ( (cs == RD_RX_DATA3) || (cs == WE_RX_RESP) && (bmaster_RX_data == `WE_RespCmd) ) begin
            rib_ack_o_reg <= `AckEnable;
        end
        else begin
            rib_ack_o_reg <= `AckDisable;
        end
    end

    assign rib_data_o = data_temp ;
    assign bmaster_TX_data = bmaster_TX_data_reg ;
    assign rib_ack_o = rib_ack_o_reg;

    always @(posedge clk) begin
        if (rst == `RstEnable)
            hold_flag_o <= `HoldDisable;
        else
            hold_flag_o <= `HoldDisable;   // 暂时永远不暂停
    end
                    
 endmodule
