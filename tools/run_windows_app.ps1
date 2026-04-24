param(
    [switch]$DevMode,
    [switch]$VerboseRun,
    [switch]$NoResident,
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
Set-Location $workspaceRoot

Write-Host '[INFO] Stopping stale digital_lab processes...' -ForegroundColor Cyan
Get-Process digital_lab -ErrorAction SilentlyContinue | Stop-Process -Force

if ($DevMode) {
    Write-Host '[INFO] Ensuring dependencies are ready...' -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
    }

    $runArgs = @('run', '-d', 'windows')
    if ($VerboseRun) {
        $runArgs += '-v'
    }
    if ($NoResident) {
        $runArgs += '--no-resident'
    }

    Write-Host "[INFO] Starting app (dev mode): flutter $($runArgs -join ' ')" -ForegroundColor Cyan
    flutter @runArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter run failed with exit code $LASTEXITCODE"
    }
}
else {
    if (-not $SkipBuild) {
        Write-Host '[INFO] Building release app...' -ForegroundColor Cyan
        flutter build windows
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build windows failed with exit code $LASTEXITCODE"
        }
    }

    $exePath = Join-Path $workspaceRoot 'build\windows\x64\runner\Release\digital_lab.exe'
    if (-not (Test-Path $exePath)) {
        throw "Release executable not found: $exePath"
    }

    Write-Host "[INFO] Starting release app: $exePath" -ForegroundColor Cyan
    Start-Process -FilePath $exePath

    Start-Sleep -Seconds 2
    $proc = Get-Process digital_lab -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $proc) {
        throw 'digital_lab.exe did not start.'
    }

    if ($proc.MainWindowHandle -ne 0) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinApi {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue
        [WinApi]::ShowWindow($proc.MainWindowHandle, 9) | Out-Null
        [WinApi]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
    }

    Write-Host '[OK] Release app started.' -ForegroundColor Green
}
