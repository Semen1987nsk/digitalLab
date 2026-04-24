Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnMsg([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Add-ToPathIfExists([string]$PathToAdd) {
    if ([string]::IsNullOrWhiteSpace($PathToAdd)) { return }
    if (-not (Test-Path $PathToAdd)) { return }

    if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $PathToAdd })) {
        $env:PATH = "$PathToAdd;$env:PATH"
    }
}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$firmwareRoot = Join-Path $workspaceRoot 'firmware'
$toolingRequirements = Join-Path $firmwareRoot 'requirements-tooling.txt'

if (-not (Test-Path $toolingRequirements)) {
    throw "Pinned tooling file not found: $toolingRequirements"
}

$usePyLauncher = Test-Command 'py'
if (-not $usePyLauncher -and -not (Test-Command 'python')) {
    throw 'Python 3 not found. Install Python 3.11+ and retry.'
}

if ($usePyLauncher) {
    Write-Info 'Using Python: py -3'
    & py -3 -m pip install --upgrade pip
}
else {
    Write-Info 'Using Python: python'
    & python -m pip install --upgrade pip
}

if (-not (Test-Command 'pipx')) {
    Write-Info 'Installing pipx (isolated CLI manager)...'
    if ($usePyLauncher) {
        & py -3 -m pip install --user pipx
    }
    else {
        & python -m pip install --user pipx
    }
}

# ensurepath does not always update current session; patch PATH manually
if ($usePyLauncher) {
    $pythonUserSite = (& py -3 -c "import site; print(site.getusersitepackages())").Trim()
}
else {
    $pythonUserSite = (& python -c "import site; print(site.getusersitepackages())").Trim()
}

$pythonUserSiteDir = Split-Path -Parent $pythonUserSite
$userScriptsPath = Join-Path $pythonUserSiteDir 'Scripts'
$pipxBinPath = Join-Path $env:USERPROFILE '.local\bin'

Add-ToPathIfExists $userScriptsPath
Add-ToPathIfExists $pipxBinPath

if (Test-Command 'pipx') {
    Write-Info 'pipx is available.'
}

$platformIoVersion = (Get-Content $toolingRequirements | Select-String 'platformio' | Select-Object -First 1).ToString().Trim()
if ([string]::IsNullOrWhiteSpace($platformIoVersion)) {
    $platformIoVersion = 'platformio==6.1.18'
}

if (-not (Test-Command 'pio')) {
    if (Test-Command 'pipx') {
        Write-Info "Installing $platformIoVersion via pipx..."
        pipx install --force $platformIoVersion | Out-Null
    }
}

if (-not (Test-Command 'pio')) {
    Write-WarnMsg 'pio command is still missing after pipx. Falling back to pip --user.'
    if ($usePyLauncher) {
        & py -3 -m pip install --user $platformIoVersion
    }
    else {
        & python -m pip install --user $platformIoVersion
    }
}

# pip may create Scripts directory during install; ensure PATH is refreshed
Add-ToPathIfExists $userScriptsPath

if (-not (Test-Command 'pio')) {
    $pioExe = Join-Path $userScriptsPath 'pio.exe'
    if (Test-Path $pioExe) {
        $env:PATH = "$userScriptsPath;$env:PATH"
    }
}

if (-not (Test-Command 'pio')) {
    throw 'Failed to install PlatformIO CLI (pio). Verify PATH and restart terminal.'
}

$pioVersion = (pio --version).Trim()
Write-Ok "PlatformIO is available: $pioVersion"
Write-Ok 'Firmware toolchain is ready.'
