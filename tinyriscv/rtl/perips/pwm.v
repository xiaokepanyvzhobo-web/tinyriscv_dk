/*
 Copyright 2026 Dickens Liu

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

module pwm(

    input wire clk,
    input wire rst,

    input wire we_i,
    input wire[`MemAddrBus] addr_i,
    input wire[`MemBus] data_i,

    output reg[`MemBus] data_o,
    output reg[3:0] PWM_o

    );

    localparam REG_A0 = 8'h00;
    localparam REG_A1 = 8'h01;
    localparam REG_A2 = 8'h02;
    localparam REG_A3 = 8'h03;
    localparam REG_C  = 8'h04;
    localparam REG_B0 = 8'h10;
    localparam REG_B1 = 8'h11;
    localparam REG_B2 = 8'h12;
    localparam REG_B3 = 8'h13;

    reg[`MemBus] pwm_period0;
    reg[`MemBus] pwm_period1;
    reg[`MemBus] pwm_period2;
    reg[`MemBus] pwm_period3;

    reg[`MemBus] pwm_high0;
    reg[`MemBus] pwm_high1;
    reg[`MemBus] pwm_high2;
    reg[`MemBus] pwm_high3;

    reg[`MemBus] pwm_ctrl;

    reg[`MemBus] pwm_cnt0;
    reg[`MemBus] pwm_cnt1;
    reg[`MemBus] pwm_cnt2;
    reg[`MemBus] pwm_cnt3;

    wire[7:0] reg_sel = addr_i[23:16];

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            pwm_period0 <= `ZeroWord;
            pwm_period1 <= `ZeroWord;
            pwm_period2 <= `ZeroWord;
            pwm_period3 <= `ZeroWord;
            pwm_high0 <= `ZeroWord;
            pwm_high1 <= `ZeroWord;
            pwm_high2 <= `ZeroWord;
            pwm_high3 <= `ZeroWord;
            pwm_ctrl <= `ZeroWord;
        end else if (we_i == `WriteEnable) begin
            case (reg_sel)
                REG_A0: pwm_period0 <= data_i;
                REG_A1: pwm_period1 <= data_i;
                REG_A2: pwm_period2 <= data_i;
                REG_A3: pwm_period3 <= data_i;
                REG_C:  pwm_ctrl <= data_i;
                REG_B0: pwm_high0 <= data_i;
                REG_B1: pwm_high1 <= data_i;
                REG_B2: pwm_high2 <= data_i;
                REG_B3: pwm_high3 <= data_i;
                default: begin
                    pwm_period0 <= pwm_period0;
                    pwm_period1 <= pwm_period1;
                    pwm_period2 <= pwm_period2;
                    pwm_period3 <= pwm_period3;
                    pwm_high0 <= pwm_high0;
                    pwm_high1 <= pwm_high1;
                    pwm_high2 <= pwm_high2;
                    pwm_high3 <= pwm_high3;
                    pwm_ctrl <= pwm_ctrl;
                end
            endcase
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            pwm_cnt0 <= `ZeroWord;
        end else if ((pwm_ctrl[0] == 1'b0) || (pwm_period0 == `ZeroWord)) begin
            pwm_cnt0 <= `ZeroWord;
        end else if (pwm_cnt0 >= (pwm_period0 - 1'b1)) begin
            pwm_cnt0 <= `ZeroWord;
        end else begin
            pwm_cnt0 <= pwm_cnt0 + 1'b1;
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            pwm_cnt1 <= `ZeroWord;
        end else if ((pwm_ctrl[1] == 1'b0) || (pwm_period1 == `ZeroWord)) begin
            pwm_cnt1 <= `ZeroWord;
        end else if (pwm_cnt1 >= (pwm_period1 - 1'b1)) begin
            pwm_cnt1 <= `ZeroWord;
        end else begin
            pwm_cnt1 <= pwm_cnt1 + 1'b1;
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            pwm_cnt2 <= `ZeroWord;
        end else if ((pwm_ctrl[2] == 1'b0) || (pwm_period2 == `ZeroWord)) begin
            pwm_cnt2 <= `ZeroWord;
        end else if (pwm_cnt2 >= (pwm_period2 - 1'b1)) begin
            pwm_cnt2 <= `ZeroWord;
        end else begin
            pwm_cnt2 <= pwm_cnt2 + 1'b1;
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            pwm_cnt3 <= `ZeroWord;
        end else if ((pwm_ctrl[3] == 1'b0) || (pwm_period3 == `ZeroWord)) begin
            pwm_cnt3 <= `ZeroWord;
        end else if (pwm_cnt3 >= (pwm_period3 - 1'b1)) begin
            pwm_cnt3 <= `ZeroWord;
        end else begin
            pwm_cnt3 <= pwm_cnt3 + 1'b1;
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            PWM_o <= 4'b0000;
        end else begin
            PWM_o[0] <= (pwm_ctrl[0] == 1'b1) && (pwm_period0 != `ZeroWord) &&
                        (pwm_high0 != `ZeroWord) && (pwm_cnt0 < pwm_high0);
            PWM_o[1] <= (pwm_ctrl[1] == 1'b1) && (pwm_period1 != `ZeroWord) &&
                        (pwm_high1 != `ZeroWord) && (pwm_cnt1 < pwm_high1);
            PWM_o[2] <= (pwm_ctrl[2] == 1'b1) && (pwm_period2 != `ZeroWord) &&
                        (pwm_high2 != `ZeroWord) && (pwm_cnt2 < pwm_high2);
            PWM_o[3] <= (pwm_ctrl[3] == 1'b1) && (pwm_period3 != `ZeroWord) &&
                        (pwm_high3 != `ZeroWord) && (pwm_cnt3 < pwm_high3);
        end
    end

    always @ (*) begin
        if (rst == `RstEnable) begin
            data_o = `ZeroWord;
        end else begin
            case (reg_sel)
                REG_A0: data_o = pwm_period0;
                REG_A1: data_o = pwm_period1;
                REG_A2: data_o = pwm_period2;
                REG_A3: data_o = pwm_period3;
                REG_C:  data_o = pwm_ctrl;
                REG_B0: data_o = pwm_high0;
                REG_B1: data_o = pwm_high1;
                REG_B2: data_o = pwm_high2;
                REG_B3: data_o = pwm_high3;
                default: data_o = `ZeroWord;
            endcase
        end
    end

endmodule
