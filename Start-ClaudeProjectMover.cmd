@echo off
setlocal
set "SCRIPT_VERSION=2.0.0"
rem ================================================================
rem  Claude Code Project Mover - Windows Starter
rem ================================================================
rem
rem  RECOMMENDED START
rem  1. Download or clone the complete project folder.
rem  2. Close Claude Code and all affected sessions.
rem  3. Double-click this file.
rem
rem  The starter uses PowerShell 7 when available and otherwise falls back to
rem  Windows PowerShell 5.1. ExecutionPolicy Bypass applies only to this
rem  process and does not change a global policy.
rem ================================================================

set "SCRIPT_DIR=%~dp0"
set "GUI_SCRIPT=%SCRIPT_DIR%claude-project-mover-gui.ps1"
set "CORE_SCRIPT=%SCRIPT_DIR%claude-project-mover.ps1"
set "INVENTORY_MODULE=%SCRIPT_DIR%ClaudeProjectInventory.psm1"
set "LOCALIZATION_MODULE=%SCRIPT_DIR%ClaudeProjectLocalization.psm1"
set "VERSION_FILE=%SCRIPT_DIR%VERSION"
title Claude Code Project Mover v%SCRIPT_VERSION%

if /I "%~1"=="/help" goto :help
if /I "%~1"=="-help" goto :help
if /I "%~1"=="--help" goto :help
if /I "%~1"=="/version" goto :version
if /I "%~1"=="--version" goto :version
if /I "%~1"=="/list-projects" goto :list
if /I "%~1"=="--list-projects" goto :list
if /I "%~1"=="/cli" goto :cli

call :checkfiles
if errorlevel 1 exit /b 1
call :findpowershell
pushd "%SCRIPT_DIR%" >nul
%POWERSHELL_EXE% -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%GUI_SCRIPT%"
set "EXIT_CODE=%errorlevel%"
popd >nul
if not "%EXIT_CODE%"=="0" (
    echo.
    echo Claude Code Project Mover exited with error code %EXIT_CODE%.
    echo Review the message above.
    echo.
    pause
)
exit /b %EXIT_CODE%

:cli
call :checkfiles
if errorlevel 1 exit /b 1
call :findpowershell
pushd "%SCRIPT_DIR%" >nul
%POWERSHELL_EXE% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CORE_SCRIPT%"
set "EXIT_CODE=%errorlevel%"
popd >nul
exit /b %EXIT_CODE%

:list
call :checkfiles
if errorlevel 1 exit /b 1
call :findpowershell
pushd "%SCRIPT_DIR%" >nul
%POWERSHELL_EXE% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CORE_SCRIPT%" -ListProjects
set "EXIT_CODE=%errorlevel%"
popd >nul
exit /b %EXIT_CODE%

:findpowershell
where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
    set "POWERSHELL_EXE=pwsh.exe"
) else (
    set "POWERSHELL_EXE=powershell.exe"
)
exit /b 0

:checkfiles
for %%F in ("%GUI_SCRIPT%" "%CORE_SCRIPT%" "%INVENTORY_MODULE%" "%LOCALIZATION_MODULE%" "%VERSION_FILE%") do (
    if not exist "%%~F" (
        echo.
        echo ERROR: A required file was not found:
        echo "%%~F"
        echo.
        echo Always use the complete project folder.
        pause
        exit /b 1
    )
)
exit /b 0

:version
echo Claude Code Project Mover v%SCRIPT_VERSION%
exit /b 0

:help
echo.
echo Claude Code Project Mover v%SCRIPT_VERSION% - Help
echo.
echo   Start-ClaudeProjectMover.cmd                 Start GUI
echo   Start-ClaudeProjectMover.cmd /cli            Start CLI
echo   Start-ClaudeProjectMover.cmd /list-projects  Show project overview
echo   Start-ClaudeProjectMover.cmd /version        Show version
echo.
echo Required files in the same folder:
echo   Start-ClaudeProjectMover.cmd
echo   claude-project-mover-gui.ps1
echo   claude-project-mover.ps1
echo   ClaudeProjectInventory.psm1
echo   ClaudeProjectLocalization.psm1
echo   VERSION
echo.
exit /b 0
