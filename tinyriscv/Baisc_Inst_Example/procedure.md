流程

1. FPGA烧录
2. FPGA复位，此时succ = 1 ， over = 1 
3. FPGA解复位，UART的使能信号有效：①此时succ = 1， 意味着复位之后，将succ的数值为寄存器整体的取反值；②处理器中的UART_DEBUG模块一直处于WAIT2状态；③此后处理器一直处于IF_WAIT状态
4. 手动操作1（已经复位，且UART使能有效）：使用python程序下载程序，此后UART_DEBUG模块开始接收数据，并将数据写入至Bridge模块中，后至ROM中（直接重写ROM模块），此后应该一直停于FIRST_PACKET的WAIT2状态
5. 手动操作2：关闭UART_DEBUG的使能信号，CPU开始正常取指并执行指令