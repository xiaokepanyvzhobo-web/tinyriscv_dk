# 基于 "hold=保持" 语义的多周期处理器完整改造方案

## 设计总览

### 核心思想

将 `gen_pipe_dff` 的 hold 语义从原来的"清NOP"改为标准的"stall保持"，配合主状态机使整条指令完整执行后才取下一条。

### 优势对比

| 对比点 | 保持语义（本方案） | 清NOP语义 |
|--------|-----------------|-----------|
| 流水线寄存器内容 | 多周期等待中维持指令信息 | 每拍后变NOP，需各单元自维持 |
| ex.v 改动量 | **几乎不用改** | 需加 mem_busy 状态机 |
| Load 写回 | ex.v 组合逻辑天然正确 | 需要 ex.v 显式产生 mem_we_back |
| 概念清晰度 | hold = 标准stall（教科书） | hold = 插气泡（特殊） |
| **总工作量** | **小** | 中 |

### 改造文件清单

| 文件 | 改动类型 | 工作量 |
|------|---------|-------|
| `rtl/utils/gen_dff.v` | 改 1 行（语义反转） | 5 min |
| `rtl/core/ctrl_dk.v` | **新建** 主 FSM | 1-2 小时 |
| `rtl/core/tinyriscv.v` | 顶层连线 + 几个 mux | 30 min |
| `rtl/core/ex.v` | **基本不改**（仅 SB/SH 需小改） | 30 min |
| `rtl/core/pc_reg.v / if_id.v / id_ex.v / id.v / regs.v` | **完全不改** | 0 |

---

## Phase 1：修改 gen_pipe_dff（5 分钟）

### 改动

打开 `rtl/utils/gen_dff.v`，修改 `gen_pipe_dff` 模块：

```verilog
module gen_pipe_dff #(parameter DW = 32)(
    input wire clk,
    input wire rst,
    input wire hold_en,
    input wire [DW-1:0] def_val,
    input wire [DW-1:0] din,
    output wire [DW-1:0] qout
    );

    reg [DW-1:0] qout_r;

    always @ (posedge clk) begin
        if (!rst)              qout_r <= def_val;     // 复位为默认值
        else if (hold_en)      qout_r <= qout_r;      // ★ 改为保持
        else                   qout_r <= din;         // 否则正常更新
    end

    assign qout = qout_r;
endmodule
```

**只改了一行**：`qout_r <= def_val` → `qout_r <= qout_r`。

### 单元验证

写一个简单 testbench：

```verilog
// 验证：rst后置为def_val；hold_en=1时保持；hold_en=0时跟随din
initial begin
    clk = 0; rst = 0; hold_en = 0; din = 32'h12345678;
    #10 rst = 1;                    // 解除复位
    #10 din = 32'hAABBCCDD;          // qout应跟随
    #10 hold_en = 1; din = 32'hFFFF; // qout应保持AABBCCDD
    #20 hold_en = 0;                 // qout恢复跟随din
end
```

---

## Phase 2：设计 ctrl_dk.v 主 FSM

### 2.1 hold_flag 等级与寄存器行为对照表（保持语义下）

| hold_flag | PC | IF/ID | ID/EX | 含义 |
|-----------|----|----|----|----|
| Hold_None | 自增/跳转 | 锁存inst_i | 锁存译码 | 全前进 |
| Hold_Pc   | **保持** | 锁存inst_i | 锁存译码 | PC等待，其余前进 |
| Hold_If   | **保持** | **保持** | 锁存译码 | PC+IF/ID保持，仅ID/EX前进 |
| Hold_Id   | **保持** | **保持** | **保持** | 全保持 |

**关键观察**：保持语义下，`Hold_Id` 真正"冻结"指令在流水线中，多周期等待变得简单直接。

### 2.2 FSM 状态定义

