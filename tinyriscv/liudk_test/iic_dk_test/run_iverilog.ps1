$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force build, log, waves | Out-Null

iverilog -g2012 -Wall -s iic_dk_tb -f tb.f -o build/iic_dk_tb.vvp
vvp build/iic_dk_tb.vvp | Tee-Object -FilePath log/iic_dk_tb.log
