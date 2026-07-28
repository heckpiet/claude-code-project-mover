# Claude Code Project Mover – Schnellstart unter Windows

Diese Anleitung beschreibt den einfachsten und empfohlenen Start des Tools unter Windows.

## Vor dem Start

1. Lade das komplette Repository über **Code → Download ZIP** herunter.
2. Entpacke die ZIP-Datei vollständig in einen eigenen Ordner.
3. Lass alle enthaltenen Dateien gemeinsam in diesem Ordner.
4. Schließe Claude Code vollständig, bevor du Projekte verschiebst.

Das Tool benötigt insbesondere diese Dateien:

```text
Start-ClaudeProjectMover.cmd
claude-project-mover-gui.ps1
claude-project-mover.ps1
```

## Empfohlener Start

Starte im entpackten Ordner die Datei:

```text
Start-ClaudeProjectMover.cmd
```

Du kannst sie im Windows-Explorer doppelt anklicken. Der Starter öffnet die grafische Oberfläche und verwendet eine nur für diesen Prozess geltende PowerShell-Freigabe. Die globale PowerShell-Ausführungsrichtlinie wird nicht verändert.

## Start über das Terminal

Wechsle zuerst mit `cd` in den entpackten Ordner. Ein Pfad allein ist in PowerShell kein Verzeichniswechsel.

Beispiel:

```powershell
cd "$HOME\Downloads\claude-code-project-mover"
.\Start-ClaudeProjectMover.cmd
```

Alternativ kann die GUI direkt gestartet werden:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1
```

Ist PowerShell 7 nicht installiert, funktioniert auch Windows PowerShell:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1
```

## Bedienung

1. Wähle in der Liste ein oder mehrere Claude-Code-Projekte aus.
2. Klicke auf **Durchsuchen ...** und wähle einen gemeinsamen Zielordner.
3. Lass **Projektverzeichnisse physisch verschieben** aktiviert, wenn das Tool die echten Projektordner verschieben soll.
4. Lass **Claude-Metadaten als ZIP sichern** für wichtige Projekte aktiviert.
5. Klicke auf **Verschieben**.
6. Prüfe den angezeigten Quell- und Zielplan sorgfältig.
7. Bestätige den Vorgang erst, wenn alle Pfade korrekt sind.

## Beispiel für mehrere Projekte

Aus diesen Projekten:

```text
C:\Users\Peter\Code\Projekt-A
C:\Users\Peter\Code\Projekt-B
```

und dem gemeinsamen Zielordner:

```text
D:\Development
```

werden:

```text
D:\Development\Projekt-A
D:\Development\Projekt-B
```

Die Namen der Projektordner bleiben erhalten.

## Nur Claude-Metadaten aktualisieren

Deaktiviere **Projektverzeichnisse physisch verschieben**, wenn du die Projektordner bereits selbst verschoben hast. Die erwarteten Zielordner müssen dann schon unter dem ausgewählten gemeinsamen Zielordner existieren.

## Typische Startfehler

### Ein Pfad wird als Befehl behandelt

Falsch:

```powershell
C:\Users\Peter\Downloads
```

Richtig:

```powershell
cd C:\Users\Peter\Downloads
```

### Das Skript ist nicht digital signiert

Starte nicht direkt mit:

```powershell
.\claude-project-mover-gui.ps1
```

Nutze stattdessen:

```powershell
.\Start-ClaudeProjectMover.cmd
```

Der Starter setzt `ExecutionPolicy Bypass` ausschließlich für den gestarteten Prozess.

### Die GUI-Datei wird nicht gefunden

Prüfe, ob `Start-ClaudeProjectMover.cmd`, `claude-project-mover-gui.ps1` und `claude-project-mover.ps1` im gleichen Ordner liegen. Lade im Zweifel das komplette Repository erneut herunter und entpacke es vollständig.

## Sicherheitshinweise

- Claude Code vor dem Verschieben schließen.
- Das ZIP-Backup für wichtige Sitzungsverläufe aktiviert lassen.
- Bestehende Zielordner werden nicht überschrieben oder zusammengeführt.
- Den angezeigten Migrationsplan vor der Bestätigung kontrollieren.
- Für einen ersten Test ein entbehrliches Projekt verwenden.

Weitere technische Details stehen in [WINDOWS-GUI.md](WINDOWS-GUI.md) und in der allgemeinen [README.md](README.md).
