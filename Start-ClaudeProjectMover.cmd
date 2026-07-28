@echo off
setlocal

rem ================================================================
rem  Claude Code Project Mover - Windows Starter
rem ================================================================
rem
rem  EMPFOHLENER START
rem  1. Dieses Repository als ZIP herunterladen und vollstaendig entpacken.
rem  2. Claude Code und alle Sitzungen der betroffenen Projekte schliessen.
rem  3. Diese Datei per Doppelklick starten.
rem
rem  BEDIENUNG
rem  - Ein oder mehrere Claude-Code-Projekte markieren.
rem  - Auf "Quellen pruefen" klicken.
rem  - Status, Projekttyp, Dateianzahl, Groesse und Hinweise kontrollieren.
rem  - Gemeinsamen Zielordner auswaehlen.
rem  - Backup aktiviert lassen.
rem  - Verschiebung bestaetigen.
rem
rem  Der Starter verwendet PowerShell 7, sofern vorhanden. Andernfalls wird
rem  Windows PowerShell 5.1 verwendet. ExecutionPolicy Bypass gilt nur fuer
rem  diesen gestarteten Prozess und veraendert keine globale Richtlinie.
rem
rem  Hilfe im Terminal:
rem    Start-ClaudeProjectMover.cmd /help
rem ================================================================

if /I "%~1"=="/help" goto :help
if /I "%~1"=="-help" goto :help
if /I "%~1"=="--help" goto :help

set "SCRIPT_DIR=%~dp0"
set "GUI_SCRIPT=%SCRIPT_DIR%claude-project-mover-gui.ps1"
set "CORE_SCRIPT=%SCRIPT_DIR%claude-project-mover.ps1"

if not exist "%GUI_SCRIPT%" (
    echo.
    echo FEHLER: claude-project-mover-gui.ps1 wurde nicht gefunden.
    echo Erwarteter Pfad: "%GUI_SCRIPT%"
    echo.
    pause
    exit /b 1
)

if not exist "%CORE_SCRIPT%" (
    echo.
    echo FEHLER: claude-project-mover.ps1 wurde nicht gefunden.
    echo Erwarteter Pfad: "%CORE_SCRIPT%"
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
    echo Der Claude Code Project Mover wurde mit Fehlercode %EXIT_CODE% beendet.
    echo Bitte die Meldung oberhalb pruefen.
    echo.
    pause
)

exit /b %EXIT_CODE%

:help
echo.
echo Claude Code Project Mover - Hilfe
echo.
echo Empfohlener Start:
echo   Start-ClaudeProjectMover.cmd
echo.
echo Ablauf:
echo   1. Claude Code schliessen.
echo   2. Ein oder mehrere Projekte markieren.
echo   3. Quellen pruefen.
echo   4. Zielordner auswaehlen.
echo   5. Backup aktiviert lassen.
echo   6. Verschieben bestaetigen.
echo.
echo Benoetigte Dateien im gleichen Ordner:
echo   Start-ClaudeProjectMover.cmd
echo   claude-project-mover-gui.ps1
echo   claude-project-mover.ps1
echo.
exit /b 0
