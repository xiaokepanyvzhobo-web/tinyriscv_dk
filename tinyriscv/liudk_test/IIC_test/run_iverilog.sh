#!/usr/bin/env bash
set -euo pipefail

mkdir -p build log waves

iverilog -g2012 -Wall -s iic_temperature_read_tb -f tb.f -o build/iic_temperature_read_tb.vvp
vvp build/iic_temperature_read_tb.vvp | tee log/iic_temperature_read_tb.log
