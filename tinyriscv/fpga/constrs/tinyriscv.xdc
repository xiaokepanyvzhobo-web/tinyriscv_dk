# 鏃堕挓绾︽潫50MHz
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {clk}]; 
create_clock -add -name sys_clk_pin -period 20.00 -waveform {0 10} [get_ports {clk}];

# 鏃堕挓寮曡剼
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN Y18 [get_ports clk]

# 澶嶄綅寮曡剼
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property PACKAGE_PIN F20 [get_ports rst]

# 绋嬪簭鎵ц鎴愬姛鎸囩ず寮曡剼
set_property IOSTANDARD LVCMOS33 [get_ports succ]
set_property PACKAGE_PIN F19 [get_ports succ]

# 涓插彛鍙戦?佸紩鑴?
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]
set_property PACKAGE_PIN G16 [get_ports uart_tx_pin]

# 涓插彛鎺ユ敹寮曡剼
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]
set_property PACKAGE_PIN G15 [get_ports uart_rx_pin]

# PWM 寮曡剼
# set_property IOSTANDARD LVCMOS33 [get_ports PWM_o[0]]
# set_property PACKAGE_PIN E21 [get_ports PWM_o[0]]

# set_property IOSTANDARD LVCMOS33 [get_ports PWM_o[1]]
# set_property PACKAGE_PIN D20 [get_ports PWM_o[1]]

# set_property IOSTANDARD LVCMOS33 [get_ports PWM_o[2]]
# set_property PACKAGE_PIN C20 [get_ports PWM_o[2]]

# I2C 寮曡剼
set_property IOSTANDARD LVCMOS33 [get_ports io_scl]
set_property PACKAGE_PIN M22 [get_ports io_scl]

set_property IOSTANDARD LVCMOS33 [get_ports io_sda]
set_property PACKAGE_PIN N22 [get_ports io_sda]

set_property PULLUP true [get_ports sda]
set_property PULLUP true [get_ports scl]

# Debug 寮曡剼
set_property IOSTANDARD LVCMOS33 [get_ports uart_debug_pin]
set_property PACKAGE_PIN M13 [get_ports uart_debug_pin]