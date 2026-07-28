@echo off
rem ============================================================================
rem  Claude Code Project Mover - Windows Starter
rem ============================================================================
rem
rem  STARTEN
rem  -------
rem  1. Das komplette Repository als ZIP herunterladen und entpacken.
rem  2. Diese Datei per Doppelklick starten:
rem
rem       Start-ClaudeProjectMover.cmd
rem
rem  Alternativ im Terminal:
rem
rem       cd C:\Pfad\zum\claude-code-project-mover
rem       .\Start-ClaudeProjectMover.cmd
rem
rem  NUTZUNG
rem  -------
rem  1. Claude Code vollständig schließen.
rem  2. Ein oder mehrere Quellprojekte in der Liste auswählen.
rem  3. Über "Durchsuchen" einen gemeinsamen Zielordner auswählen.
rem  4. "Projektverzeichnisse physisch verschieben" aktiviert lassen, wenn
rem     das Tool die echten Projektordner verschieben soll.
rem  5. Das ZIP-Backup aktiviert lassen.
rem  6. Auf "Verschieben" klicken und den angezeigten Plan bestätigen.
rem
rem  Beispiel:
rem
rem       Quelle: C:\Users\Name\Code\ProjektA
rem       Ziel:   D:\Development
rem       Ergebnis: D:\Development\ProjektA
rem
rem  WICHTIG
rem  -------
rem  - Diese Starterdatei umgeht die PowerShell-Ausführungsrichtlinie nur für
rem    diesen einen Prozess. Die globale Windows-Konfiguration bleibt unverändert.
rem  - Alle Dateien aus dem Repository müssen im gleichen Ordner bleiben.
rem  - Vor wichtigen Migrationen das vorgeschlagene ZIP-Backup erstellen.
rem  - Mehr Informationen stehen in START-HERE.md und WINDOWS-GUI.md.
rem
rem ============================================================================

setlocal

set "SCRIPT_DIR=%~dp0"
set "GUI_SCRIPT=%SCRIPT_DIR%claude-project-mover-gui.ps1"

if /I "%~1"=="/help" goto :help
if /I "%~1"=="-help" goto :help
if /I "%~1"=="--help" goto :help

if not exist "%GUI_SCRIPT%" (
    echo.
    echo FEHLER: claude-project-mover-gui.ps1 wurde nicht gefunden.
    echo Erwarteter Pfad: "%GUI_SCRIPT%"
    echo.
    echo Bitte das komplette Repository herunterladen und alle Dateien
    echo gemeinsam in einem Ordner belassen.
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
    echo Bitte die vorstehende Fehlermeldung prüfen.
    echo.
    pause
)

exit /b %EXIT_CODE%

:help
echo.
echo Claude Code Project Mover
echo =========================
echo.
echo Start:
echo   Start-ClaudeProjectMover.cmd
echo.
echo Bedienung:
echo   1. Claude Code schliessen.
echo   2. Projekte auswaehlen.
echo   3. Zielordner auswaehlen.
echo   4. Backup aktiviert lassen.
echo   5. Verschieben anklicken und Plan bestaetigen.
echo.
echo Dokumentation:
echo   START-HERE.md
echo   WINDOWS-GUI.md
echo   README.md
echo.
exit /b 0
