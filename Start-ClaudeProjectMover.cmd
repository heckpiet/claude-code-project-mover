@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "GUI_SCRIPT=%SCRIPT_DIR%claude-project-mover-gui.ps1"

if not exist "%GUI_SCRIPT%" (
    echo.
    echo ERROR: claude-project-mover-gui.ps1 was not found.
    echo Expected location: "%GUI_SCRIPT%"
    echo.
    pause
    exit /b 1
)

pushd "%SCRIPT_DIR%" >nul

where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%GUI_SCRIPT%"
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%GUI_SCRIPT%"
)

set "EXIT_CODE=%errorlevel%"
popd >nul

if not "%EXIT_CODE%"=="0" (
    echo.
    echo The Claude Code Project Mover exited with code %EXIT_CODE%.
    echo Review the message above for details.
    echo.
    pause
)

exit /b %EXIT_CODE%
