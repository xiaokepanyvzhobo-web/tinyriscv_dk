$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force build, log, waves | Out-Null

$modelsim = "D:\liudk\software\import\modelsim\modelsim\Modelsim 10.1c\modelsim\win64\vsim.exe"
$license = "D:\liudk\software\import\modelsim\modelsim\Modelsim 10.1c\modelsim\win64\LICENSE.TXT"

$env:LM_LICENSE_FILE = $license
$env:MGLS_LICENSE_FILE = $license

& $modelsim -do "do run_modelsim.do"
