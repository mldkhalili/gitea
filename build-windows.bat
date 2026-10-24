@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto run_build

set "BUILD_BAT=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; try { $bat = $env:BUILD_BAT; $arguments = '/c ""' + $bat + '""'; Start-Process -FilePath $env:ComSpec -Verb RunAs -WorkingDirectory (Split-Path -LiteralPath $bat) -ArgumentList $arguments } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (
    echo Failed to start the build with administrator privileges. The UAC prompt may have been canceled.
    pause
    exit /b 1
)
exit /b 0

:run_build
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1"
set "BUILD_EXIT=%ERRORLEVEL%"
if not "%BUILD_EXIT%"=="0" echo Windows build failed with exit code %BUILD_EXIT%.
pause
exit /b %BUILD_EXIT%
