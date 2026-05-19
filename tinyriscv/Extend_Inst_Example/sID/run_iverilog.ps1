param(
    [switch]$NoDump,
    [switch]$Trace
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
$BuildDir = Join-Path $ScriptDir "build"

New-Item -ItemType Directory -Force $BuildDir | Out-Null

$sources = @()
$sources += Join-Path $ScriptDir "sID_tb.v"
$sources += Get-ChildItem -Path (Join-Path $RepoRoot "rtl\utils") -Filter "*.v" | ForEach-Object { $_.FullName }
$sources += Get-ChildItem -Path (Join-Path $RepoRoot "rtl\debug") -Filter "*.v" | ForEach-Object { $_.FullName }
$sources += Get-ChildItem -Path (Join-Path $RepoRoot "rtl\core") -Filter "*.v" | ForEach-Object { $_.FullName }
$sources += Get-ChildItem -Path (Join-Path $RepoRoot "rtl\perips") -Filter "*.v" | ForEach-Object { $_.FullName }
$sources += Get-ChildItem -Path (Join-Path $RepoRoot "rtl\soc") -Filter "*.v" | ForEach-Object { $_.FullName }

$iverilogArgs = @(
    "-g2012",
    "-DIVERILOG_FAST_SIM",
    "-I", (Join-Path $RepoRoot "rtl\core"),
    "-I", (Join-Path $RepoRoot "rtl\perips"),
    "-I", (Join-Path $RepoRoot "rtl\utils"),
    "-I", (Join-Path $RepoRoot "rtl\debug"),
    "-I", (Join-Path $RepoRoot "rtl\soc"),
    "-s", "sID_tb",
    "-o", (Join-Path $BuildDir "sID_tb.vvp")
)

if ($NoDump) {
    $iverilogArgs += "-DNO_DUMP"
}

if ($Trace) {
    $iverilogArgs += "-DTRACE_CORE"
}

Push-Location $RepoRoot
try {
    & iverilog @iverilogArgs @sources
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & vvp (Join-Path $BuildDir "sID_tb.vvp") `
        "+INST_FILE=Extend_Inst_Example/sID/sID_inst.data" `
        "+VCD_FILE=Extend_Inst_Example/sID/build/sID_tb.vcd" `
        "+ROM_DUMP=Extend_Inst_Example/sID/build/downloaded_rom_after_uart.hex"
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
