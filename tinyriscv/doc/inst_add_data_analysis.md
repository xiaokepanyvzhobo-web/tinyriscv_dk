# inst_add.data 解析

## 文件来源和格式

- 数据文件：`Baisc_Inst_Example/inst_add.data`
- 参考反汇编：`tests/isa/generated/rv32ui-p-add.dump`
- 指令集目标：RV32I
- 核心测试指令：`add`
- `.data` 行数：223 行，每行是 1 条 32-bit 指令或 padding 数据，按 ROM word 顺序加载。

这个文件是 `rv32ui-p-add` 的机器码形式。程序启动后先清零 `x26/s10` 和 `x27/s11`，随后逐个执行 ADD 测试点。任一测试失败会跳到 `fail`；全部通过后跳到 `pass`。

## 结果寄存器约定

程序本身的 pass/fail 标志如下：

```asm
fail:
    li s10, 1     # x26 = 1, 表示程序结束
    li s11, 0     # x27 = 0, 表示失败
    j loop_fail

pass:
    li s10, 1     # x26 = 1, 表示程序结束
    li s11, 1     # x27 = 1, 表示成功
    j loop_pass
```

如果顶层 RTL 对 `x26/x27` 做了取反输出，那么外部 `over/succ` 的有效语义会和程序内寄存器值相反。

## 汇编结构

### 初始化

```asm
00000000 <_start>:
   0: 00000d13    li s10,0
   4: 00000d93    li s11,0
```

### 普通数值和边界值测试

这些测试检查 `add rd, rs1, rs2` 在 32-bit 补码加法下的结果，包括正数、负数、最高位、溢出回绕等情况。

| 测试 | 汇编核心 | 期望结果 | 功能 |
| --- | --- | --- | --- |
| test_2 | `0 + 0` | `0` | 零加零 |
| test_3 | `1 + 1` | `2` | 小正数相加 |
| test_4 | `3 + 7` | `10` | 普通正数相加 |
| test_5 | `0 + 0xffff8000` | `0xffff8000` | 负边界立即数组合 |
| test_6 | `0x80000000 + 0` | `0x80000000` | 最高位符号位保持 |
| test_7 | `0x80000000 + 0xffff8000` | `0x7fff8000` | 32-bit 回绕 |
| test_8 | `0 + 0x00007fff` | `0x00007fff` | 正边界立即数 |
| test_9 | `0x7fffffff + 0` | `0x7fffffff` | 最大正数 |
| test_10 | `0x7fffffff + 0x7fff` | `0x80007ffe` | 正溢出回绕 |
| test_11 | `0x80000000 + 0x7fff` | `0x80007fff` | 负数加正数 |
| test_12 | `0x7fffffff + 0xffff8000` | `0x7fff7fff` | 正数加负数 |
| test_13 | `0 + (-1)` | `0xffffffff` | 加 -1 |
| test_14 | `-1 + 1` | `0` | 负数抵消 |
| test_15 | `-1 + -1` | `0xfffffffe` | 负数相加 |
| test_16 | `1 + 0x7fffffff` | `0x80000000` | 最大正数加 1 |

典型汇编形式如下：

```asm
test_3:
    li      ra,1
    li      sp,1
    add     t5,ra,sp
    li      t4,2
    li      gp,3
    bne     t5,t4,fail
```

### 目标寄存器重叠测试

这些测试检查 `rd` 与 `rs1/rs2` 重叠时，写回结果是否正确。

| 测试 | 汇编核心 | 期望结果 | 功能 |
| --- | --- | --- | --- |
| test_17 | `add ra, ra, sp`，`13 + 11` | `24` | `rd == rs1` |
| test_18 | `add sp, ra, sp`，`14 + 11` | `25` | `rd == rs2` |
| test_19 | `add ra, ra, ra`，`13 + 13` | `26` | `rd == rs1 == rs2` |

```asm
test_17:
    li      ra,13
    li      sp,11
    add     ra,ra,sp
    li      t4,24
    li      gp,17
    bne     ra,t4,fail
```

### 数据相关和旁路/暂停测试

`test_20` 到 `test_34` 主要检查 ADD 指令结果在后续指令中被立即使用时是否正确，覆盖 0、1、2 个 `nop` 间隔，以及源操作数生成和消费的相对位置。

| 测试范围 | 典型模式 | 功能 |
| --- | --- | --- |
| test_20 到 test_22 | `add t5,ra,sp` 后紧跟/间隔 `nop` 后 `mv t1,t5` | 检查 ADD 写回结果被后续指令读取 |
| test_23 到 test_25 | 循环内执行 `add t5,ra,sp`，循环后比较 `t5` | 检查跨分支循环后的结果保持 |
| test_26 到 test_34 | 在 `rs1/rs2` 写入和 `add` 之间插入不同数量 `nop` | 检查源寄存器数据相关和流水线时序 |

典型 0 间隔数据相关：

```asm
test_20:
    li      tp,0
1:
    li      ra,13
    li      sp,11
    add     t5,ra,sp
    mv      t1,t5
    addi    tp,tp,1
    li      t0,2
    bne     tp,t0,1b
    li      t4,24
    li      gp,20
    bne     t1,t4,fail
```

带 `nop` 的数据相关：

```asm
test_22:
    li      tp,0
1:
    li      ra,15
    li      sp,11
    add     t5,ra,sp
    nop
    nop
    mv      t1,t5
    addi    tp,tp,1
    li      t0,2
    bne     tp,t0,1b
    li      t4,26
    li      gp,22
    bne     t1,t4,fail
```

### x0 寄存器测试

最后几组检查 `x0/zero` 的特殊行为。

| 测试 | 汇编核心 | 期望结果 | 功能 |
| --- | --- | --- | --- |
| test_35 | `add sp, zero, ra` | `sp = ra = 15` | `rs1 == x0` |
| test_36 | `add sp, ra, zero` | `sp = ra = 32` | `rs2 == x0` |
| test_37 | `add ra, zero, zero` | `ra = 0` | 两个源都是 x0 |
| test_38 | `add zero, ra, sp` | `zero` 仍为 `0` | 写 x0 必须无效 |

```asm
test_38:
    li      ra,16
    li      sp,30
    add     zero,ra,sp
    li      t4,0
    li      gp,38
    bne     zero,t4,fail
    bne     zero,gp,pass
```

## 完成的功能

`inst_add.data` 用于验证 CPU 的 RV32I `ADD` 指令实现是否正确，覆盖：

- 32-bit 补码加法；
- 正数、负数、零、边界值；
- 加法溢出后的低 32-bit 回绕；
- `rd` 与 `rs1/rs2` 重叠；
- 与后续指令的数据相关；
- `x0` 作为源寄存器和目标寄存器时的特殊行为。

全部测试通过后，程序停在 `loop_pass`，程序内部 `x26/s10 = 1`、`x27/s11 = 1`。