```
S_IF_REQ      发起取指请求 (1拍)
S_IF_WAIT     等取指 ack (~13拍)
S_LATCH_ID    放行 ID/EX 锁存 (1拍)
S_EX          EX 输出稳定 / 普通指令写回 (1拍)
S_MEM_R_REQ   发起读请求 (Load 或 SB/SH 的读阶段)
S_MEM_R_WAIT  等读 ack
S_MEM_W_REQ   发起写请求 (SW/SB/SH 的写阶段)
S_MEM_W_WAIT  等写 ack
S_DIV_WAIT    等除法完成
S_DONE        放行 PC 前进 (1拍)
```

### 2.3 状态转移图

```
                     ┌──────────┐
                     │S_IF_REQ  │
                     └────┬─────┘
                          v
                     ┌──────────┐  if_ack
                     │S_IF_WAIT │─────────┐
                     └────┬─────┘         │
                          │ if_ack ──────>│ (同拍切 hold=Hold_Pc, 锁存IF/ID)
                          v
                     ┌────────────┐
                     │S_LATCH_ID  │ (hold=Hold_If, 锁存ID/EX)
                     └─────┬──────┘
                           v
                     ┌────────────┐
                     │S_EX        │ (hold=Hold_Id, 普通指令此拍写回)
                     └─────┬──────┘
              ┌────────────┼─────────────┬─────────┬──────────┐
              v            v             v         v          v
        ┌──────────┐ ┌─────────┐  ┌──────────┐ ┌────────┐ ┌──────┐
        │S_MEM_R_  │ │SW: S_   │  │SB/SH: S_ │ │S_DIV_  │ │normal│
        │REQ (LW)  │ │MEM_W_REQ│  │MEM_R_REQ │ │WAIT    │ │      │
        └─────┬────┘ └────┬────┘  └────┬─────┘ └───┬────┘ └──┬───┘
              v           v            v           v         │
        ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
        │S_MEM_R_  │ │S_MEM_W_  │ │S_MEM_R_  │ │ack       │  │
        │WAIT(Load)│ │WAIT(SW)  │ │WAIT(SB)  │ │div_ready │  │
        └──┬───────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘  │
           │ ack          │ ack        │ ack         v        │
           │              │            v          (Load写回)  │
           │              │      ┌──────────┐                 │
           │              │      │S_MEM_W_  │                 │
           │              │      │REQ(SB)   │                 │
           │              │      └────┬─────┘                 │
           │              │           v                       │
           │              │      ┌──────────┐                 │
           │              │      │S_MEM_W_  │                 │
           │              │      │WAIT(SB)  │                 │
           │              │      └────┬─────┘                 │
           │              │           │ ack                   │
           v              v           v                       v
                     ┌────────────────────────────────┐
                     │           S_DONE                │ (hold=Hold_None, PC前进)
                     └────────────────┬───────────────┘
                                      └──> S_IF_REQ
```

### 2.4 完整 ctrl_dk.v 代码

```verilog
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
    input wire hold_flag_ex_i,            // 兼容保留

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
    localparam S_DONE        = 4'd9;

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
                    else                      next_state = S_DONE;
                end
                S_MEM_R_REQ:  next_state = S_MEM_R_WAIT;
                S_MEM_R_WAIT: if (mem_ack_i == `RIB_ACK) begin
                                  if (is_sb_sh_inst) next_state = S_MEM_W_REQ;  // SB/SH读完后写
                                  else               next_state = S_DONE;       // Load完成
                              end
                S_MEM_W_REQ:  next_state = S_MEM_W_WAIT;
                S_MEM_W_WAIT: if (mem_ack_i == `RIB_ACK) next_state = S_DONE;
                S_DIV_WAIT:   if (div_ready_i == `DivResultReady) next_state = S_DONE;
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
    assign mem_req_o = (state == S_MEM_R_REQ) || (state == S_MEM_R_WAIT)
                    || (state == S_MEM_W_REQ) || (state == S_MEM_W_WAIT);

    // 访存写使能 (FSM 直接控制，不依赖 ex.v 的 mem_we_o)
    assign mem_we_o = (state == S_MEM_W_REQ) || (state == S_MEM_W_WAIT);

    // SB/SH 在写阶段使用之前锁存的 mem_rdata
    assign mem_rdata_use_latched_o = is_sb_sh_inst
                                  && ((state == S_MEM_W_REQ) || (state == S_MEM_W_WAIT));

    // 寄存器写回门控
    //   - 普通指令：S_EX 拍写回
    //   - Load：    S_MEM_R_WAIT 的 ack 拍写回
    //   - Div：     S_DIV_WAIT 的 ready 拍写回
    //   - Store/Branch：ex.v 的 reg_we 本身就是 0
    assign reg_we_gate_o = ((state == S_EX) && !is_load_inst && !is_store_inst && !is_div_inst)
                        || ((state == S_MEM_R_WAIT) && (mem_ack_i == `RIB_ACK) && is_load_inst)
                        || ((state == S_DIV_WAIT)   && (div_ready_i == `DivResultReady));

    // 除法启动门控
    assign div_start_gate_o = (state == S_EX) || (state == S_DIV_WAIT);

    assign state_o = state;

