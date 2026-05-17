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

 //`include "defines.v"

`define MemAddrBus 31:0
`define MemBus     31:0

module i2c_controller #(
    parameter SYS_FREQ = 50_000_000, // 假设系统时钟为50MHz，请按实际修改
    parameter I2C_FREQ = 100_000     // 100KHz 标准I2C频率
)(
    input  wire                  clk      , 
    input  wire                  rst      , // 高电平复位
    input  wire [1:0]            req_i    , // 10=Write, 11=Read
    input  wire                  we_i     , // 写内部寄存器使能
    input  wire [`MemAddrBus]    addr_i   , 
    input  wire [`MemBus]        data_i   ,

    output reg  [`MemBus]        data_o   , 
    output reg                   ack_o    , 
    
    // IIC 物理接口
    output wire                  SCL_o    ,   
    output reg                   SDA_o    ,   
    output reg                   SDA_oe_o , // SDA输出使能：1为驱动(输出SDA_o)，0为高阻态(读SDA_i)
    input  wire                  SDA_i    
);

//---------------------------------------------------
// 1. 内部寄存器定义与总线读写 (同步写, 异步读)
//---------------------------------------------------
reg [31:0] slave_addr_reg;   // 0x7001_0000
reg [31:0] i2c_out_data_reg; // 0x7002_0000
reg [31:0] i2c_in_data_reg;  // 0x7003_0000

// 异步读 (当总线发出寻址时立刻组合逻辑反馈数据，如果不在读寄存器，也保持最后读出的结果)
always @(*) begin
    case (addr_i)
        32'h7001_0000: data_o = slave_addr_reg;
        32'h7002_0000: data_o = i2c_out_data_reg;
        32'h7003_0000: data_o = i2c_in_data_reg;
        default:       data_o = i2c_out_data_reg; 
    endcase
end

// 同步写 
always @(posedge clk) begin
    if (rst) begin
        slave_addr_reg   <= 32'b0;
        i2c_out_data_reg <= 32'b0;
    end else if (we_i) begin
        case (addr_i)
            32'h7001_0000: slave_addr_reg   <= data_i;
            32'h7002_0000: i2c_out_data_reg <= data_i;
            // 注：0x7003_0000为输入(只读)寄存器，由I2C硬件FSM更新，不接受总线写入
        endcase
    end
end

//---------------------------------------------------
// 2. I2C 分频节拍发生器 (4倍于I2C频率)
//---------------------------------------------------
localparam TICK_DIV = SYS_FREQ / (I2C_FREQ * 4);
reg [15:0] tick_cnt;
wire       tick = (tick_cnt == TICK_DIV - 1);

always @(posedge clk) begin
    if (rst)          tick_cnt <= 0;
    else if (tick)    tick_cnt <= 0;
    else              tick_cnt <= tick_cnt + 1;
end

//---------------------------------------------------
// 3. I2C 核心状态机定义
//---------------------------------------------------
localparam IDLE         = 5'd0;
localparam START        = 5'd1;
localparam SEND_ADDR_W  = 5'd2;
localparam ACK1         = 5'd3;
localparam SEND_PTR     = 5'd4;
localparam ACK2         = 5'd5;
localparam REP_START    = 5'd6;
localparam SEND_ADDR_R  = 5'd7;
localparam ACK3         = 5'd8;
localparam READ_MSB     = 5'd9;
localparam SEND_ACK     = 5'd10;
localparam READ_LSB     = 5'd11;
localparam SEND_NACK    = 5'd12;
localparam WRITE_MSB    = 5'd13;
localparam ACK_W1       = 5'd14;
localparam WRITE_LSB    = 5'd15;
localparam ACK_W2       = 5'd16;
localparam STOP         = 5'd17;

reg [4:0]  state;
reg [1:0]  phase;      // 0~3, 一个I2C bit划分为4个操作相位
reg [2:0]  bit_cnt;    // 7~0, 传输字节的位计数器
reg        rw_flag;    // 0=Write, 1=Read
reg [15:0] read_data;  // 暂存从总线上读回的16位数据

//---------------------------------------------------
// 4. 状态机跳转与数据采样控制
//---------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        state           <= IDLE;
        phase           <= 0;
        bit_cnt         <= 7;
        rw_flag         <= 0;
        ack_o           <= 0;
        i2c_in_data_reg <= 0;
    end else begin
        // 清除单周期完成脉冲
        if (ack_o) ack_o <= 0;

        if (state == IDLE) begin
            if (req_i == 2'b10) begin         // 启动 Write
                state   <= START;
                rw_flag <= 0;
                phase   <= 0;
                bit_cnt <= 7;
            end else if (req_i == 2'b11) begin // 启动 Read
                state   <= START;
                rw_flag <= 1;
                phase   <= 0;
                bit_cnt <= 7;
            end
        end else if (tick) begin
            phase <= phase + 1; // 相位推进
            
            // 数据采样发生在 Phase 1(此时SCL处于高电平安全期)
            if (phase == 1) begin
                if (state == READ_MSB) read_data[bit_cnt + 8] <= SDA_i;
                if (state == READ_LSB) read_data[bit_cnt]     <= SDA_i;
            end
            
            // 相位3结束时，推进状态
            if (phase == 3) begin
                case (state)
                    START:       state <= SEND_ADDR_W;
                    SEND_ADDR_W: state <= (bit_cnt == 0) ? ACK1 : SEND_ADDR_W;
                    ACK1:        state <= SEND_PTR;
                    SEND_PTR:    state <= (bit_cnt == 0) ? ACK2 : SEND_PTR;
                    ACK2:        state <= rw_flag ? REP_START : WRITE_MSB; // 根据读写类型分叉
                    
                    // 读分支 (Read Flow)
                    REP_START:   state <= SEND_ADDR_R;
                    SEND_ADDR_R: state <= (bit_cnt == 0) ? ACK3 : SEND_ADDR_R;
                    ACK3:        state <= READ_MSB;
                    READ_MSB:    state <= (bit_cnt == 0) ? SEND_ACK : READ_MSB;
                    SEND_ACK:    state <= READ_LSB;
                    READ_LSB:    state <= (bit_cnt == 0) ? SEND_NACK : READ_LSB;
                    SEND_NACK:   state <= STOP;
                    
                    // 写分支 (Write Flow)
                    WRITE_MSB:   state <= (bit_cnt == 0) ? ACK_W1 : WRITE_MSB;
                    ACK_W1:      state <= WRITE_LSB;
                    WRITE_LSB:   state <= (bit_cnt == 0) ? ACK_W2 : WRITE_LSB;
                    ACK_W2:      state <= STOP;
                    
                    STOP: begin
                        state <= IDLE;
                        ack_o <= 1; // 读写过程完成产生单周期脉冲
                        // 将LM75读出的温度数据写入对应寄存器锁存，使其能随时被总线读到
                        if (rw_flag == 1) i2c_in_data_reg <= {16'h0000, read_data};
                    end
                endcase

                // 位计数器轮转逻辑
                if (state == SEND_ADDR_W || state == SEND_PTR || state == SEND_ADDR_R ||
                    state == READ_MSB || state == READ_LSB || state == WRITE_MSB || state == WRITE_LSB) begin
                    if (bit_cnt == 0) bit_cnt <= 7;
                    else              bit_cnt <= bit_cnt - 1;
                end else begin
                    bit_cnt <= 7;
                end
            end
        end
    end
end

//---------------------------------------------------
// 5. I2C SCL与SDA 组合逻辑物理层输出控制
//---------------------------------------------------

// SCL_o 时钟物理输出
reg scl_reg;
assign SCL_o = scl_reg;
always @(*) begin
    case (state)
        IDLE:      scl_reg = 1'b1;
        START:     scl_reg = (phase < 2) ? 1'b1 : 1'b0;  // phase=2 SCL拉低
        REP_START: scl_reg = (phase == 0 || phase == 3) ? 1'b0 : 1'b1;
        STOP:      scl_reg = (phase == 0) ? 1'b0 : 1'b1; // phase=1 SCL拉高
        default:   scl_reg = (phase == 1 || phase == 2) ? 1'b1 : 1'b0; // 常规周期：中间1和2时SCL保持高电平
    endcase
end

// SDA_o 数据输出及其方向使能控制
always @(*) begin
    SDA_o    = 1'b1;
    SDA_oe_o = 1'b0; // 默认将方向交给从机 (0:输入高阻态, 1:输出状态)
    
    case (state)
        IDLE: begin
            SDA_o = 1'b1;  SDA_oe_o = 1'b0; 
        end
        START: begin
            SDA_o = (phase == 0) ? 1'b1 : 1'b0; // Phase1时拉低SDA发起起始
            SDA_oe_o = 1'b1;
        end
        REP_START: begin
            SDA_o = (phase < 2) ? 1'b1 : 1'b0;
            SDA_oe_o = 1'b1;
        end
        STOP: begin
            SDA_o = (phase < 2) ? 1'b0 : 1'b1;  // Phase2时拉高SDA产生停止
            SDA_oe_o = 1'b1;
        end
        SEND_ADDR_W: begin
            // 7:1位来自寄存器7:1位，第0位是写(0)
            SDA_o = (bit_cnt == 0) ? 1'b0 : slave_addr_reg[bit_cnt];
            SDA_oe_o = 1'b1;
        end
        SEND_ADDR_R: begin
            // 7:1位来自寄存器7:1位，第0位是读(1)
            SDA_o = (bit_cnt == 0) ? 1'b1 : slave_addr_reg[bit_cnt];
            SDA_oe_o = 1'b1;
        end
        SEND_PTR: begin
            // 取从设备地址寄存器第9、8位：发数据时补齐高6位0 (8位长度)
            SDA_o = (bit_cnt > 1) ? 1'b0 : slave_addr_reg[8 + bit_cnt];
            SDA_oe_o = 1'b1;
        end
        WRITE_MSB: begin
            SDA_o = i2c_out_data_reg[8 + bit_cnt]; // 低16位的高8位 [15:8]
            SDA_oe_o = 1'b1;
        end
        WRITE_LSB: begin
            SDA_o = i2c_out_data_reg[bit_cnt];     // 低16位的低8位 [7:0]
            SDA_oe_o = 1'b1;
        end
        SEND_ACK: begin
            SDA_o = 1'b0;  // 主机给Ack拉低
            SDA_oe_o = 1'b1;
        end
        SEND_NACK: begin
            SDA_o = 1'b1;  // 主机给Nack拉高
            SDA_oe_o = 1'b1;
        end
        // 对于 ACK1, ACK2, ACK3, ACK_W1, ACK_W2, READ_MSB, READ_LSB
        // 维持默认 SDA_oe_o = 1'b0，释放总线去读取状态
        default: begin
            SDA_oe_o = 1'b0; 
        end
    endcase
end

endmodule