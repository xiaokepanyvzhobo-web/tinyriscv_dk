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
`include "../core/defines.v"

module bridge_slave (

    // 时钟和复位信号
    input  wire                 clk , 
    input  wire                 rst ,
    // 处理器总线桥接设备的数据信号
    input  wire  [`BridgeBus]   bslave_RX_data ,
    output wire  [`BridgeBus]   bslave_TX_data ,
    // 与RAM相交互的信号组
    output wire                 ram_we_o ,                   
    output wire  [`MemAddrBus]  ram_addr_o ,    
    output wire  [`MemBus]      ram_data_o ,
    input  wire  [`MemBus]      ram_data_i ,     
    // 与ROM相交互的信号组
    output wire                 rom_we_o ,                   
    output wire  [`MemAddrBus]  rom_addr_o ,    
    output wire  [`MemBus]      rom_data_o ,
    input  wire  [`MemBus]      rom_data_i 

) ;

    // 空闲状态
    parameter IDLE           = 4'b0000 ;
    // 地址传输过程
    parameter WE_RD_RX_ADDR0 = 4'b0001 ;
    parameter WE_RD_RX_ADDR1 = 4'b0010 ;
    parameter WE_RD_RX_ADDR2 = 4'b0011 ;
    parameter WE_RD_RX_ADDR3 = 4'b0100 ;
    // 数据写入及相应过程
    parameter WE_RX_DATA0    = 4'b0101 ;
    parameter WE_RX_DATA1    = 4'b0110 ;
    parameter WE_RX_DATA2    = 4'b0111 ;
    parameter WE_RX_DATA3    = 4'b1000 ;
    parameter WE_TX_RESP     = 4'b1001 ;
    // 数据读出过程
    parameter RD_TX_DATA0    = 4'b1010 ;
    parameter RD_TX_DATA1    = 4'b1011 ;
    parameter RD_TX_DATA2    = 4'b1100 ;
    parameter RD_TX_DATA3    = 4'b1101 ;
    // Regs 
    reg [`StatusBus_slave]        cs, ns ;
    reg [`BridgeBus]              bslave_TX_data_reg ;
    reg [`MemBus]                 data_temp ;
    reg [`MemAddrBus]             addr_temp ;
    reg [`CmdSimple]              cmd_simple_temp ;
    reg                           ram_we_reg ;
    reg                           rom_we_reg ;

    reg [`MemBus]                 rom_ram_data_out ;

    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            cs <= IDLE ;
        end
        else begin
            cs <= ns ;
        end
    end

    always @ ( * ) begin
        case ( cs ) 
            // Switch to Write or Read Addr Transmission Status according to " RX_data ( Cmd ) "
            IDLE:begin
                if ( (bslave_RX_data == `ReadCmd) || (bslave_RX_data == `WriteCmd) ) begin
                    ns = WE_RD_RX_ADDR0 ;
                end
                else begin
                    ns = IDLE ;
                end
            end
            // Addr transmission status
            WE_RD_RX_ADDR0: begin ns = WE_RD_RX_ADDR1 ; end
            WE_RD_RX_ADDR1: begin ns = WE_RD_RX_ADDR2 ; end
            WE_RD_RX_ADDR2: begin ns = WE_RD_RX_ADDR3 ; end
            // Switch to read or write status according to cmd_simple_temp
            WE_RD_RX_ADDR3:begin
                if ( cmd_simple_temp == `WriteCmd_simp ) begin
                    ns = WE_RX_DATA0 ;
                end
                else if ( cmd_simple_temp == `ReadCmd_simp ) begin
                    ns = RD_TX_DATA0 ;
                end
                else begin
                    ns = IDLE ; // need to be cautious -- liudk
                end
            end
            // Switch to writing status ( Data transmission  )
            WE_RX_DATA0: begin ns = WE_RX_DATA1 ; end
            WE_RX_DATA1: begin ns = WE_RX_DATA2 ; end
            WE_RX_DATA2: begin ns = WE_RX_DATA3 ; end
            WE_RX_DATA3: begin ns = WE_TX_RESP  ; end
            WE_TX_RESP:  begin ns = IDLE        ; end
            // Switch to reading status ( Data fetching from Ram/Rom and transmission )
            RD_TX_DATA0: begin ns = RD_TX_DATA1 ; end
            RD_TX_DATA1: begin ns = RD_TX_DATA2 ; end
            RD_TX_DATA2: begin ns = RD_TX_DATA3 ; end
            RD_TX_DATA3: begin ns = IDLE        ; end
            // default cases switch to IDLE
            default:     begin ns = IDLE        ; end
        endcase
    end

    // the logic of addr_temp regs: reset when rst validate and update addr values in the status of ADDR TRANSMISSION  
    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            addr_temp <= `ZeroWord ;
        end
        else begin
            case ( cs ) 
                WE_RD_RX_ADDR0:begin
                    addr_temp[`AddrOrDataSlice0] <= bslave_RX_data ;
                end
                WE_RD_RX_ADDR1:begin
                    addr_temp[`AddrOrDataSlice1] <= bslave_RX_data ;
                end
                WE_RD_RX_ADDR2:begin
                    addr_temp[`AddrOrDataSlice2] <= bslave_RX_data ;
                end
                WE_RD_RX_ADDR3:begin
                    addr_temp[`AddrOrDataSlice3] <= bslave_RX_data ;
                end
                default:begin
                    
                end
            endcase 
        end
    end

    //the logic of data_temp:reset when rst validate, receive RX_data when cs enters WE_RX_DATA status
    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            data_temp <= `ZeroWord ;
        end
        else begin
            case ( cs ) 
                WE_RX_DATA0:begin
                    data_temp[`AddrOrDataSlice0] <= bslave_RX_data ;
                end
                WE_RX_DATA1:begin
                    data_temp[`AddrOrDataSlice1] <= bslave_RX_data ;
                end
                WE_RX_DATA2:begin
                    data_temp[`AddrOrDataSlice2] <= bslave_RX_data ;
                end
                WE_RX_DATA3:begin
                    data_temp[`AddrOrDataSlice3] <= bslave_RX_data ;
                end
                default:begin

                end 
            endcase
        end
    end 

    // the logic of bslave_TX_data_reg : reset when rst validate update when cs enters the RD_TX Status and update when WE_TX_RESP
    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            bslave_TX_data_reg <= `ZeroTempReg ;
        end
        else begin
            case ( cs ) 
                RD_TX_DATA0:begin
                    bslave_TX_data_reg <= rom_ram_data_out[`AddrOrDataSlice0] ;
                end
                RD_TX_DATA1:begin
                    bslave_TX_data_reg <= rom_ram_data_out[`AddrOrDataSlice1] ;
                end
                RD_TX_DATA2:begin
                    bslave_TX_data_reg <= rom_ram_data_out[`AddrOrDataSlice2] ;
                end
                RD_TX_DATA3:begin
                    bslave_TX_data_reg <= rom_ram_data_out[`AddrOrDataSlice3] ;
                end
                WE_RX_DATA2:begin
                    bslave_TX_data_reg <= `WE_RespCmd ;
                end
                default:begin

                end
            endcase
        end
    end   

    // the logic of cmd_simple_temp : reset when rst validate, update when cs enters IDLE status
    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            cmd_simple_temp <= `ZeroCmdSimple ;
        end 
        else begin
            if ( cs == IDLE ) begin
                cmd_simple_temp <= bslave_RX_data[`CmdSimple] ;
            end
        end
    end

    always @ ( * ) begin
        if ( addr_temp[28] == 1'b0 ) begin
            rom_ram_data_out = rom_data_i ;
        end 
        else begin
            rom_ram_data_out = ram_data_i ;
        end
    end 

    // the logic of ram_we_reg and rom_we_reg
    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            ram_we_reg <= `WriteDisable ;
            rom_we_reg <= `WriteDisable ;
        end
        else begin
            if ( cs == WE_RX_DATA3 ) begin
                if ( addr_temp[28] == 1'b0 ) begin
                    rom_we_reg <= `WriteEnable ;
                end
                else begin 
                    ram_we_reg <= `WriteEnable ;
                end
            end
            else begin
                rom_we_reg <= `WriteDisable ;
                ram_we_reg <= `WriteDisable ;
            end
        end
    end

    assign rom_we_o   = rom_we_reg ;
    assign rom_addr_o = addr_temp  ;
    assign rom_data_o = data_temp  ; 

    assign ram_we_o   = ram_we_reg ;
    assign ram_addr_o = addr_temp  ;
    assign ram_data_o = data_temp  ; 

    assign bslave_TX_data = bslave_TX_data_reg ;

endmodule