endmodule
```

---

## Phase 3：修改 tinyriscv.v 顶层连线

### 3.1 替换 ctrl 例化

```verilog
// 原: ctrl u_ctrl(...);
// 改为:
ctrl_dk u_ctrl_dk(
    .clk             (clk),
    .rst             (rst),
    .inst_at_ex_i    (id_ex_inst_o),       // ID/EX 的 inst_o
    .jump_flag_i     (ex_jump_flag_o),
    .jump_addr_i     (ex_jump_addr_o),
    .hold_flag_ex_i  (ex_hold_flag_o),
    .hold_flag_rib_i (rib_hold_flag_o),
    .if_ack_i        (bridge_if_ack),       // 来自桥接
    .mem_ack_i       (bridge_mem_ack),      // 来自桥接
    .div_busy_i      (div_busy),
    .div_ready_i     (div_ready),
    .jtag_halt_flag_i(jtag_halt_flag),
    .hold_flag_clint_i(clint_hold_flag),
    .int_assert_i    (clint_int_assert),
    .int_addr_i      (clint_int_addr),
    .hold_flag_o     (ctrl_hold_flag),
    .jump_flag_o     (ctrl_jump_flag),
    .jump_addr_o     (ctrl_jump_addr),
    .if_req_o        (bridge_if_req),
    .mem_req_o       (bridge_mem_req),
    .mem_we_o        (bridge_mem_we),
    .reg_we_gate_o   (reg_we_gate),
    .div_start_gate_o(div_start_gate),
    .mem_rdata_use_latched_o(mem_use_latched),
    .state_o         ()  // open
);
```

### 3.2 添加 mem_rdata 旁路（用于 SB/SH 读-改-写）

```verilog
// 锁存读阶段返回的 mem_rdata，供写阶段使用
reg [31:0] mem_rdata_latched;
always @(posedge clk) begin
    if (rst == `RstEnable) begin
        mem_rdata_latched <= 32'h0;
    end else if (u_ctrl_dk.state == 5 /* S_MEM_R_WAIT */ && bridge_mem_ack) begin
        mem_rdata_latched <= bridge_mem_rdata;
    end
end

// 喂给 ex.v 的 mem_rdata：旁路选择
wire [31:0] ex_mem_rdata_in = mem_use_latched ? mem_rdata_latched : bridge_mem_rdata;

// 在 ex 实例化时把 mem_rdata_i 改为这个 ex_mem_rdata_in
ex u_ex(
    ...
    .mem_rdata_i (ex_mem_rdata_in),  // 改为旁路输出
    ...
);
```

### 3.3 各种 AND 门

```verilog
// reg_we 门控
wire final_reg_we = ex_reg_we_o & reg_we_gate;

// div_start 门控
wire final_div_start = ex_div_start_o & div_start_gate;

// 把 final_reg_we 和 final_div_start 连接到下游
regs u_regs(
    ...
    .we_i (final_reg_we),
    ...
);
div u_div(
    ...
    .start_i (final_div_start),
    ...
);
```

### 3.4 桥接连接

ex.v 的 `mem_req_o`、`mem_we_o` 不再直接连桥接，而是用 ctrl_dk 的输出：

```verilog
// 桥接的写数据始终用 ex.v 的输出（因为保持语义下 ex 的 mem_wdata 是稳定的）
assign bridge_mem_wdata = ex_mem_wdata_o;
assign bridge_mem_addr  = is_load ? ex_mem_raddr_o : ex_mem_waddr_o;  // 视实际而定
```

---

## Phase 4：ex.v 几乎不用改

由于保持语义下 ID/EX 维持指令信息，ex.v 的组合逻辑天然在多周期下正确。**唯一需要注意的**：

### 4.1 移除 ex.v 内部对 div 的"自维持"逻辑（可选）

原 ex.v 中（行 222-244）：
```verilog
end else begin   // ID/EX 被清NOP后的分支
    if (div_busy_i == True) begin
        div_start = DivStart;
        div_hold_flag = HoldEnable;
    end else begin ... end
end
```

保持语义下，ID/EX 不会变成 NOP，永远命中第一个 if 分支。这部分 else 代码逻辑上不会执行，可保留也可删除。**建议保留**，作为防御性代码。

### 4.2 SB/SH 的处理（无需改 ex.v）

ex.v 的 SB/SH 代码继续用 `mem_rdata_i` 计算 `mem_wdata_o`。但 `mem_rdata_i` 在写阶段由顶层的 `ex_mem_rdata_in` 旁路提供（用 `mem_rdata_latched`）。所以 ex.v 内部代码不动，只是顶层连线变化。

### 4.3 关键的中断处理调整

ex.v 第 153/157/160 行有 `int_assert_i` 抑制写回的逻辑：
```verilog
assign reg_we_o = (int_assert_i == `INT_ASSERT) ? `WriteDisable : (reg_we || div_we);
assign mem_we_o = (int_assert_i == `INT_ASSERT) ? `WriteDisable : mem_we;
```

