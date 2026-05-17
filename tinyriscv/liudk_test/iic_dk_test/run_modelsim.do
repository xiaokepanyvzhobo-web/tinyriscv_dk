transcript file log/modelsim_iic_dk_tb.log
transcript on

if {![file exists build]} {
    file mkdir build
}
if {![file exists log]} {
    file mkdir log
}
if {![file exists waves]} {
    file mkdir waves
}

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv -work work iic_dk.v iic_dk_tb.v
vsim -novopt work.iic_dk_tb

view wave
view transcript

add wave -divider "TB"
add wave -radix binary  sim:/iic_dk_tb/clk
add wave -radix binary  sim:/iic_dk_tb/rst
add wave -radix binary  sim:/iic_dk_tb/req_i
add wave -radix binary  sim:/iic_dk_tb/we_i
add wave -radix hex     sim:/iic_dk_tb/addr_i
add wave -radix hex     sim:/iic_dk_tb/data_i
add wave -radix hex     sim:/iic_dk_tb/data_o
add wave -radix binary  sim:/iic_dk_tb/ack_o

add wave -divider "IIC Bus"
add wave -radix binary  sim:/iic_dk_tb/scl
add wave -radix binary  sim:/iic_dk_tb/sda
add wave -radix binary  sim:/iic_dk_tb/master_sda_o
add wave -radix binary  sim:/iic_dk_tb/master_sda_oe
add wave -radix binary  sim:/iic_dk_tb/slave_sda_o
add wave -radix binary  sim:/iic_dk_tb/slave_sda_oe
add wave -radix binary  sim:/iic_dk_tb/bus_conflict

add wave -divider "DUT Internal"
add wave -radix unsigned sim:/iic_dk_tb/u_iic/iic_cs
add wave -radix unsigned sim:/iic_dk_tb/u_iic/iic_ns
add wave -radix unsigned sim:/iic_dk_tb/u_iic/scl_phrase
add wave -radix unsigned sim:/iic_dk_tb/u_iic/iic_counter
add wave -radix binary   sim:/iic_dk_tb/u_iic/iic_tick
add wave -radix unsigned sim:/iic_dk_tb/u_iic/sda_counter
add wave -radix binary   sim:/iic_dk_tb/u_iic/rx_ack
add wave -radix hex      sim:/iic_dk_tb/u_iic/addr_reg
add wave -radix hex      sim:/iic_dk_tb/u_iic/data_in_reg
add wave -radix hex      sim:/iic_dk_tb/u_iic/data_out_reg

run -all
wave zoom full

transcript off
