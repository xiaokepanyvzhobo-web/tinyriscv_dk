/* ============================================================================
 * 微处理器结构与设计 — 第二次课程作业
 * IIC 总线控制器（IIC Controller）—— 面向 LM75 温度传感器
 *
 * 设计说明：
 *   本模块实现了一个符合 IIC 标准协议的主设备控制器，专用于对 LM75 系列
 *   温度传感器内部寄存器进行读写操作。
 *
 * 内部寄存器（同步写，异步读）：
 *   ┌──────────────────┬─────────────────┬─────────────────────────────┐
 *   │ 寄存器名         │ 地址 (addr_i)   │ 功能说明                    │
 *   ├──────────────────┼─────────────────┼─────────────────────────────┤
 *   │ 从设备地址寄存器 │ 0x7001_0000     │ [7:0]=IIC从设备地址(7位)   │
 *   │  (slave_addr)    │                 │ [9:8]=Pointer(寄存器指针)   │
 *   ├──────────────────┼─────────────────┼─────────────────────────────┤
 *   │ 输出数据寄存器   │ 0x7002_0000     │ 读操作结果锁存到此寄存器    │
 *   │  (data_out_reg)  │                 │                             │
 *   ├──────────────────┼─────────────────┼─────────────────────────────┤
 *   │ 输入数据寄存器   │ 0x7003_0000     │ 写操作数据取自低 16 位      │
 *   │  (data_in_reg)   │                 │                             │
 *   └──────────────────┴─────────────────┴─────────────────────────────┘
 *
 * 接口信号说明：
 *   req_i[1] = 功能使能, req_i[0] = IIC读写方向 (0=写, 1=读)
 *   we_i     = 内部寄存器写使能
 *   addr_i   = 内部寄存器地址
 *   data_i   = 写入内部寄存器的数据
 *   data_o   = 从内部寄存器读出的数据；当 ack_o=1 时输出的是结果数据
 *   ack_o    = IIC 传输完成脉冲信号（维持 1 周期）
 *   SCL_o    = IIC 时钟线输出
 *   SDA_o    = IIC 数据线输出值
 *   SDA_oe_o = SDA 输出使能 (1=驱动, 0=高阻态释放)
 *   SDA_i    = IIC 数据线输入值
 *
 * IIC 写协议 (LM75, req_i = 2'b10)：
 *   ┌─────┬──────────┬───────┬─────────┬───────┬────────────┬───────┬────────────┬───────┬──────┐
 *   │START│DevAddr+W │Slv ACK│ Pointer │Slv ACK│ Data_MSB   │Slv ACK│ Data_LSB   │Slv ACK│ STOP │
 *   └─────┴──────────┴───────┴─────────┴───────┴────────────┴───────┴────────────┴───────┴──────┘
 *
 * IIC 读协议 (LM75, req_i = 2'b11)：
 *   ┌─────┬──────────┬───────┬─────────┬───────┬─────┬───────┬──────────┬───────┬───────────┬──────────┬───────┬──────────┬──────┐
 *   │START│DevAddr+W │Slv ACK│ Pointer │Slv ACK│RESTART│DevAddr+R│Slv ACK│ Data_MSB  │Mst ACK=0 │Data_LSB│Mst ACK=1│ STOP │
 *   └─────┴──────────┴───────┴─────────┴───────┴─────┴───────┴──────────┴───────┴───────────┴──────────┴───────┴──────────┴──────┘
 *
 * 时钟分频：
 *   SYS_CLK = 100 MHz,  I2C_CLK = 100 kHz
 *   CLK_DIV = SYS_CLK / (4 * I2C_CLK) = 250
 *
 * 作者：课程作业
 * 日期：2026-05-18
 * ============================================================================ */

