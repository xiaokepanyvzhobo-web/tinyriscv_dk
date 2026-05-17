# inst_div.data 解析

## 文件来源和格式

- 数据文件：`Baisc_Inst_Example/inst_div.data`
- 参考反汇编：`tests/isa/generated/rv32um-p-div.dump`
- 指令集目标：RV32IM
- 核心测试指令：`div`
- `.data` 行数：98 行，每行是 1 条 32-bit 指令或 padding 数据，按 ROM word 顺序加载。

这个文件是 `rv32um-p-div` 的机器码形式，用来测试 RISC-V M 扩展里的有符号除法指令：

```asm
div rd, rs1, rs2
```

RISC-V `div` 的语义是有符号整数除法，结果向 0 截断。除数为 0 时，商返回 `-1`，即 `0xffffffff`。

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

## 完整汇编流程

### 初始化

```asm
00000000 <_start>:
   0: 00000d13    li s10,0
   4: 00000d93    li s11,0
```

### test_2：正数除正数

```asm
00000008 <test_2>:
   8: 01400093    li  ra,20
   c: 00600113    li  sp,6
  10: 0220cf33    div t5,ra,sp
  14: 00300e93    li  t4,3
  18: 00200193    li  gp,2
  1c: 0ddf1463    bne t5,t4,fail
```

功能：验证 `20 / 6 = 3`，余数被丢弃，结果向 0 截断。

### test_3：负数除正数

```asm
00000020 <test_3>:
  20: fec00093    li  ra,-20
  24: 00600113    li  sp,6
  28: 0220cf33    div t5,ra,sp
  2c: ffd00e93    li  t4,-3
  30: 00300193    li  gp,3
  34: 0bdf1863    bne t5,t4,fail
```

功能：验证 `-20 / 6 = -3`。

### test_4：正数除负数

```asm
00000038 <test_4>:
  38: 01400093    li  ra,20
  3c: ffa00113    li  sp,-6
  40: 0220cf33    div t5,ra,sp
  44: ffd00e93    li  t4,-3
  48: 00400193    li  gp,4
  4c: 09df1c63    bne t5,t4,fail
```

功能：验证 `20 / -6 = -3`。

### test_5：负数除负数

```asm
00000050 <test_5>:
  50: fec00093    li  ra,-20
  54: ffa00113    li  sp,-6
  58: 0220cf33    div t5,ra,sp
  5c: 00300e93    li  t4,3
  60: 00500193    li  gp,5
  64: 09df1063    bne t5,t4,fail
```

功能：验证 `-20 / -6 = 3`。

### test_6：0 除正数

```asm
00000068 <test_6>:
  68: 00000093    li  ra,0
  6c: 00100113    li  sp,1
  70: 0220cf33    div t5,ra,sp
  74: 00000e93    li  t4,0
  78: 00600193    li  gp,6
  7c: 07df1463    bne t5,t4,fail
```

功能：验证 `0 / 1 = 0`。

### test_7：0 除负数

```asm
00000080 <test_7>:
  80: 00000093    li  ra,0
  84: fff00113    li  sp,-1
  88: 0220cf33    div t5,ra,sp
  8c: 00000e93    li  t4,0
  90: 00700193    li  gp,7
  94: 05df1863    bne t5,t4,fail
```

功能：验证 `0 / -1 = 0`。

### test_8：0 除 0

```asm
00000098 <test_8>:
  98: 00000093    li  ra,0
  9c: 00000113    li  sp,0
  a0: 0220cf33    div t5,ra,sp
  a4: fff00e93    li  t4,-1
  a8: 00800193    li  gp,8
  ac: 03df1c63    bne t5,t4,fail
```

功能：验证除数为 0 时，RISC-V 规定 `div` 返回 `-1`。

### test_9：正数除 0

```asm
000000b0 <test_9>:
  b0: 00100093    li  ra,1
  b4: 00000113    li  sp,0
  b8: 0220cf33    div t5,ra,sp
  bc: fff00e93    li  t4,-1
  c0: 00900193    li  gp,9
  c4: 03df1063    bne t5,t4,fail
```

功能：验证 `1 / 0` 返回 `-1`。

### test_10：再次验证 0 除 0

```asm
000000c8 <test_10>:
  c8: 00000093    li  ra,0
  cc: 00000113    li  sp,0
  d0: 0220cf33    div t5,ra,sp
  d4: fff00e93    li  t4,-1
  d8: 00a00193    li  gp,10
  dc: 01df1463    bne t5,t4,fail
  e0: 00301863    bne zero,gp,pass
```

功能：再次确认除数为 0 的返回值，并在全部测试通过后跳转到 `pass`。

### fail/pass 结束逻辑

```asm
000000e4 <fail>:
  e4: 00100d13    li s10,1
  e8: 00000d93    li s11,0

000000ec <loop_fail>:
  ec: 0000006f    j loop_fail

000000f0 <pass>:
  f0: 00100d13    li s10,1
  f4: 00100d93    li s11,1

000000f8 <loop_pass>:
  f8: 0000006f    j loop_pass
```

## 测试点汇总

| 测试 | 表达式 | 期望结果 | 说明 |
| --- | --- | --- | --- |
| test_2 | `20 / 6` | `3` | 正数除正数，向 0 截断 |
| test_3 | `-20 / 6` | `-3` | 负数除正数 |
| test_4 | `20 / -6` | `-3` | 正数除负数 |
| test_5 | `-20 / -6` | `3` | 负数除负数 |
| test_6 | `0 / 1` | `0` | 被除数为 0 |
| test_7 | `0 / -1` | `0` | 被除数为 0，除数为负数 |
| test_8 | `0 / 0` | `-1` | 除数为 0 |
| test_9 | `1 / 0` | `-1` | 除数为 0 |
| test_10 | `0 / 0` | `-1` | 除数为 0，结束前重复确认 |

## 完成的功能

`inst_div.data` 用于验证 CPU 的 RV32M `DIV` 指令实现是否正确，覆盖：

- 有符号除法；
- 正负号组合；
- 结果向 0 截断；
- 被除数为 0；
- 除数为 0 时返回 `0xffffffff`；
- pass/fail 跳转和结束标志写入。

全部测试通过后，程序停在 `loop_pass`，程序内部 `x26/s10 = 1`、`x27/s11 = 1`。