由于中断响应改为在 S_DONE 拍由 FSM 处理，这些逻辑可以保留作为双重保险，**无需改动**。

---

## Phase 5：跳转、中断、CSR、FENCE 处理

### 5.1 跳转（JAL/JALR/Branch）

- ex.v 的 `jump_flag` 在 S_EX 拍组合输出
- ctrl_dk 在 S_EX 拍锁存到 `jump_pending` 和 `jump_addr_latched`
- S_DONE 拍输出给 pc_reg
- pc_reg 在 S_DONE 末态更新 PC

**完全复用现有逻辑，无需任何修改**。

### 5.2 中断响应

中断只在指令边界（S_DONE）响应：
```verilog
if ((state == S_DONE) && (int_assert_i == `INT_ASSERT)) begin
    jump_flag_o = `JumpEnable;
    jump_addr_o = int_addr_i;     // CLINT 提供向量
end
```

CLINT 模块自身的状态机会处理 mepc 更新等细节，CPU 只需在指令边界跳转。

### 5.3 CSR 指令

CSR 指令属于"普通指令"路径：S_EX 拍 ex.v 组合输出 csr_wdata 和 reg_wdata。csr_reg.v 在 S_EX 末态写入。**无需特殊处理**。

> 注：csr_reg.v 的 `we_i` 也建议过 reg_we_gate 门控，避免误写。或在顶层加一个 `csr_we_gate = (state == S_EX)`。

### 5.4 FENCE 指令

FENCE 在 ex.v 中通过 `jump_flag=1` 跳到 PC+4 实现刷新。在多周期模型下：
- S_EX 拍 ex.v 输出 jump_flag=1, jump_addr=PC+4
- jump_pending 锁存
- S_DONE 拍 PC 跳到 PC+4（等价于不跳转）

**无需任何修改**。

---

## Phase 6：分阶段验证（核心）

### 阶段 A：骨架验证（1拍取指假设）

**目标**：FSM 跑起来，PC 行为正确。