`include "../core/defines.v"

module iic_controller #(
    parameter integer CLK_DIV = `CLK_DIVIDER
)(
    input  wire               clk,
    input  wire               rst,

    // ─── 总线接口 ────────────────────────────────────────
    input  wire [1:0]         req_i,       // [1]=使能, [0]=读写方向(0写1读)
    input  wire               we_i,        // 内部寄存器写使能
    input  wire [`MemAddrBus] addr_i,      // 内部寄存器地址
    input  wire [`MemBus]     data_i,      // 待写入内部寄存器的数据

    output reg  [`MemBus]     data_o,      // 内部寄存器读出/结果数据
    output reg                ack_o,       // IIC 传输完成脉冲

    // ─── IIC 物理接口 ────────────────────────────────────
    output wire               SCL_o,       // IIC 时钟线
    output reg                SDA_o,       // IIC 数据线输出
    output reg                SDA_oe_o,    // SDA 输出使能 (1=drive, 0=高阻)
    input  wire               SDA_i        // IIC 数据线输入
);

    // ====================================================================
    //  1. 内部寄存器定义
    // ====================================================================

    // ─── 寄存器地址译码 ──────────────────────────────────
    wire addr_slave_sel = (addr_i[23:16] == 8'h01);   // 0x7001_0000
    wire addr_out_sel   = (addr_i[23:16] == 8'h02);   // 0x7002_0000
    wire addr_in_sel    = (addr_i[23:16] == 8'h03);   // 0x7003_0000

    // ─── 三个内部寄存器 ─────────────────────────────────
    reg [`MemBus] slave_addr_reg;     // 从设备地址寄存器
    reg [`MemBus] output_data_reg;    // 输出数据寄存器
    reg [`MemBus] input_data_reg;     // 输入数据寄存器

    // ─── 异步读（组合逻辑，从控制器内部读出寄存器值）─────
    always @ (*) begin
        if (ack_o == 1'b1) begin
            data_o = output_data_reg;        // 完成时读出最终结果
        end else begin
            case (1'b1)
                addr_slave_sel: data_o = slave_addr_reg;
                addr_out_sel:   data_o = output_data_reg;
                addr_in_sel:    data_o = input_data_reg;
                default:        data_o = `ZeroWord;
            endcase
        end
    end

    // ====================================================================
    //  2. 状态机定义
    // ====================================================================

    // ─── 主状态机状态编码 ────────────────────────────────
    localparam [4:0] ST_IDLE        = 5'd0;   // 空闲，等待 req_i

    // START 条件（3 状态）：SCL=1, SDA 1→0, 然后 SCL→0
    localparam [4:0] ST_START_A     = 5'd1;   // SCL=1, SDA=1 (空闲电平)
    localparam [4:0] ST_START_B     = 5'd2;   // SCL=1, SDA=0 (START条件)
    localparam [4:0] ST_START_C     = 5'd3;   // SCL=0, SDA=0

    // 发送字节（3 状态/bit）：
    localparam [4:0] ST_SEND_LOW    = 5'd4;   // SCL=0, 驱动SDA
    localparam [4:0] ST_SEND_HIGH   = 5'd5;   // SCL=1, 从设备采样
    localparam [4:0] ST_SEND_FALL   = 5'd6;   // SCL=0, 准备下一bit

    // 接收 ACK（3 状态）：
    localparam [4:0] ST_ACK_LOW     = 5'd7;   // SCL=0, 释放SDA
    localparam [4:0] ST_ACK_HIGH    = 5'd8;   // SCL=1, 采样SDA
    localparam [4:0] ST_ACK_FALL    = 5'd9;   // SCL=0, 判断ACK/NACK

    // Repeated START（4 状态）：在读操作中用于方向切换
    localparam [4:0] ST_REP_A       = 5'd10;  // SCL=0, 释放SDA
    localparam [4:0] ST_REP_B       = 5'd11;  // SCL=1
    localparam [4:0] ST_REP_C       = 5'd12;  // SCL=1, SDA=0 (ReSTART)
    localparam [4:0] ST_REP_D       = 5'd13;  // SCL=0, SDA=0

    // 接收字节（3 状态/bit）：
    localparam [4:0] ST_READ_LOW    = 5'd14;  // SCL=0, 准备采样
    localparam [4:0] ST_READ_HIGH   = 5'd15;  // SCL=1, 采样SDA到移位寄存器
    localparam [4:0] ST_READ_FALL   = 5'd16;  // SCL=0, 准备下一bit

    // 主机 ACK/NACK（3 状态）：
    localparam [4:0] ST_MACK_LOW    = 5'd17;  // SCL=0, 驱动ACK/NACK
    localparam [4:0] ST_MACK_HIGH   = 5'd18;  // SCL=1
    localparam [4:0] ST_MACK_FALL   = 5'd19;  // SCL=0

    // STOP 条件（3 状态）：SCL=0, SDA 0→1
    localparam [4:0] ST_STOP_A      = 5'd20;  // SCL=0, SDA=0
    localparam [4:0] ST_STOP_B      = 5'd21;  // SCL=1, SDA=0
    localparam [4:0] ST_STOP_C      = 5'd22;  // SCL=1, SDA=0→1 (STOP条件)

    // 完成
    localparam [4:0] ST_DONE        = 5'd23;  // 输出 ack_o，下一周期到 IDLE

    // ─── 传输阶段编码 ────────────────────────────────────
    localparam [2:0] PH_WR_ADDR     = 3'd0;   // 写流程：发送从设备地址+W
    localparam [2:0] PH_WR_PTR      = 3'd1;   // 写流程：发送 Pointer
    localparam [2:0] PH_WR_DATA_H   = 3'd2;   // 写流程：发送数据高字节
    localparam [2:0] PH_WR_DATA_L   = 3'd3;   // 写流程：发送数据低字节
    localparam [2:0] PH_RD_ADDR_W   = 3'd4;   // 读流程：发送从设备地址+W
    localparam [2:0] PH_RD_PTR      = 3'd5;   // 读流程：发送 Pointer
    localparam [2:0] PH_RD_ADDR_R   = 3'd6;   // 读流程：发送从设备地址+R

    // ====================================================================
    //  3. 控制信号和寄存器
    // ====================================================================

    reg [4:0] state;                   // 当前状态
    reg [4:0] state_next;              // 下一状态（组合逻辑）
    reg [2:0] phase;                   // 当前传输阶段
    reg [2:0] bit_cnt;                 // 位计数器（7→0）
    reg [15:0] clk_cnt;                // SCL分频计数器

    reg scl_reg;                       // SCL寄存器

    // ─── 锁存 req_i 信息 ──────────────────────────────────
    reg rw_latched;                    // 锁存的读写方向
    reg [7:0] slave_addr_wr;           // 7位地址+R/W=0
    reg [7:0] slave_addr_rd;           // 7位地址+R/W=1
    reg [7:0] pointer_byte;            // Pointer 字节 (6'b0 + {2-bit pointer})
    reg [15:0] write_data;             // 待写入的数据（16位）

    // ─── 发送/接收寄存器 ──────────────────────────────────
    reg [7:0] tx_byte;                 // 当前发送字节
    reg [7:0] rx_shift;                // 接收移位寄存器
    reg [15:0] read_data_tmp;          // 读数据暂存

    // ─── 控制标志 ────────────────────────────────────────
    reg read_byte_index;               // 读字节序号 (0=MSB, 1=LSB)
    reg master_nack;                   // 主机是否发NACK（最后一个字节）

    // ====================================================================
    //  4. SCL 生成
    // ====================================================================

    wire clk_tick = (clk_cnt == (CLK_DIV - 1));

    assign SCL_o = scl_reg;

    // ====================================================================
    //  5. 状态寄存器（时序逻辑）
    // ====================================================================

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    // ====================================================================
    //  6. 下一状态逻辑（组合逻辑）
    //      注意：在 IDLE 和 DONE 状态使用异步跳转，
    //      其余状态由 clk_tick 同步驱动，使每 bit 持续 CLK_DIV 个周期
    // ====================================================================

    always @ (*) begin
        state_next = state;

        case (state)
            // ── IDLE：检测 req_i[1] 有效，立即启动 ──────
            ST_IDLE: begin
                if (req_i[1] == 1'b1) begin
                    state_next = ST_START_A;
                end
            end

            // ── DONE：输出 ack_o 脉冲后自动回到 IDLE ──────
            ST_DONE: begin
                state_next = ST_IDLE;
            end

            // ── 其余状态：由 clk_tick 驱动 ──────────────
            default: begin
                if (clk_tick == 1'b1) begin
                    case (state)
                        // --------------------------------------------------------------------
                        // START 条件序列
                        // --------------------------------------------------------------------
                        ST_START_A:   state_next = ST_START_B;
                        ST_START_B:   state_next = ST_START_C;
                        ST_START_C:   state_next = ST_SEND_LOW;

                        // --------------------------------------------------------------------
                        // 发送字节：SEND_LOW → SEND_HIGH → SEND_FALL 循环 8 次
                        // --------------------------------------------------------------------
                        ST_SEND_LOW:  state_next = ST_SEND_HIGH;
                        ST_SEND_HIGH: state_next = ST_SEND_FALL;
                        ST_SEND_FALL: state_next = (bit_cnt == 3'd0) ? ST_ACK_LOW : ST_SEND_LOW;

                        // --------------------------------------------------------------------
                        // 等待从设备 ACK
                        // --------------------------------------------------------------------
                        ST_ACK_LOW:   state_next = ST_ACK_HIGH;
                        ST_ACK_HIGH:  state_next = ST_ACK_FALL;

                        // --------------------------------------------------------------------
                        // ACK 后根据阶段分发到下一个目标
                        // --------------------------------------------------------------------
                        ST_ACK_FALL: begin
                            case (phase)
                                // 写流程：依次发送地址 → Pointer → 数据H → 数据L
                                PH_WR_ADDR:    state_next = ST_SEND_LOW;
                                PH_WR_PTR:     state_next = ST_SEND_LOW;
                                PH_WR_DATA_H:  state_next = ST_SEND_LOW;
                                PH_WR_DATA_L:  state_next = ST_STOP_A;

                                // 读流程：地址+W → Pointer → Repeated START → 地址+R
                                PH_RD_ADDR_W:  state_next = ST_SEND_LOW;
                                PH_RD_PTR:     state_next = ST_REP_A;
                                PH_RD_ADDR_R:  state_next = ST_READ_LOW;

                                default:       state_next = ST_STOP_A;
                            endcase
                        end

                        // --------------------------------------------------------------------
                        // Repeated START 序列（读流程中地址方向切换）
                        // --------------------------------------------------------------------
                        ST_REP_A:     state_next = ST_REP_B;
                        ST_REP_B:     state_next = ST_REP_C;
                        ST_REP_C:     state_next = ST_REP_D;
                        ST_REP_D:     state_next = ST_SEND_LOW;

                        // --------------------------------------------------------------------
                        // 接收字节：READ_LOW → READ_HIGH → READ_FALL 循环 8 次
                        // --------------------------------------------------------------------
                        ST_READ_LOW:  state_next = ST_READ_HIGH;
                        ST_READ_HIGH: state_next = ST_READ_FALL;
                        ST_READ_FALL: state_next = (bit_cnt == 3'd0) ? ST_MACK_LOW : ST_READ_LOW;

                        // --------------------------------------------------------------------
                        // 主机 ACK/NACK
                        // --------------------------------------------------------------------
                        ST_MACK_LOW:  state_next = ST_MACK_HIGH;
                        ST_MACK_HIGH: state_next = ST_MACK_FALL;
                        ST_MACK_FALL: state_next = (master_nack == 1'b1) ? ST_STOP_A : ST_READ_LOW;

                        // --------------------------------------------------------------------
                        // STOP 条件序列
                        // --------------------------------------------------------------------
                        ST_STOP_A:    state_next = ST_STOP_B;
                        ST_STOP_B:    state_next = ST_STOP_C;
                        ST_STOP_C:    state_next = ST_DONE;

                        default:      state_next = ST_IDLE;
                    endcase
                end
            end
        endcase
    end

    // ====================================================================
    //  7. 数据路径和寄存器输出（时序逻辑）
    //     包含：内部寄存器同步写、状态机数据操作、SCL/SDA控制
    // ====================================================================

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            // ── 内部寄存器复位 ───────────────────────────
            slave_addr_reg  <= 32'h0000_0090;   // 默认 LM75 地址 0x48+0
            output_data_reg <= `ZeroWord;
            input_data_reg  <= `ZeroWord;

            // ── 状态机控制复位 ───────────────────────────
            phase            <= PH_WR_ADDR;
            bit_cnt          <= 3'd7;
            clk_cnt          <= 16'h0;
            scl_reg          <= 1'b1;
            SDA_o            <= 1'b1;
            SDA_oe_o         <= 1'b0;
            ack_o            <= 1'b0;

            rw_latched       <= 1'b0;
            read_byte_index  <= 1'b0;
            master_nack      <= 1'b0;

            slave_addr_wr    <= 8'h90;   // 0x48 << 1 | 0
            slave_addr_rd    <= 8'h91;   // 0x48 << 1 | 1
            pointer_byte     <= 8'h00;
            tx_byte          <= 8'h00;
            rx_shift         <= 8'h00;
            write_data       <= 16'h0000;
            read_data_tmp    <= 16'h0000;

        end else begin
            // ── ack_o 默认为 0（仅在 ST_DONE 置 1）──
            ack_o <= 1'b0;

            // ================================================================
            //  7.1 内部寄存器同步写
            //      当 we_i=1 且 addr_i 匹配时，将 data_i 写入对应寄存器
            // ================================================================
            if (we_i == `WriteEnable) begin
                case (1'b1)
                    addr_slave_sel: slave_addr_reg  <= data_i;
                    addr_out_sel:   output_data_reg <= data_i;
                    addr_in_sel:    input_data_reg  <= data_i;
                    default: begin end
                endcase
            end

            // ================================================================
            //  7.2 分频计数器
            //      IDLE 和 DONE 时清零，计数到 CLK_DIV-1 时清零（产生 clk_tick）
            // ================================================================
            if (state == ST_IDLE || state == ST_DONE) begin
                clk_cnt <= 16'h0;
            end else if (clk_tick == 1'b1) begin
                clk_cnt <= 16'h0;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end

            // ================================================================
            //  7.3 各状态下的数据路径操作
            // ================================================================

            // ────────────────────────────────────────────────
            // ST_IDLE：锁存触发信号，准备启动传输
            //   锁存 req_i 的方向信息、计算地址字节和 Pointer、
            //   读取待写入数据到 write_data 中
            // ────────────────────────────────────────────────
            if (state == ST_IDLE) begin
                scl_reg  <= 1'b1;
                SDA_o    <= 1'b1;
                SDA_oe_o <= 1'b0;

                if (req_i[1] == 1'b1) begin
                    rw_latched        <= req_i[0];
                    slave_addr_wr     <= {slave_addr_reg[7:1], 1'b0};    // 地址 + 写位
                    slave_addr_rd     <= {slave_addr_reg[7:1], 1'b1};    // 地址 + 读位
                    pointer_byte      <= {6'h0, slave_addr_reg[9:8]};    // Pointer = bits[9:8]
                    write_data        <= input_data_reg[15:0];           // 待写数据低 16 位
                    read_data_tmp     <= 16'h0000;                       // 清空读临时缓存
                    rx_shift          <= 8'h00;
                    bit_cnt           <= 3'd7;
                    read_byte_index   <= 1'b0;
                    master_nack       <= 1'b0;
                end

            // ────────────────────────────────────────────────
            // ST_DONE：输出结果，回到空闲
            //   产生 ack_o 脉冲，释放 SCL/SDA 总线
            // ────────────────────────────────────────────────
            end else if (state == ST_DONE) begin
                ack_o    <= 1'b1;
                scl_reg  <= 1'b1;
                SDA_o    <= 1'b1;
                SDA_oe_o <= 1'b0;

            // ────────────────────────────────────────────────
            // clk_tick 有效时的状态机数据操作
            // ────────────────────────────────────────────────
            end else if (clk_tick == 1'b1) begin
                case (state)

                    // ── ST_START_A：保持空闲电平 ──────
                    ST_START_A: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    // ── ST_START_B：SDA拉低，SCL保持高 → 产生START条件 ──
                    ST_START_B: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    // ── ST_START_C：SCL拉低，准备发送数据 ──
                    ST_START_C: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                        bit_cnt  <= 3'd7;
                        // 根据读写方向决定起始发送字节和阶段
                        if (rw_latched == 1'b0) begin
                            // 写流程：先发地址+W
                            tx_byte <= slave_addr_wr;
                            phase   <= PH_WR_ADDR;
                        end else begin
                            // 读流程：先发地址+W(Pointer写入)
                            tx_byte <= slave_addr_wr;
                            phase   <= PH_RD_ADDR_W;
                        end
                    end

                    // ── ST_SEND_LOW：SCL=0，设置SDA数据位 ──
                    ST_SEND_LOW: begin
                        scl_reg <= 1'b0;
                        if (tx_byte[bit_cnt] == 1'b0) begin
                            SDA_o    <= 1'b0;
                            SDA_oe_o <= 1'b1;
                        end else begin
                            SDA_o    <= 1'b1;
                            SDA_oe_o <= 1'b0;
                        end
                    end

                    // ── ST_SEND_HIGH：SCL=1，从设备采样数据 ──
                    ST_SEND_HIGH: begin
                        scl_reg <= 1'b1;
                    end

                    // ── ST_SEND_FALL：SCL=0，下一bit ──
                    ST_SEND_FALL: begin
                        scl_reg <= 1'b0;
                        if (bit_cnt != 3'd0) begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    // ── ST_ACK_LOW：SCL=0，释放SDA给从设备 ──
                    ST_ACK_LOW: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    // ── ST_ACK_HIGH：SCL=1，采样从设备ACK ──
                    ST_ACK_HIGH: begin
                        scl_reg <= 1'b1;
                    end

                    // ── ST_ACK_FALL：SCL=0，判断ACK并切换阶段 ──
                    ST_ACK_FALL: begin
                        scl_reg <= 1'b0;

                        case (phase)
                            // ── 写流程 ──────────────────
                            PH_WR_ADDR: begin
                                // 地址发送完成 → 发送 Pointer
                                tx_byte <= pointer_byte;
                                bit_cnt <= 3'd7;
                                phase   <= PH_WR_PTR;
                            end

                            PH_WR_PTR: begin
                                // Pointer 发送完成 → 发送数据高字节
                                tx_byte <= write_data[15:8];
                                bit_cnt <= 3'd7;
                                phase   <= PH_WR_DATA_H;
                            end

                            PH_WR_DATA_H: begin
                                // 数据高字节完成 → 发送数据低字节
                                tx_byte <= write_data[7:0];
                                bit_cnt <= 3'd7;
                                phase   <= PH_WR_DATA_L;
                            end

                            // ── 读流程 ──────────────────
                            PH_RD_ADDR_W: begin
                                // 地址发送完成 → 发送 Pointer
                                tx_byte <= pointer_byte;
                                bit_cnt <= 3'd7;
                                phase   <= PH_RD_PTR;
                            end

                            PH_RD_PTR: begin
                                // Pointer 发送完成 → 准备 Repeated START
                            end

                            PH_RD_ADDR_R: begin
                                // 地址+R 发送完成 → 准备接收数据
                                bit_cnt         <= 3'd7;
                                read_byte_index <= 1'b0;
                                rx_shift        <= 8'h00;
                            end

                            default: begin end
                        endcase
                    end

                    // ── ST_REP_A：SCL=0，释放SDA ──
                    ST_REP_A: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    // ── ST_REP_B：SCL=1 ──
                    ST_REP_B: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    // ── ST_REP_C：SCL=1，SDA=0 → Repeated START条件 ──
                    ST_REP_C: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    // ── ST_REP_D：SCL=0，准备发送地址+R ──
                    ST_REP_D: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                        tx_byte  <= slave_addr_rd;
                        bit_cnt  <= 3'd7;
                        phase    <= PH_RD_ADDR_R;
                    end

                    // ── ST_READ_LOW：SCL=0，释放SDA等待从设备驱动 ──
                    ST_READ_LOW: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    // ── ST_READ_HIGH：SCL=1，采样SDA数据位 ──
                    ST_READ_HIGH: begin
                        scl_reg           <= 1'b1;
                        rx_shift[bit_cnt] <= SDA_i;
                    end

                    // ── ST_READ_FALL：SCL=0，判断一个字节是否接收完毕 ──
                    ST_READ_FALL: begin
                        scl_reg <= 1'b0;
                        if (bit_cnt == 3'd0) begin
                            // 一个字节接收完毕
                            if (read_byte_index == 1'b0) begin
                                // 第 1 字节：保存到 read_data_tmp[15:8]，发 ACK
                                read_data_tmp[15:8] <= rx_shift;
                                master_nack         <= 1'b0;   // ACK
                            end else begin
                                // 第 2 字节：保存到 read_data_tmp[7:0]，发 NACK
                                read_data_tmp[7:0]  <= rx_shift;
                                output_data_reg     <= {16'h0000, read_data_tmp[15:8], rx_shift};
                                master_nack         <= 1'b1;   // NACK
                            end
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    // ── ST_MACK_LOW：SCL=0，驱动ACK/NACK ──
                    ST_MACK_LOW: begin
                        scl_reg <= 1'b0;
                        if (master_nack == 1'b1) begin
                            // NACK：释放 SDA（高电平）
                            SDA_o    <= 1'b1;
                            SDA_oe_o <= 1'b0;
                        end else begin
                            // ACK：SDA 拉低
                            SDA_o    <= 1'b0;
                            SDA_oe_o <= 1'b1;
                        end
                    end

                    // ── ST_MACK_HIGH：SCL=1，从设备采样ACK/NACK ──
                    ST_MACK_HIGH: begin
                        scl_reg <= 1'b1;
                    end

                    // ── ST_MACK_FALL：SCL=0，ACK后继续读取或停止 ──
                    ST_MACK_FALL: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;

                        if (master_nack == 1'b0) begin
                            // 继续接收下一个字节
                            read_byte_index <= 1'b1;
                            bit_cnt         <= 3'd7;
                            rx_shift        <= 8'h00;
                        end
                    end

                    // ── ST_STOP_A：SCL=0，SDA=0 ──
                    ST_STOP_A: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    // ── ST_STOP_B：SCL=1，SDA=0 ──
                    ST_STOP_B: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    // ── ST_STOP_C：SCL=1，SDA=1 → STOP条件 ──
                    ST_STOP_C: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    default: begin end
                endcase
            end
        end
    end

endmodule
