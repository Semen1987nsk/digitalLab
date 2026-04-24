Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$bootstrapScript = Join-Path $PSScriptRoot 'bootstrap_firmware_env.ps1'
$firmwareRoot = Join-Path $workspaceRoot 'firmware'

if (-not (Test-Path $bootstrapScript)) {
    throw "Bootstrap script not found: $bootstrapScript"
}

if (-not (Test-Path $firmwareRoot)) {
    throw "Firmware folder not found: $firmwareRoot"
}

Write-Host '[INFO] Preparing firmware toolchain...' -ForegroundColor Cyan
& $bootstrapScript

Write-Host '[INFO] Building firmware (esp32s3)...' -ForegroundColor Cyan
Push-Location $firmwareRoot
try {
    pio run -e esp32s3
    if ($LASTEXITCODE -ne 0) {
        throw "PlatformIO build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host '[OK] Firmware build completed.' -ForegroundColor Green