1. **改 gen_pipe_dff** 为保持语义。
2. **新建 ctrl_dk.v**，但暂时把 `if_ack_i` 直接接 `1'b1`（假设1拍取指）。
3. **改顶层**最少必要连线，跑最简单的指令测试：
   ```
   cd sim
   python sim_new_nowave.py ../tests/isa/generated/rv32ui-p-add.bin inst.data
   ```
4. **预期**：每条指令约 4-5 拍（S_IF_REQ → S_IF_WAIT → S_LATCH_ID → S_EX → S_DONE）

**验证点**：
- 波形看 PC 是否每条指令完成一次才 +4
- state 序列是否符合预期
- 寄存器值是否正确

**调试技巧**：在 testbench 里 dump regs：
```verilog
always @(posedge clk) begin
    if (u_tinyriscv.u_ctrl_dk.state == 9 /*S_DONE*/) begin
        $display("[%t] PC=%h INST=%h x[%d]=%h",
                 $time, u_pc_reg.pc_o, u_id_ex.inst_o,
                 u_regs.we_addr_i, u_regs.we_data_i);
    end
end
```

### 阶段 B：接入 13 拍桥接取指

1. **接入 `if_ack_i`** 为真实桥接 ack 信号。
2. **跑最简单的 ADDI/ADD 测试**。
3. **预期**：每条指令约 16-17 拍。

**验证点**：
- 波形看 13 拍延迟是否正确
- 取指请求 `if_req_o` 是否在 ack 后及时撤销
- IF/ID 是否在正确拍锁存到正确指令

**常见 bug**：
- 桥接的 ack 是脉冲还是电平？如果是脉冲（仅1拍），FSM 必须在该拍正确切换 hold_flag
- inst_i 在 ack 后是否还稳定？关系到 IF/ID 锁存正确性

**单步指令测试**：先跑 `rv32ui-p-add`，然后扩展到 `rv32ui-p-addi`、`rv32ui-p-and`、`rv32ui-p-or`、`rv32ui-p-xor`、`rv32ui-p-sll/srl/sra` 等。

```bash
# 在 sim 目录下
python sim_new_nowave.py ../tests/isa/generated/rv32ui-p-add.bin   inst.data
python sim_new_nowave.py ../tests/isa/generated/rv32ui-p-addi.bin  inst.data
python sim_new_nowave.py ../tests/isa/generated/rv32ui-p-and.bin   inst.data
# ... 等
```

### 阶段 C：分支与跳转

跑：
- `rv32ui-p-beq.bin`、`rv32ui-p-bne.bin`、`rv32ui-p-blt.bin`、`rv32ui-p-bge.bin`、`rv32ui-p-bltu.bin`、`rv32ui-p-bgeu.bin`
- `rv32ui-p-jal.bin`、`rv32ui-p-jalr.bin`

**验证点**：
- jump_pending 是否在 S_EX 正确锁存
- S_DONE 拍 PC 是否跳到正确地址
- BEQ 不跳的情况下 PC 正确 +4

**易错点**：jump_addr_latched 必须在 S_EX 那一拍锁存。如果在 S_DONE 拍才采样 ex 的 jump_addr，此时 ID/EX 可能已经变化（虽然保持语义下不变）。**实际上由于保持语义，ID/EX 在 S_DONE 拍仍是当前指令，但保险起见还是显式在 S_EX 锁存**。

### 阶段 D：Load 指令（接入多周期访存）

1. 接入 `mem_ack_i` 为真实桥接 ack。
2. 跑：`rv32ui-p-lw.bin`、`rv32ui-p-lh.bin`、`rv32ui-p-lhu.bin`、`rv32ui-p-lb.bin`、`rv32ui-p-lbu.bin`

**验证点**：
- S_MEM_R_REQ 拍是否正确发出 mem_req
- ack 拍是否正确写入 rd（reg_we_gate=1）
- 符号扩展、零扩展、字节偏移选择是否正确（这些都由 ex.v 处理，应该天然正确）

**关键检查**：在 ack 拍：
- ID/EX 仍是 Load 指令（保持语义下应该如此）
- ex.v 的 `reg_wdata` 输出 = 正确的 load 结果
- ex.v 的 `reg_we_o` = 1
- `reg_we_gate` = 1
- regs.v 的 `we_i` = 1，写入正确

