/*
ctrl_dk.v - 多周期处理器主控制模块（基于 hold=保持 语义）
*/
`include "defines.v"

module ctrl_dk(
    input wire clk,
    input wire rst,

    // from id_ex (ID/EX 寄存器输出，即 EX 看到的指令字)
    input wire [`InstBus] inst_at_ex_i,

    // from ex
    input wire jump_flag_i,
    input wire [`InstAddrBus] jump_addr_i,
    input wire ext_mem_req_i,
    input wire ext_mem_we_i,
    input wire mem_no_ack_i,
    input wire hold_flag_ex_i,            // 兼容保留
    input wire ife_use_uart,              // IF指令是否使用UART进行传回
    input wire ext_inst_done,                  // sID指令执行完毕的标志

    // from rib / bridge
    input wire hold_flag_rib_i,           // 兼容保留
    input wire if_ack_i,                  // 取指完成
    input wire mem_ack_i,                 // 访存完成

    // from div
    input wire div_busy_i,
    input wire div_ready_i,

    // from jtag
    input wire jtag_halt_flag_i,

    // from clint
    input wire hold_flag_clint_i,
    input wire int_assert_i,              // 中断响应
    input wire [`InstAddrBus] int_addr_i, // 中断向量

    // to pipeline registers
    output reg [`Hold_Flag_Bus] hold_flag_o,

    // to pc_reg
    output reg jump_flag_o,
    output reg [`InstAddrBus] jump_addr_o,

    // to bridge
    output wire if_req_o,
    output wire mem_req_o,
    output wire mem_we_o,                 // 受 FSM 控制的写使能

    // to ex (写回门控)
    output wire reg_we_gate_o,

    // to div
    output wire div_start_gate_o,
    output wire ext_inst_start_o,

    // for SB/SH 数据通路 (mem_rdata 旁路控制)
    output wire mem_rdata_use_latched_o,  // 1=用latched值, 0=用桥接当前值

    // 调试
    output wire [3:0] state_o
);

    // ========================================================================
    // 状态定义
    // ========================================================================
    localparam S_IF_REQ      = 4'd0;
    localparam S_IF_WAIT     = 4'd1;
    localparam S_LATCH_ID    = 4'd2;
    localparam S_EX          = 4'd3;
    localparam S_MEM_R_REQ   = 4'd4; 
    localparam S_MEM_R_WAIT  = 4'd5;
    localparam S_MEM_W_REQ   = 4'd6;
    localparam S_MEM_W_WAIT  = 4'd7;
    localparam S_DIV_WAIT    = 4'd8;
    localparam S_SID_REQ     = 4'd9;
    localparam S_SID_WAIT    = 4'd10;
    localparam S_RT_R_REQ    = 4'd11;
    localparam S_RT_R_WAIT   = 4'd12;
    localparam S_IFE_REQ     = 4'd13;
    localparam S_IFE_WAIT    = 4'd14;
    
    localparam S_DONE        = 4'd15;
    // 新增rT指令，读取传感器中的温度


    reg [3:0] state, next_state;

    // 跳转锁存
    reg                      jump_pending;
    reg [`InstAddrBus]       jump_addr_latched;

    // ========================================================================
    // 当前 EX 拍指令字段解码
    // ========================================================================
    wire [6:0] opcode = inst_at_ex_i[6:0];
    wire [2:0] funct3 = inst_at_ex_i[14:12];
    wire [6:0] funct7 = inst_at_ex_i[31:25];

    wire is_load_inst   = (opcode == `INST_TYPE_L);
    wire is_store_inst  = (opcode == `INST_TYPE_S);
    wire is_sw_inst     = is_store_inst && (funct3 == `INST_SW);
    wire is_sb_sh_inst  = is_store_inst && ((funct3 == `INST_SB) || (funct3 == `INST_SH));
    wire is_div_inst    = (opcode == `INST_TYPE_R_M)
                       && (funct7 == 7'b0000001)
                       && (funct3[2] == 1'b1);
    wire is_rT_inst     = ( opcode == `INST_EXTEND ) && ( funct3 == `INST_RT ) ;
    wire is_sID_inst    = ( opcode == `INST_EXTEND ) && ( funct3 == `INST_SID ) ;
    wire is_ife_inst    = ( opcode == `INST_EXTEND ) && ( funct3 == `INST_IFE ) ;
    wire is_sid_state   = ( state == S_SID_REQ ) || ( state == S_SID_WAIT ) ;
    wire is_ife_state   = ( state == S_IFE_REQ ) || ( state == S_IFE_WAIT ) ;
    

    // 外部强制 hold
    wire ext_hold = (jtag_halt_flag_i == `HoldEnable)
                 || (hold_flag_clint_i == `HoldEnable);

    // ========================================================================
    // 状态寄存器
    // ========================================================================
    always @(posedge clk) begin
        if (rst == `RstEnable) state <= S_IF_REQ;
        else                   state <= next_state;
    end

    // ========================================================================
    // 状态转移
    // ========================================================================
    always @(*) begin
        next_state = state;
        if (ext_hold) begin
            next_state = state;
        end else begin
            case (state)
                S_IF_REQ:     next_state = S_IF_WAIT;
                S_IF_WAIT:    if (if_ack_i == `RIB_ACK) next_state = S_LATCH_ID;
                S_LATCH_ID:   next_state = S_EX;
                S_EX: begin
                    if      (is_load_inst)    next_state = S_MEM_R_REQ;
                    else if (is_sw_inst)      next_state = S_MEM_W_REQ;
                    else if (is_sb_sh_inst)   next_state = S_MEM_R_REQ;  // 先读
                    else if (is_div_inst)     next_state = S_DIV_WAIT;
                    else if (is_rT_inst)      next_state = S_RT_R_REQ;
                    else if (is_sID_inst)     next_state = S_SID_REQ;
                    else if (is_ife_inst)     next_state = S_IFE_REQ;
                    else                      next_state = S_DONE;
                end
                S_MEM_R_REQ:  begin
                                  if (mem_no_ack_i) begin
                                      next_state = S_DONE;
                                  end 
                                  else begin
                                      next_state = S_MEM_R_WAIT;
                                  end
                              end
                S_MEM_R_WAIT: if (mem_ack_i == `RIB_ACK) begin
                                  if (is_sb_sh_inst) next_state = S_MEM_W_REQ;  // SB/SH读完后写
                                  else               next_state = S_DONE;       // Load完成
                              end
                S_MEM_W_REQ:  next_state = mem_no_ack_i ? S_DONE : S_MEM_W_WAIT;
                S_MEM_W_WAIT: if (mem_ack_i == `RIB_ACK) next_state = S_DONE;
                S_DIV_WAIT:   if (div_ready_i == `DivResultReady) next_state = S_DONE;
                S_RT_R_REQ:   next_state = S_RT_R_WAIT;
                S_RT_R_WAIT:  if (ext_inst_done == `EXT_INST_DONE) next_state = S_DONE;
                S_SID_REQ:    next_state = S_SID_WAIT;
                S_SID_WAIT:   if (ext_inst_done == `EXT_INST_DONE) next_state = S_DONE;
                S_IFE_REQ:    if (ife_use_uart) next_state = S_IFE_WAIT; else next_state = S_DONE ;
                S_IFE_WAIT:   if (ext_inst_done == `EXT_INST_DONE) next_state = S_DONE;
                S_DONE:       next_state = S_IF_REQ;
                default:      next_state = S_IF_REQ;
            endcase
        end
    end

    // ========================================================================
    // hold_flag 输出
    // ========================================================================
    always @(*) begin
        case (state)
            // 取指等待中：ack 那一拍切 Hold_Pc 让 IF/ID 锁存
            S_IF_WAIT:   hold_flag_o = (if_ack_i == `RIB_ACK) ? `Hold_Pc : `Hold_Id;
            S_LATCH_ID:  hold_flag_o = `Hold_If;
            S_DONE:      hold_flag_o = `Hold_None;
            default:     hold_flag_o = `Hold_Id;
        endcase

        if (ext_hold) hold_flag_o = `Hold_Id;
    end

    // ========================================================================
    // 跳转锁存
    // ========================================================================
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            jump_pending      <= 1'b0;
            jump_addr_latched <= `ZeroWord;
        end else if ((state == S_EX) && (jump_flag_i == `JumpEnable)) begin
            jump_pending      <= 1'b1;
            jump_addr_latched <= jump_addr_i;
        end else if (state == S_DONE) begin
            jump_pending      <= 1'b0;
            jump_addr_latched <= `ZeroWord;
        end
    end

    // ========================================================================
    // 跳转输出（含中断响应）
    // ========================================================================
    always @(*) begin
        if ((state == S_DONE) && (int_assert_i == `INT_ASSERT)) begin
            // 中断响应优先于普通跳转
            jump_flag_o = `JumpEnable;
            jump_addr_o = int_addr_i;
        end else if ((state == S_DONE) && jump_pending) begin
            jump_flag_o = `JumpEnable;
            jump_addr_o = jump_addr_latched;
        end else begin
            jump_flag_o = `JumpDisable;
            jump_addr_o = `ZeroWord;
        end
    end

    // ========================================================================
    // 各种门控信号
    // ========================================================================

    // 取指请求
    assign if_req_o = (state == S_IF_REQ) ; // 一周期的脉冲信号

    // 访存请求 (覆盖 ex.v 的 mem_req_o)
    assign mem_req_o = (state == S_MEM_R_REQ) || ( state == S_MEM_R_WAIT )
                        || (state == S_MEM_W_REQ) || ( state == S_MEM_W_WAIT ) 
                        || ( state == S_RT_R_REQ ) || ( state == S_RT_R_WAIT )
                        || ( (is_sid_state || is_ife_state) && ext_mem_req_i ) ;

    // 访存写使能 (FSM 直接控制，不依赖 ex.v 的 mem_we_o, 当出现拓展指令时，将控制权交给运算单元ex)
    assign mem_we_o = (state == S_MEM_W_REQ) 
                        || ( state == S_RT_R_REQ ) 
                        || ( (is_sid_state || is_ife_state) && ext_mem_we_i ) ;

    assign ext_inst_start_o = (( state == S_SID_REQ ) && is_sID_inst)
                           || (( state == S_IFE_REQ ) && is_ife_inst && ife_use_uart) ;

    // SB/SH 在写阶段使用之前锁存的 mem_rdata
    assign mem_rdata_use_latched_o = is_sb_sh_inst
                                  && ((state == S_MEM_W_REQ));

    // 寄存器写回门控
    //   - 普通指令：S_EX 拍写回
    //   - Load：    S_MEM_R_WAIT 的 ack 拍写回
    //   - Div：     S_DIV_WAIT 的 ready 拍写回
    //   - Store/Branch：ex.v 的 reg_we 本身就是 0
    assign reg_we_gate_o = ((state == S_EX) && !is_load_inst && !is_store_inst && !is_div_inst && !is_sID_inst && !is_rT_inst && !is_ife_inst)
                        || ((state == S_MEM_R_WAIT) && (mem_ack_i == `RIB_ACK) && is_load_inst)
                        || ((state == S_MEM_R_REQ)  && mem_no_ack_i && is_load_inst)
                        || ((state == S_DIV_WAIT)   && (div_ready_i == `DivResultReady))   
                        || ((state == S_RT_R_WAIT)  && (ext_inst_done == `EXT_INST_DONE) && is_rT_inst)
                        || ((state == S_IFE_REQ)    && !ife_use_uart && is_ife_inst)
                        || ((state == S_IFE_WAIT)   && (ext_inst_done == `EXT_INST_DONE) && is_ife_inst) ;

    // 除法启动门控
    assign div_start_gate_o = (state == S_EX) || (state == S_DIV_WAIT && div_busy_i);

    assign state_o = state;

endmodule
