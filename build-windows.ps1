$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This build script must run on Windows.'
}

$projectRoot = $PSScriptRoot
$goMod = Get-Content -LiteralPath (Join-Path $projectRoot 'go.mod')
$toolchainLine = $goMod | Where-Object { $_ -match '^toolchain\s+go' } | Select-Object -First 1
if ($toolchainLine -match '^toolchain\s+go([\d.]+)$') {
    $requiredGoVersion = [version]$Matches[1]
} else {
    throw 'Could not determine the required Go toolchain from go.mod.'
}

$goCommand = Get-Command go.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$goExe = if ($goCommand -and (Test-Path -LiteralPath $goCommand.Source)) { $goCommand.Source }
if (-not $goExe -and $env:GOROOT) {
    $candidate = Join-Path $env:GOROOT 'bin\go.exe'
    if (Test-Path -LiteralPath $candidate) { $goExe = $candidate }
}
if (-not $goExe -and (Test-Path -LiteralPath 'C:\Program Files\Go\bin\go.exe')) {
    $goExe = 'C:\Program Files\Go\bin\go.exe'
}
if (-not $goExe) {
    throw 'Go was not found. Install the Go version required by go.mod.'
}
$goVersionOutput = & $goExe version
if ($goVersionOutput -notmatch 'go version go([\d.]+)\s') {
    throw "Could not read the installed Go version: $goVersionOutput"
}
if ([version]$Matches[1] -lt $requiredGoVersion) {
    throw "Go $($Matches[1]) is too old; this source requires Go $requiredGoVersion or newer."
}

$makeCommand = Get-Command make.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$makeExe = if ($makeCommand -and (Test-Path -LiteralPath $makeCommand.Source)) { $makeCommand.Source }
$makePaths = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\make.exe'),
    'C:\msys64\usr\bin\make.exe'
)
if ($env:ChocolateyInstall) {
    $makePaths += Join-Path $env:ChocolateyInstall 'bin\make.exe'
}
foreach ($candidate in $makePaths) {
    if (-not $makeExe -and (Test-Path -LiteralPath $candidate)) { $makeExe = $candidate }
}
if (-not $makeExe) {
    throw 'GNU Make was not found. Install GNU Make before building.'
}

$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$corepackCommand = Get-Command corepack.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $corepackCommand -and $nodeCommand) {
    $candidate = Join-Path (Split-Path -Parent $nodeCommand.Source) 'corepack.cmd'
    if (Test-Path -LiteralPath $candidate) {
        $corepackCommand = Get-Item -LiteralPath $candidate
    }
}
if (-not $corepackCommand) {
    throw 'Corepack was not found. Install Node.js with Corepack enabled.'
}

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$gitRoot = if ($gitCommand) { Split-Path -Parent (Split-Path -Parent $gitCommand.Source) }
$gitBin = if ($gitRoot) { Join-Path $gitRoot 'usr\bin' }
if (-not $gitBin -or -not (Test-Path (Join-Path $gitBin 'sh.exe'))) {
    throw 'Git for Windows with its Unix tools (Git Bash) is required by Make.'
}

$toolsDirectory = Join-Path $projectRoot ('.build-windows-' + [guid]::NewGuid().ToString('N'))
$binary = Join-Path $projectRoot 'gitea.exe'
$previousBinaryTime = if (Test-Path -LiteralPath $binary) { (Get-Item -LiteralPath $binary).LastWriteTime } else { [datetime]::MinValue }
$originalPath = $env:Path
try {
    New-Item -ItemType Directory -Path $toolsDirectory | Out-Null
    $corepackPath = $corepackCommand.Source.Replace('%', '%%')
    $pnpmShim = "@echo off`r`ncall `"$corepackPath`" pnpm %*`r`nexit /b %errorlevel%`r`n"
    Set-Content -LiteralPath (Join-Path $toolsDirectory 'pnpm.cmd') -Value $pnpmShim -Encoding ASCII

    $env:Path = @(
        $toolsDirectory,
        (Split-Path -Parent $goExe),
        $gitBin,
        (Join-Path $gitRoot 'bin'),
        $(if ($nodeCommand) { Split-Path -Parent $nodeCommand.Source }),
        (Split-Path -Parent $makeExe),
        $originalPath
    ) -join ';'

    & $corepackCommand.Source pnpm --version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Corepack could not start pnpm.'
    }

    Push-Location $projectRoot
    try {
        & $makeExe -B build TAGS=bindata
        if ($LASTEXITCODE -ne 0) {
            throw "Windows build failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $binary)) {
        throw 'Build finished without producing gitea.exe.'
    }
    if ((Get-Item -LiteralPath $binary).LastWriteTime -le $previousBinaryTime) {
        throw 'gitea.exe was not updated by this build.'
    }

    Write-Host "Build succeeded: $binary"
    & $binary --version
} finally {
    $env:Path = $originalPath
    if (Test-Path -LiteralPath $toolsDirectory) {
        Remove-Item -LiteralPath $toolsDirectory -Recurse -Force
    }
}