### 阶段 E：SW 指令

跑：`rv32ui-p-sw.bin`

**验证点**：
- S_MEM_W_REQ 发起写
- mem_we_o（来自 ctrl_dk）= 1
- ex.v 的 mem_wdata 是 reg2_rdata 全字
- ack 后 S_DONE，PC 前进

### 阶段 F：SB/SH 指令（最容易出问题）

跑：`rv32ui-p-sb.bin`、`rv32ui-p-sh.bin`

这是最复杂的一步。**严格按以下时序验证**：

```
拍N:   S_MEM_R_REQ   发出读请求 (mem_we_o=0, mem_rdata 流向 ex.v 是 bridge.mem_rdata)
拍N+1: S_MEM_R_WAIT  等待...
拍N+M: S_MEM_R_WAIT  ack=1, 顶层锁存 mem_rdata_latched <= bridge.mem_rdata
拍N+M+1: S_MEM_W_REQ
  - mem_use_latched=1, ex.v 看到的 mem_rdata_i = mem_rdata_latched
  - ex.v 的 mem_wdata_o 用 mem_rdata_latched 和 reg2_rdata 拼出正确写入数据
  - mem_we_o(从ctrl_dk)=1, 发出写请求
拍N+M+2 ... S_MEM_W_WAIT 等待
拍...: ack, S_DONE
```

**典型 bug**：
- mem_rdata_latched 锁存时机错（应该在 S_MEM_R_WAIT 的 ack 拍）
- mem_use_latched 的状态判断错（写阶段才用 latched）
- ex.v 看到的 mem_rdata_i 在两个阶段切换时有 glitch

可写一个专门 testbench 单步验证：
```verilog
// 在 SB 指令处单步
initial begin
    wait(u_tinyriscv.u_ctrl_dk.state == S_MEM_R_REQ);
    $display("MEM_R_REQ: addr=%h", bridge_mem_addr);
    wait(u_tinyriscv.u_ctrl_dk.state == S_MEM_W_REQ);
    $display("MEM_W_REQ: addr=%h, wdata=%h, latched=%h",
             bridge_mem_addr, bridge_mem_wdata, mem_rdata_latched);
end
```

### 阶段 G：除法

跑：`rv32um-p-mul.bin`、`rv32um-p-mulh.bin`、`rv32um-p-mulhu.bin`、`rv32um-p-mulhsu.bin`、`rv32um-p-div.bin`、`rv32um-p-divu.bin`、`rv32um-p-rem.bin`、`rv32um-p-remu.bin`

**乘法**：单拍组合，跟普通指令一样走 S_EX → S_DONE。

**除法**：S_EX 启动 div，进入 S_DIV_WAIT，等 div_ready，写回 → S_DONE。

**验证点**：
- div_start_gate 在 S_EX 和 S_DIV_WAIT 都是 1，确保 div_start 持续有效
- div_ready 拍 reg_we_gate=1，div_we 通过 ex.v 输出 reg_we_o=1，写入

### 阶段 H：CSR 指令

跑：`rv32ui-p-csr.bin`（如果测试集中有）。或写一个简单 C 程序测试 CSR。

### 阶段 I：完整回归

```bash
cd sim
python test_all_isa.py
```

如果所有 isa 测试都过，再跑：
```bash
cd sim/compliance_test
python compliance_test_all.py   # 如果有这个脚本，否则逐个跑
```

### 阶段 J：C 程序

```bash
cd tests/example/simple
make
cd ../../../sim
python sim_new_nowave.py ../tests/example/simple/simple.bin inst.data
```

### 阶段 K：中断测试

跑 timer 中断的 C 程序例程（可能在 tests/example/ 下）。

---

## Phase 7：调试技巧与常见问题

### 7.1 必看波形信号

