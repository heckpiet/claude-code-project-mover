# Schnellstart für Windows

Diese Datei beschreibt den empfohlenen Weg, ein oder mehrere Claude-Code-Projekte einschließlich ihrer bisherigen Sitzungen an einen neuen Speicherort zu verschieben.

Dieses Repository wird als Windows-first-Projekt entwickelt und getestet. Der empfohlene Funktionsumfang umfasst Windows 10/11, Windows PowerShell 5.1, PowerShell 7 und die native Windows-Forms-Oberfläche. Hinweise zu macOS und Linux stehen ergänzend in der README.

## Vorbereitung

1. Über **Code → Download ZIP** den vollständigen Quellordner herunterladen und entpacken oder das Repository klonen. Ein separates Release-Paket ist noch nicht veröffentlicht.
2. Claude Code sowie alle Sitzungen der betroffenen Projekte schließen.
3. Prüfen, dass diese Dateien im gleichen Ordner liegen:

```text
Start-ClaudeProjectMover.cmd
claude-project-mover-gui.ps1
claude-project-mover.ps1
ClaudeProjectInventory.psm1
VERSION
```

## Start

Am einfachsten startest du das Tool per Doppelklick auf:

```text
Start-ClaudeProjectMover.cmd
```

Alternativ im Terminal:

```powershell
cd "$HOME\Downloads\claude-code-project-mover"
.\Start-ClaudeProjectMover.cmd
```

Der Starter verwendet PowerShell 7, sofern vorhanden, und ansonsten Windows PowerShell 5.1. Die Ausführungsrichtlinie wird nur für diesen Prozess umgangen. Es wird keine globale PowerShell-Einstellung verändert.

## Bedienung

1. Ein oder mehrere Projekte markieren.
2. Auf **Quellen prüfen** klicken.
3. Status, Projekttyp, Dateianzahl, Größe und Hinweise kontrollieren.
4. Einen gemeinsamen Zielordner auswählen.
5. **Verschieben**, **Kopieren** oder **Nur Metadaten** auswählen.
6. **Claude-Metadaten als ZIP sichern**, **Herkunft im Ziel dokumentieren**, **Session-Paket sichern** und **Sichere Session-Dateien kopieren** aktiviert lassen.
7. Auf **Ausführen** klicken und den Plan bestätigen.

Der gemeinsame GUI-Zielordner ist ein Sammelordner; die GUI legt darin pro ausgewähltem Projekt einen eigenen Unterordner an. Beim direkten Aufruf von `claude-project-mover.ps1` ist dagegen der vollständige Ziel-Projektordner anzugeben, beispielsweise `D:\Projekte\MeinProjekt` statt nur `D:\Projekte`.

Besitzt eine ausgewählte Sitzungsgruppe noch keinen eigenen Projektordner oder liegt sie in einem erkannten Sammelordner mit weiteren Claude-Projekten, fragt die GUI nach einem neuen Ordnernamen. Sie schlägt aus Titel oder Sitzungsinhalt einen Namen vor, legt diesen Ordner unterhalb des gemeinsamen Ziels an und stellt nur die Claude-Sitzungsmetadaten darauf um. Ein allgemeiner Quell- oder Sammelordner wird niemals vollständig verschoben.

Existiert der vorgeschlagene Unterordner schon, kannst du ihn verwenden, einen anderen Namen wählen oder abbrechen. Beim Verwenden bleiben vorhandene Dateien bestehen; das Tool ergänzt nur die zur Session gehörenden sicheren Dateien und Claude-Hilfsdaten.

Wähle je nach gewünschtem Ablauf **Verschieben**, **Kopieren** oder **Nur Metadaten**. Lass **Herkunft im Ziel dokumentieren** aktiviert. Dadurch steht später in `.claude-project-origin.json`, von welchem Computer, Benutzer und Pfad das Projekt kam, wann und mit welcher Variante es übertragen wurde und ob die Nachprüfung erfolgreich war.

Bei Sessions ohne eigenen Projektordner zeigt die Übersicht zusätzlich sichere und sensible Session-Dateien. Sichere Bereiche werden in den neuen Projektordner kopiert. Claude-Hilfsdaten und Sitzungsverlauf landen in `.claude-session-bundle`; sensible oder systemgebundene Pfade werden nur angezeigt.

