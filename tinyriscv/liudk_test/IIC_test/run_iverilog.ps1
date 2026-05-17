$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path build | Out-Null
New-Item -ItemType Directory -Force -Path log | Out-Null
New-Item -ItemType Directory -Force -Path waves | Out-Null

iverilog -g2012 -Wall -s iic_temperature_read_tb -f tb.f -o build/iic_temperature_read_tb.vvp
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp build/iic_temperature_read_tb.vvp | Tee-Object -FilePath log/iic_temperature_read_tb.log
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

