 /*                                                                      
 Copyright 2019 Blue Liang, liangkangnan@163.com
                                                                         
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

// 将指令向译码模块传递
module if_id(

    input wire clk,
    input wire rst,

    input wire[`InstBus] inst_i,            // 指令内容
    input wire[`InstAddrBus] inst_addr_i,   // 指令地址

    input wire[`Hold_Flag_Bus] hold_flag_i, // 流水线暂停标志

    input wire[`INT_BUS] int_flag_i,        // 外设中断输入信号
    output wire[`INT_BUS] int_flag_o,

    output wire[`InstBus] inst_o,           // 指令内容
    output wire[`InstAddrBus] inst_addr_o,   // 指令地址

    input wire inst_resp_i,               // rib模块响应信号
    input wire ex_hold_i,                 // ex模块暂停信号
    input wire jump_flag_i,               // ctrl模块跳转信号
    input wire clint_hold_i,              // clint模块暂停信号
    input wire jtag_hold_i                // jtag模块暂停信号

    );

    wire hold_en = (hold_flag_i >= `Hold_If);

    reg int_start_to_next_inst ;                        // 中断处理中
    reg jtag_start_to_next_inst ;                       // jtag处理中
    reg ex_start_to_next_inst ;                         // ex处理中
    reg jump_start_to_next_inst ;                       // jump处理中
    reg ex_hold_reg ;                             // ex模块暂停信号

    wire inst_fetch_cancel ; 

    // ex模块暂停信号打一拍的输出信号
    always @ ( posedge clk ) begin
        if (rst == `RstEnable) begin
            ex_hold_reg <= 1'b0 ;
        end
        else begin
            ex_hold_reg <= ex_hold_i ;
        end
    end

    assign ex_end = ex_hold_reg && ! ex_hold_i ; // 标志特殊指令执行完成后的第一个时钟周期

    // 中断处理标志
    always @ ( posedge clk ) begin
        if (rst == `RstEnable) begin
            int_start_to_next_inst <= 1'b0 ;
        end
        else if ( clint_hold_i == `HoldEnable && !inst_resp_i ) begin
            int_start_to_next_inst <= 1'b1 ;
        end
        else if ( int_start_to_next_inst && inst_resp_i ) begin
            int_start_to_next_inst <= 1'b0 ;
        end 
    end 

    // jtag处理标志
    always @ ( posedge clk ) begin
        if (rst == `RstEnable) begin
            jtag_start_to_next_inst <= 1'b0 ;
        end
        else if ( jtag_hold_i == `HoldEnable && !inst_resp_i ) begin
            jtag_start_to_next_inst <= 1'b1 ;
        end
        else if ( jtag_start_to_next_inst && inst_resp_i ) begin
            jtag_start_to_next_inst <= 1'b0 ;
        end 
    end 

    // ex模块处理标志
    always @ ( posedge clk ) begin
        if (rst == `RstEnable) begin
            ex_start_to_next_inst <= 1'b0 ;
        end
        else if ( ex_hold_i == `HoldEnable && !inst_resp_i ) begin
            ex_start_to_next_inst <= 1'b1 ;
        end
        else if ( ex_start_to_next_inst && inst_resp_i ) begin
            ex_start_to_next_inst <= 1'b0 ;
        end 
    end 

    // 跳转处理标志
    always @ ( posedge clk ) begin
        if (rst == `RstEnable) begin
            jump_start_to_next_inst <= 1'b0 ;
        end
        else if ( jump_flag_i == `JumpEnable && !inst_resp_i ) begin
            jump_start_to_next_inst <= 1'b1 ;
        end
        else if ( jump_start_to_next_inst && inst_resp_i ) begin
            jump_start_to_next_inst <= 1'b0 ;
        end 
    end 

    assign inst_fetch_cancel = ( jump_flag_i && inst_resp_i ) || ( clint_hold_i && inst_resp_i ) || jump_start_to_next_inst || int_start_to_next_inst ; 

    always @( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            inst_o <= `INST_NOP ;
            inst_addr_o <= `ZeroWord ;
        end
        else if ( inst_fetch_cancel ) begin
            inst_o <= `INST_NOP ;
            inst_addr_o <= `ZeroWord ;
        end
        else if ( ex_end && inst_resp_i ) begin
            inst_o <= inst_i ;
            inst_addr_o <= inst_addr_i ;
        end
        else if ( ex_end ) begin
            inst_o <= inst_temp ;
            inst_addr_o <= inst_addr_i ; 
        end
        else if ( inst_resp_i ) begin
            inst_o <= inst_i ;
            inst_addr_o <= inst_addr_i ;
        end 
        else begin
            inst_o <= `INST_NOP ;
            inst_addr_o <= `ZeroWord ;
        end
    end

    always @ ( posedge clk ) begin
        if ( rst == `RstEnable ) begin
            inst_temp <= `INST_NOP ;
            inst_addr_temp <= `ZeroWord ;
        end
        else if ( ex_start_to_next_inst && inst_resp_i ) begin
            inst_temp <= inst_i ;
        end
    end


    // wire[`InstBus] inst;
    // gen_pipe_dff #(32) inst_ff(clk, rst, hold_en, `INST_NOP, inst_i, inst);
    // assign inst_o = inst;



    //wire[`InstAddrBus] inst_addr;
    //gen_pipe_dff #(32) inst_addr_ff(clk, rst, hold_en, `ZeroWord, inst_addr_i - 4 , inst_addr);
    //assign inst_addr_o = inst_addr;

    

    wire[`INT_BUS] int_flag;
    gen_pipe_dff #(8) int_ff(clk, rst, hold_en, `INT_NONE, int_flag_i, int_flag);
    assign int_flag_o = int_flag;

endmodule