Zur leichteren Auswahl zeigt die Übersicht Zeitstempel, Sitzungsanzahl, Inhalt, bisherigen Pfad, Ordnerstatus und einen automatisch erzeugten Zielordner-Vorschlag. Der Vorschlag kann vor dem Anlegen geändert werden.

## Was vor dem Verschieben geprüft wird

Das Tool kontrolliert für jedes ausgewählte Projekt:

- Quellordner vorhanden und lesbar
- Projekt enthält Dateien
- gültige Claude-Code-JSONL-Sitzungsdaten vorhanden
- gespeicherte `cwd`-Pfade passen zum Quellordner
- keine beschädigten JSONL-Datensätze
- typische Projektmerkmale und Projekttypen
- Dateianzahl und Gesamtgröße
- freier Speicherplatz am Ziel
- Zielordner ist frei oder wurde bei einem Namenskonflikt ausdrücklich zur Übernahme bestätigt

Erkannte Merkmale umfassen unter anderem `.git`, `CLAUDE.md`, `.claude`, `package.json`, `pyproject.toml`, `requirements.txt`, `.sln`, `.csproj`, `pom.xml`, Gradle-Dateien, `go.mod`, `Cargo.toml`, `composer.json`, `Gemfile`, Dockerfile und Compose-Dateien.

## Statuswerte

| Status | Bedeutung |
| --- | --- |
| `NICHT GEPRÜFT` | Noch keine Prüfung durchgeführt |
| `OK` | Quelle und Claude-Metadaten sind plausibel |
| `WARNUNG` | Verwendbar, aber mit einem nicht kritischen Hinweis |
| `FEHLER` | Projekt wird nicht verschoben |

## Prüfung nach dem Verschieben

Vor der Bewegung wird ein Manifest aus relativen Dateipfaden und Dateigrößen erstellt. Nach dem Verschieben prüft das Tool:

- keine Datei fehlt
- keine Dateigröße weicht ab
- Dateianzahl stimmt überein
- Gesamtgröße stimmt überein

Danach werden die Claude-Code-Metadaten in einer Arbeitskopie aktualisiert, validiert und erst anschließend aktiviert. Bei einem Fehler versucht das Tool, den aktuell betroffenen Projektordner und die Metadaten zurückzusetzen.

## Mehrere Projekte

Mehrere Projekte werden nacheinander unterhalb eines gemeinsamen Zielordners abgelegt.

```text
Quelle:
C:\Users\Peter\Code\Projekt-A
C:\Users\Peter\Code\Projekt-B

Zielwurzel:
D:\Development

Ergebnis:
D:\Development\Projekt-A
D:\Development\Projekt-B
```

## Nur Metadaten aktualisieren

Sind die Projektordner bereits manuell verschoben worden, deaktiviere **Projektverzeichnisse physisch verschieben**. Die Zielordner müssen dann bereits vorhanden sein.

Direkter Start:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1 -NoProjectMove
```

## Häufige Startfehler

### Der Pfad wird als Befehl interpretiert

Falsch:

```powershell
C:\Users\Name\Downloads
```

Richtig:

```powershell
cd C:\Users\Name\Downloads
```

### Das Skript ist nicht digital signiert

Nutze den mitgelieferten Starter:

```powershell
.\Start-ClaudeProjectMover.cmd
```

### Keine Projekte werden angezeigt

Claude Code muss für das Projekt bereits Sitzungsmetadaten unter `%USERPROFILE%\.claude\projects` angelegt haben. Bei einer eigenen Konfiguration wird `CLAUDE_CONFIG_DIR` berücksichtigt.

## Wichtige Hinweise

- Claude Code vor der Migration schließen.
- Backup aktiviert lassen.
- Bestehende Zielordner werden nur nach ausdrücklicher Bestätigung verwendet; vorhandene Dateien werden nicht überschrieben.
- Bei Netzlaufwerken kann die Speicherplatzprüfung eingeschränkt sein.
- Mehrere Projekte werden nacheinander und nicht als eine gemeinsame Transaktion verarbeitet.
- Vor wichtigen Migrationen zuerst mit einem entbehrlichen Testprojekt prüfen.
