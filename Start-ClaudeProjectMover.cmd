@echo off
setlocal
set "SCRIPT_VERSION=1.8.0"
rem ================================================================
rem  Claude Code Project Mover - Windows Starter
rem ================================================================
rem
rem  EMPFOHLENER START
rem  1. Den vollstaendigen Projektordner herunterladen oder klonen.
rem  2. Claude Code und alle Sitzungen der betroffenen Projekte schliessen.
rem  3. Diese Datei per Doppelklick starten.
rem
rem  Der Starter verwendet PowerShell 7, sofern vorhanden. Andernfalls wird
rem  Windows PowerShell 5.1 verwendet. ExecutionPolicy Bypass gilt nur fuer
rem  diesen gestarteten Prozess und veraendert keine globale Richtlinie.
rem ================================================================

set "SCRIPT_DIR=%~dp0"
set "GUI_SCRIPT=%SCRIPT_DIR%claude-project-mover-gui.ps1"
set "CORE_SCRIPT=%SCRIPT_DIR%claude-project-mover.ps1"
set "INVENTORY_MODULE=%SCRIPT_DIR%ClaudeProjectInventory.psm1"
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
    echo Der Claude Code Project Mover wurde mit Fehlercode %EXIT_CODE% beendet.
    echo Bitte die Meldung oberhalb pruefen.
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
for %%F in ("%GUI_SCRIPT%" "%CORE_SCRIPT%" "%INVENTORY_MODULE%" "%VERSION_FILE%") do (
    if not exist "%%~F" (
        echo.
        echo FEHLER: Erforderliche Datei wurde nicht gefunden:
        echo "%%~F"
        echo.
        echo Bitte immer den vollstaendigen Projektordner verwenden.
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
echo Claude Code Project Mover v%SCRIPT_VERSION% - Hilfe
echo.
echo   Start-ClaudeProjectMover.cmd                 GUI starten
echo   Start-ClaudeProjectMover.cmd /cli            CLI starten
echo   Start-ClaudeProjectMover.cmd /list-projects  Projektuebersicht anzeigen
echo   Start-ClaudeProjectMover.cmd /version        Version anzeigen
echo.
echo Benoetigte Dateien im gleichen Ordner:
echo   Start-ClaudeProjectMover.cmd
echo   claude-project-mover-gui.ps1
echo   claude-project-mover.ps1
echo   ClaudeProjectInventory.psm1
echo   VERSION
echo.
exit /b 0