| 信号 | 用途 |
|------|------|
| `u_ctrl_dk.state[3:0]` | FSM 状态 |
| `u_ctrl_dk.hold_flag_o` | hold 等级 |
| `u_pc_reg.pc_o` | 当前 PC |
| `u_if_id.inst_o` | IF/ID 中的指令 |
| `u_id_ex.inst_o` | ID/EX 中的指令（关键！） |
| `bridge_if_req`, `bridge_if_ack` | 取指握手 |
| `bridge_mem_req`, `bridge_mem_ack`, `bridge_mem_we` | 访存握手 |
| `u_ex.reg_we_o`, `reg_we_gate`, `final_reg_we` | 写回链路 |
| `u_ctrl_dk.jump_pending` | 跳转锁存 |

### 7.2 Golden 模型对比

每条指令完成后 dump：
```
PC=xxxxxxxx INST=xxxxxxxx [WB: x[r]=xxxxxxxx]  [MEM_W: addr=xx data=xx]
```

与 spike 的 commit log 对比。spike 命令：
```bash
spike --isa=rv32im --log=spike.log -l ./test.elf
```

### 7.3 常见问题排查

| 现象 | 可能原因 |
|------|---------|
| PC 卡死不动 | FSM 卡在某状态，看 ack 信号是否正确返回 |
| Load 写回值错误 | reg_we_gate 时机不对，或 mem_rdata 旁路 mux 错 |
| Store 后 Load 同地址值不对 | SB/SH 的 RMW 时序错 |
| BEQ 总跳转或总不跳 | jump_pending 没在 S_EX 锁存 |
| 第一条指令就错 | 复位后 PC 是否正确为 CpuResetAddr，FSM 是否正确从 S_IF_REQ 启动 |
| 多条指令后才出错 | regs 文件被错误写入了垃圾值，重点查 reg_we_gate |
| 中断响应错误 | 检查 int_assert_i 时序与 S_DONE 拍的对齐 |

### 7.4 性能验证

理论 CPI（设取指 13 拍，访存 N 拍，假设 N=10）：
- 普通指令：13 + 1(LATCH_ID) + 1(EX) + 1(DONE) = 16 拍
- Load：16 + 2(MEM_R) + 10(WAIT) = 28 拍
- SW：16 + 2 + 10 = 28 拍
- SB/SH：16 + 2 + 10 + 2 + 10 = 40 拍
- Div：16 + 33 = 49 拍

跑 CoreMark 后用 cycle CSR 验证。

---

## 附录：完整改造检查清单

### 文件清单

- [ ] `rtl/utils/gen_dff.v` 修改 1 行
- [ ] `rtl/core/ctrl_dk.v` 新建（参考 Phase 2）
- [ ] `rtl/core/tinyriscv.v` 顶层连线（参考 Phase 3）
- [ ] `rtl/tinyriscv.f` 添加 ctrl_dk.v 到文件列表

### 信号检查清单

- [ ] `if_ack_i`、`mem_ack_i` 来自桥接，时序确定
- [ ] `mem_rdata_latched` 在 SB/SH 读阶段 ack 拍正确锁存
- [ ] `reg_we_gate` 仅在指令结果有效拍为 1
- [ ] `mem_we_o` 来自 ctrl_dk 而非 ex.v
- [ ] ex.v 的 `mem_rdata_i` 通过旁路 mux

### 验证里程碑

- [ ] 阶段 A：rv32ui-p-add 通过（1拍取指）
- [ ] 阶段 B：rv32ui-p-add 通过（13拍取指）
- [ ] 阶段 C：所有分支跳转测试通过
- [ ] 阶段 D：所有 Load 测试通过
- [ ] 阶段 E：SW 通过
- [ ] 阶段 F：SB/SH 通过
- [ ] 阶段 G：所有 RV32M 测试通过
- [ ] 阶段 H：CSR 测试通过
- [ ] 阶段 I：`test_all_isa.py` 全过
- [ ] 阶段 J：C 程序 simple 跑通
- [ ] 阶段 K：中断测试通过

按这个方案稳步推进，每个阶段过了再做下一个，可以保证最终跑通整个 RV32IM 指令测试集。
