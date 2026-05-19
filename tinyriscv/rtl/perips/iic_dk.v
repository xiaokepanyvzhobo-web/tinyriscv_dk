 /*                                                                      
 Copyright 2026 Liudk
                                                                         
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

//TODO:
// 1. 补充SCL SDA信号的寄存器
// 2. 复制该文件中的各种宏定义
module iic_dk ( 

    input wire               clk    , 
    input wire               rst    ,
    // req_i[1]为功能使能，req_i[0]为IIC读写选择，0=写，1=读
    input wire [1:0]         req_i  , 
    input wire               we_i   ,
    input wire [`MemAddrBus] addr_i ,
    input wire [`MemBus]     data_i ,

    output wire [`MemBus]    data_o ,   // 已定义
    output reg               ack_o  ,   // 已定义
    // IIC的方向信号
    output wire              SCL_o  ,   // 已定义
    output wire              SDA_o  ,   // 已定义
    output wire              SDA_oe_o , // 已定义
    input wire               SDA_i  

  ) ;

    reg [`MemAddrBus]                       addr_reg         ;  // 0x7001_0000
    reg [`MemBus]                           data_out_reg     ;  // 0x7002_0000
    reg [`MemBus]                           data_in_reg      ;  // 0x7003_0000

    reg [1:0]                               iic_req_reg      ;  // 寄存IIC事务的请求有效信号

    reg [4:0]                               iic_cs, iic_ns   ;  // IIC事务的状态机状态
    reg [$clog2(`CLK_DIVIDER)-1:0]          iic_counter      ;  // IIC事务的状态机计数器，已定义 
    reg                                     iic_tick         ;  // IIC相位的切换标志信号，已定义
    reg                                     iic_busy         ;  // IIC事务进行中的标志信号，已定义
    reg [1:0]                               scl_phrase       ;  // SCL时钟信号的相位标识，已定义

    //reg                                     need_pointer_reg ;  // 标志当前的读过程需要pointer指示，未定义
    reg                                     scl_reg          ;  // SCL信号的寄存器，未定义完全，不确定是否还需要补充一些状态的赋值
    reg                                     sda_reg          ;  // SDA信号的寄存器，未定义完全，还缺少一些状态的赋值
    reg [3:0]                               sda_counter      ;  // SDA信号的计数器，未定义完全，开始计数的实际还需要补充

    reg rx_ack                                               ;  // 从设备回应的ACK信号，未完全定义，其采集的时机还需要补充

    wire sda_in ;
    assign sda_in = SDA_i ;

    wire scl_cycle_end ;
    wire scl_8cycles_end ;
    wire start_end ;
    wire addr_byte_end ;
    wire addr_byte_ack_end ;
    wire pointer_byte_end ;
    wire pointer_byte_ack_end ;
    wire we_hi_byte_end ;
    wire we_hi_byte_ack_end ;
    wire we_lo_byte_end ;
    wire we_lo_byte_ack_end ;
    wire rd_hi_byte_end ;
    wire rd_hi_byte_ack_end ;
    wire rd_lo_byte_end ;
    wire rd_lo_byte_ack_end ;
    wire stop_end ;

    parameter IDLE              = 5'd0 ;
    parameter START             = 5'd1 ;
    parameter ADDR_BYTE         = 5'd2 ;
    parameter ADDR_BYTE_ACK     = 5'd3 ;
    parameter POINTER_BYTE      = 5'd4 ;
    parameter POINTER_BYTE_ACK  = 5'd5 ;
    parameter WE_HI_BYTE        = 5'd6 ;
    parameter WE_HI_BYTE_ACK    = 5'd7 ;
    parameter WE_LO_BYTE        = 5'd8 ;
    parameter WE_LO_BYTE_ACK    = 5'd9 ;
    parameter RD_HI_BYTE        = 5'd10 ;
    parameter RD_HI_BYTE_ACK    = 5'd11 ;
    parameter RD_LO_BYTE        = 5'd12 ;
    parameter RD_LO_BYTE_ACK    = 5'd13 ;
    parameter STOP              = 5'd14 ;
    

    /////////////////////////////////////////////////////////////////////// 寄存器的行为定义 ///////////////////////////////////////////////////////////////////
    // iic_busy信号的更新逻辑
    
    reg iic_start ;

    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            iic_start <= 1'b0 ;
        end
        else begin
            if ( ( req_i == `IICWrite ) || ( req_i == `IICRead ) ) begin
                iic_start <= 1'b1 ;
            end
            else begin
                iic_start <= 1'b0 ;
            end
        end
    end

    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            iic_busy <= `BusyDisable ;
        end
        else begin
            if ( iic_start ) begin
                iic_busy <= `BusyEnable ;
            end
            else if ( stop_end ) begin
                iic_busy <= `BusyDisable ;
            end
            else begin
                iic_busy <= iic_busy ;
            end
        end
    end

    // ack_o信号的更新逻辑
    always @( posedge clk ) begin
        if ( rst ==`RstEnable ) begin
            ack_o <= `AckDisable ;
        end
        else if ( stop_end ) begin
            ack_o <= `AckEnable ;
        end
        else begin
            ack_o <= `AckDisable ;
        end
    end

    // IIC 相关寄存器的写控制
    always @( posedge clk) begin
        if ( rst == `RstEnable ) begin
            addr_reg <= `ZeroWord;
            data_in_reg <= `ZeroWord;
        end else begin
            if ( we_i == `WriteEnable ) begin
                case ( addr_i[17:16] )
                    2'b01: addr_reg <= data_i ;
                    2'b11: data_in_reg <= data_i ;
                    default: begin
                        addr_reg <= addr_reg;
                        data_in_reg <= data_in_reg;
                    end
                endcase
            end else begin
                addr_reg <= addr_reg;
                data_in_reg <= data_in_reg;
            end
        end
    end

    


    // iic_counter的更新逻辑
    // iic_tick的更新逻辑
    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            iic_counter <= 0 ;
            iic_tick <= 0 ;
        end else begin
            if ( iic_busy ) begin
                if ( iic_counter == `CLK_DIVIDER - 1 ) begin
                    iic_counter <= 0 ;
                    iic_tick <= 1'b0 ;
                end
                else if ( iic_counter == `CLK_DIVIDER - 2 )  begin
                    iic_counter <= iic_counter + 1 ;
                    iic_tick <= 1'b1 ;
                end
                else begin
                    iic_counter <= iic_counter + 1 ;
                    iic_tick <= 1'b0 ;
                end
            end
            else begin
                iic_counter <= 0 ;
                iic_tick <= 0 ;
            end
        end
    end

    // iic_phrase的更新逻辑
    always @( posedge clk ) begin
        if ( rst ==`RstEnable ) begin
            scl_phrase <= 2'b00 ;
        end
        else if ( iic_busy ) begin
            if ( iic_tick ) begin
                scl_phrase <= scl_phrase + 1'b1 ;
            end
            else begin
                scl_phrase <= scl_phrase ;
            end
        end
        else begin
            scl_phrase <= 2'b00 ;        
        end
    end

    //sda_counter的更新逻辑
    always @( posedge clk ) begin
        if ( rst ==`RstEnable ) begin
            sda_counter <= 0 ;
        end
        else if ( iic_busy ) begin
            if ( start_end || addr_byte_ack_end || pointer_byte_ack_end || we_hi_byte_ack_end || rd_hi_byte_ack_end || we_lo_byte_ack_end || rd_lo_byte_ack_end ) begin   // 逻辑待补充
                sda_counter <= 0 ;
            end
            else begin
                if ( iic_tick && scl_phrase == 2'b11 ) begin
                    sda_counter <= sda_counter + 1 ;
                end 
                else begin
                    sda_counter <= sda_counter ;
                end
            end
        end
        else begin
            sda_counter <= 0 ;
        end
        
    end

    // rx_ack信号的更新逻辑
    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            rx_ack <= 1'b1 ;
        end
        else begin
            if ( iic_busy ) begin
                if ( iic_cs == ADDR_BYTE_ACK || iic_cs == POINTER_BYTE_ACK || iic_cs == WE_HI_BYTE_ACK || iic_cs == WE_LO_BYTE_ACK ) begin        // 逻辑待补充 
                    if ( iic_tick && scl_phrase == 2'b01 ) begin
                        rx_ack <= sda_in ;
                    end
                    else begin
                        rx_ack <= rx_ack ;
                    end
                end 
                else begin
                    rx_ack <= 1'b1 ;
                end
            end 
            else begin
                rx_ack <= 1'b1 ;
            end
            
        end
    end

    // data_out_reg信号的更新逻辑
    always @( posedge clk ) begin
        if ( rst ==`RstEnable ) begin
            data_out_reg <= `ZeroWord ;
        end
        else begin
            if ( iic_cs == RD_HI_BYTE ) begin
                if ( iic_tick && scl_phrase == 2'b01 ) begin
                    case ( sda_counter )
                        4'd0: data_out_reg[15] <= sda_in ;
                        4'd1: data_out_reg[14] <= sda_in ;
                        4'd2: data_out_reg[13] <= sda_in ;
                        4'd3: data_out_reg[12] <= sda_in ;
                        4'd4: data_out_reg[11] <= sda_in ;
                        4'd5: data_out_reg[10] <= sda_in ;
                        4'd6: data_out_reg[9]  <= sda_in ;
                        4'd7: data_out_reg[8]  <= sda_in ;
                        default:begin
                            data_out_reg <= data_out_reg ;
                        end
                    endcase
                end
                else begin
                    data_out_reg <= data_out_reg ;
                end
            end
            else if ( iic_cs == RD_LO_BYTE ) begin
                if ( iic_tick && scl_phrase == 2'b01 ) begin
                    case ( sda_counter )
                        4'd0: data_out_reg[7] <= sda_in ;
                        4'd1: data_out_reg[6] <= sda_in ;
                        4'd2: data_out_reg[5] <= sda_in ;
                        4'd3: data_out_reg[4] <= sda_in ;
                        4'd4: data_out_reg[3] <= sda_in ;
                        4'd5: data_out_reg[2] <= sda_in ;
                        4'd6: data_out_reg[1] <= sda_in ;
                        4'd7: data_out_reg[0] <= sda_in ;
                        default:begin
                            data_out_reg <= data_out_reg ;
                        end
                    endcase
                end
                else begin
                    data_out_reg <= data_out_reg ;
                end
            end
            else begin
                data_out_reg <= data_out_reg ;
            end
        end
    end
    /////////////////////////////////////////////////////////////////////// 寄存器的行为定义 ///////////////////////////////////////////////////////////////////



    /////////////////////////////////////////////////////////////////////// 关键控制信号定义 ///////////////////////////////////////////////////////////////////
    assign scl_cycle_end        =   ( iic_tick ) && ( scl_phrase == 2'b11 ) ;
    assign scl_8cycles_end      =   scl_cycle_end && ( sda_counter == 4'd7 ) ;
    assign start_end            =   ( iic_cs == START ) && scl_cycle_end ;
    assign addr_byte_end        =   ( iic_cs == ADDR_BYTE ) && scl_8cycles_end ;
    assign addr_byte_ack_end    =   ( iic_cs == ADDR_BYTE_ACK ) && scl_cycle_end ;
    assign pointer_byte_end     =   ( iic_cs == POINTER_BYTE ) && scl_8cycles_end ;
    assign pointer_byte_ack_end =   ( iic_cs == POINTER_BYTE_ACK ) && scl_cycle_end ;
    assign we_hi_byte_end       =   ( iic_cs == WE_HI_BYTE ) && scl_8cycles_end ;
    assign we_hi_byte_ack_end   =   ( iic_cs == WE_HI_BYTE_ACK ) && scl_cycle_end ;
    assign we_lo_byte_end       =   ( iic_cs == WE_LO_BYTE ) && scl_8cycles_end ;
    assign we_lo_byte_ack_end   =   ( iic_cs == WE_LO_BYTE_ACK ) && scl_cycle_end ;
    assign rd_hi_byte_end       =   ( iic_cs == RD_HI_BYTE ) && scl_8cycles_end ;
    assign rd_hi_byte_ack_end   =   ( iic_cs == RD_HI_BYTE_ACK ) && scl_cycle_end ;
    assign rd_lo_byte_end       =   ( iic_cs == RD_LO_BYTE ) && scl_8cycles_end ;
    assign rd_lo_byte_ack_end   =   ( iic_cs == RD_LO_BYTE_ACK ) && scl_cycle_end ;
    assign stop_end             =   ( iic_cs == STOP ) && scl_cycle_end ;
    /////////////////////////////////////////////////////////////////////// 关键控制信号定义 ///////////////////////////////////////////////////////////////////



    /////////////////////////////////////////////////////////////////////// 状态机定义 ////////////////////////////////////////////////////////////////////////
    // 状态机第一段：状态在时钟上升沿进行转换
    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            iic_cs <= IDLE ;
        end
        else begin
            iic_cs <= iic_ns ;
        end
    end

    ///////////////////////////////////////////////////////////////////// 状态机第二段：状态转换间的条件描述 ////////////////////////////////////////////////////
    always @( * ) begin
        iic_ns = IDLE ;
        case ( iic_cs )
            // 默认初始状态
            IDLE : begin
                if ( iic_busy ) begin
                    iic_ns = START ;
                end
                else begin
                    iic_ns = IDLE ;
                end
            end
            // IIC事务开始状态
            START: begin
                if ( start_end ) begin
                    iic_ns = ADDR_BYTE ;
                end
                else begin
                    iic_ns = START ;
                end
            end
            // IIC事务发送首地址字节的状态
            ADDR_BYTE:begin
                if ( addr_byte_end ) begin
                    iic_ns = ADDR_BYTE_ACK ;
                end
                else begin
                    iic_ns = ADDR_BYTE ;
                end
            end
            // IIC事务发送首地址字节回应状态
            ADDR_BYTE_ACK:begin
                if ( addr_byte_ack_end ) begin
                    if ( ! rx_ack ) begin
                        if ( ! addr_reg[0] ) begin
                            iic_ns = POINTER_BYTE ;
                        end
                        else begin
                            iic_ns = RD_HI_BYTE ;
                        end
                    end
                    else begin
                        iic_ns = STOP ;
                    end
                end
                else begin
                    iic_ns = ADDR_BYTE_ACK ;
                end
            end
            // IIC事务发送pointer字节的状态
            POINTER_BYTE:begin
                if (  pointer_byte_end ) begin
                    iic_ns = POINTER_BYTE_ACK ;
                end
                else begin
                    iic_ns = POINTER_BYTE ;
                end
            end
            // 指针寄存器字节相应状态
            POINTER_BYTE_ACK:begin
                if ( pointer_byte_ack_end ) begin
                    if ( ! rx_ack ) begin
                        if ( addr_reg[9:8] == 2'b01 ) begin
                            iic_ns = WE_LO_BYTE ;
                        end
                        else begin
                            iic_ns = WE_HI_BYTE ;
                        end
                    end
                    else begin
                        iic_ns = STOP ;
                    end
                end
                else begin
                    iic_ns = POINTER_BYTE_ACK ;
                end
            end
            // 高字节数据写入状态
            WE_HI_BYTE:begin
                if ( we_hi_byte_end ) begin
                    iic_ns = WE_HI_BYTE_ACK ;
                end
                else begin
                    iic_ns = WE_HI_BYTE ;
                end
            end
            // 高字节数据写入回应状态
            WE_HI_BYTE_ACK:begin
                if ( we_hi_byte_ack_end ) begin
                    if ( ! rx_ack ) begin
                        iic_ns = WE_LO_BYTE ;
                    end
                    else begin
                        iic_ns = STOP ;
                    end
                end
                else begin
                    iic_ns = WE_HI_BYTE_ACK ;
                end
            end
            // 低字节数据写入状态
            WE_LO_BYTE:begin
                if ( we_lo_byte_end ) begin
                    iic_ns = WE_LO_BYTE_ACK ;
                end
                else begin
                    iic_ns = WE_LO_BYTE ;
                end
            end
            // 低字节数据写入回应状态
            WE_LO_BYTE_ACK:begin
                if ( we_lo_byte_ack_end ) begin
                    iic_ns = STOP ;
                end
                else begin
                    iic_ns = WE_LO_BYTE_ACK ;
                end
            end
            // 高字节数据读取状态
            RD_HI_BYTE:begin
                if ( rd_hi_byte_end ) begin
                    iic_ns = RD_HI_BYTE_ACK ;
                end
                else begin
                    iic_ns = RD_HI_BYTE ;
                end
            end
            // 高字节数据读取回应状态
            RD_HI_BYTE_ACK:begin
                if ( rd_hi_byte_ack_end ) begin
                    iic_ns = RD_LO_BYTE ;
                end
                else begin
                    iic_ns = RD_HI_BYTE_ACK ;
                end
            end
            // 低字节数据读取状态
            RD_LO_BYTE:begin
                if ( rd_lo_byte_end ) begin
                    iic_ns = RD_LO_BYTE_ACK ;
                end
                else begin
                    iic_ns = RD_LO_BYTE ;
                end
            end
            // 低字节数据读取回应状态
            RD_LO_BYTE_ACK:begin
                if ( rd_lo_byte_ack_end ) begin
                    iic_ns = STOP ;
                end
                else begin
                    iic_ns = RD_LO_BYTE_ACK ;
                end
            end
            // IIC事务结束状态
            STOP:begin
                if ( stop_end ) begin
                    iic_ns = IDLE ;
                end
                else begin
                    iic_ns = STOP ;
                end
            end
            // 默认分支
            default: begin 
                iic_ns = IDLE ; 
            end
        endcase
    end
    ///////////////////////////////////////////////////////////////////// 状态机第二段：状态转换间的条件描述 ////////////////////////////////////////////////////


    ///////////////////////////////////////////////////////////////////// 状态机第三段：输出寄存器的行为描述 ////////////////////////////////////////////////////
    // 状态机第三段：
    // scl_reg的赋值逻辑
    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            scl_reg <= 1'b0 ;
        end
        else begin
            if ( iic_busy ) begin
                if ( iic_tick ) begin
                    case ( scl_phrase ) 
                        2'b00: scl_reg <= 1'b1 ;
                        2'b01: scl_reg <= 1'b1 ;
                        2'b10: scl_reg <= 1'b0 ;
                        2'b11: scl_reg <= 1'b0 ;
                    endcase
                end
                else begin
                    scl_reg <= scl_reg ;
                end
            end 
            else begin
                scl_reg <= 1'b0 ;
            end
        end
    end

    ///////////////////////////////////////////////////////////////////// 状态机第三段：输出寄存器的行为描述 ////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////// 状态机定义 ////////////////////////////////////////////////////////////////////////

    // sda_reg的赋值逻辑
    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            sda_reg <= 1'b1 ;
        end
        else begin
            if ( iic_busy ) begin
                case ( iic_cs ) 
                    // IDLE状态下为低电平
                    IDLE: sda_reg <= 1'b1 ;
                    // START状态
                    START:begin
                        case ( scl_phrase )
                            2'b00: sda_reg <= 1'b1 ;
                            2'b01: sda_reg <= 1'b1 ;
                            2'b10: sda_reg <= 1'b0 ;
                            2'b11: sda_reg <= 1'b0 ;
                            default: begin
                                sda_reg <= 1'b1 ;
                            end
                        endcase
                    end
                    // 发送首地址字节的状态
                    ADDR_BYTE:begin
                        case ( sda_counter )
                            4'd0: sda_reg <= addr_reg[7] ;
                            4'd1: sda_reg <= addr_reg[6] ;
                            4'd2: sda_reg <= addr_reg[5] ;
                            4'd3: sda_reg <= addr_reg[4] ;
                            4'd4: sda_reg <= addr_reg[3] ;
                            4'd5: sda_reg <= addr_reg[2] ;
                            4'd6: sda_reg <= addr_reg[1] ;
                            4'd7: sda_reg <= addr_reg[0] ;
                            default: begin
                                sda_reg <= 1'b1 ;
                            end
                        endcase
                    end
                    // 发送首地址字节回应状态
                    ADDR_BYTE_ACK:begin
                        sda_reg <= sda_reg ;
                    end
                    POINTER_BYTE:begin
                        case ( sda_counter )
                            4'd0: sda_reg <= 1'b0 ;
                            4'd1: sda_reg <= 1'b0 ;
                            4'd2: sda_reg <= 1'b0 ;
                            4'd3: sda_reg <= 1'b0 ;
                            4'd4: sda_reg <= 1'b0 ;
                            4'd5: sda_reg <= 1'b0 ;
                            4'd6: sda_reg <= addr_reg[9] ;
                            4'd7: sda_reg <= addr_reg[8] ;
                            default: begin
                                sda_reg <= 1'b1 ;
                            end
                        endcase                 
                    end
                    POINTER_BYTE_ACK:begin
                        sda_reg <= sda_reg ;
                    end
                    WE_HI_BYTE:begin
                        case ( sda_counter )
                            4'd0: sda_reg <= data_in_reg[15] ;
                            4'd1: sda_reg <= data_in_reg[14] ;
                            4'd2: sda_reg <= data_in_reg[13] ;
                            4'd3: sda_reg <= data_in_reg[12] ;
                            4'd4: sda_reg <= data_in_reg[11] ;
                            4'd5: sda_reg <= data_in_reg[10] ;
                            4'd6: sda_reg <= data_in_reg[9] ;
                            4'd7: sda_reg <= data_in_reg[8] ;
                            default: begin
                                sda_reg <= 1'b1 ;
                            end
                        endcase 
                    end
                    // 高字节数据写入回应状态
                    WE_HI_BYTE_ACK:begin
                        sda_reg <= sda_reg ;
                    end
                    // 低字节数据写入状态
                    WE_LO_BYTE:begin
                        case ( sda_counter )
                            4'd0: sda_reg <= data_in_reg[7] ;
                            4'd1: sda_reg <= data_in_reg[6] ;
                            4'd2: sda_reg <= data_in_reg[5] ;
                            4'd3: sda_reg <= data_in_reg[4] ;
                            4'd4: sda_reg <= data_in_reg[3] ;
                            4'd5: sda_reg <= data_in_reg[2] ;
                            4'd6: sda_reg <= data_in_reg[1] ;
                            4'd7: sda_reg <= data_in_reg[0] ;
                            default: begin
                                sda_reg <= 1'b1 ;
                            end
                        endcase 
                    end
                    // 低字节数据写入回应状态
                    WE_LO_BYTE_ACK:begin
                        sda_reg <= sda_reg ;
                    end
                    // 高字节数据读取状态
                    RD_HI_BYTE:begin
                        sda_reg <= sda_reg ;
                    end
                    // 高字节数据读取回应状态
                    RD_HI_BYTE_ACK:begin
                        sda_reg <=  1'b0 ;
                    end
                    // 低字节数据读取状态
                    RD_LO_BYTE:begin
                        sda_reg <= sda_reg ;
                    end
                    // 低字节数据读取回应状态
                    RD_LO_BYTE_ACK:begin
                        sda_reg <=  1'b0 ;
                    end
                    // IIC事务结束状态
                    STOP:begin
                        case ( scl_phrase )
                            2'b00: sda_reg <= 1'b0 ;
                            2'b01: sda_reg <= 1'b0 ;
                            2'b10: sda_reg <= 1'b1 ;
                            2'b11: sda_reg <= 1'b1 ;
                            default: begin
                                sda_reg <= 1'b1 ;
                            end
                        endcase
                    end
                    // 默认分支
                    default : begin
                        sda_reg <= 1'b1 ;
                    end
                endcase
            end
            else begin
                sda_reg <= 1'b1 ;
            end
        end
    end
    

    // data_o的赋值逻辑
    assign data_o = data_out_reg ;
    assign SCL_o = scl_reg ;
    assign SDA_o = sda_reg ;
    assign SDA_oe_o =  ( iic_cs != ADDR_BYTE_ACK ) && ( iic_cs != POINTER_BYTE_ACK ) && ( iic_cs != WE_HI_BYTE_ACK ) && ( iic_cs != WE_LO_BYTE_ACK )
                       && ( iic_cs != RD_HI_BYTE ) && ( iic_cs != RD_LO_BYTE ) ? 1'b1 : 1'b0 ;

endmodule
