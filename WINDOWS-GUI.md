# Native Windows-Oberfläche

`claude-project-mover-gui.ps1` ist die interaktive Windows-Oberfläche zum sicheren Verschieben eines oder mehrerer Claude-Code-Projekte.

## Empfohlener Start

Starte im entpackten Projektordner:

```text
Start-ClaudeProjectMover.cmd
```

Am einfachsten ist ein Doppelklick im Windows Explorer. Alternativ:

```powershell
.\Start-ClaudeProjectMover.cmd
```

Direkter Start über PowerShell 7:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1
```

## Interaktiver Ablauf

1. Claude Code vollständig schließen.
2. Ein oder mehrere Quellprojekte in der Liste markieren.
3. Auf **Quellen prüfen** klicken.
4. Status, Projekttyp, Dateianzahl, Größe und Hinweise kontrollieren.
5. Einen gemeinsamen Zielordner auswählen.
6. **Projektverzeichnisse physisch verschieben** aktiviert lassen, wenn das Tool auch die echten Dateien bewegen soll.
7. Das ZIP-Backup der Claude-Metadaten aktiviert lassen.
8. Auf **Verschieben** klicken und den geprüften Plan bestätigen.

Beim Klick auf **Verschieben** wird die Quellenprüfung automatisch noch einmal ausgeführt. Ein Projekt mit dem Status **FEHLER** wird nicht verschoben.

## Was in der Quelle geprüft wird

Für jedes ausgewählte Projekt kontrolliert das Tool:

- ob der Quellordner vorhanden und vollständig lesbar ist
- ob der Ordner Dateien enthält
- ob gültige Claude-Code-JSONL-Sitzungsdaten vorhanden sind
- ob die in Claude Code gespeicherten `cwd`-Pfade zum Quellordner passen
- ob beschädigte JSONL-Datensätze vorhanden sind
- welche typischen Projektdateien und Projekttypen erkannt werden
- wie viele Dateien vorhanden sind und wie groß das Projekt insgesamt ist

Erkannte Projektmerkmale umfassen unter anderem:

- `.git`, `CLAUDE.md` und `.claude`
- `package.json` und Lock-Dateien für Node.js
- `pyproject.toml`, `requirements.txt` und `Pipfile` für Python
- `.sln`, `.csproj` und `.fsproj` für .NET
- `pom.xml` und Gradle-Dateien für Java
- `go.mod`, `Cargo.toml`, `composer.json` und `Gemfile`
- Dockerfile- und Compose-Dateien

Fehlen typische Projektmerkmale, wird eine Warnung angezeigt. Ein leerer, nicht lesbarer oder nicht zu den Claude-Sitzungen passender Ordner wird als Fehler blockiert.

## Prüfung nach dem Verschieben

Vor der Bewegung erstellt das Tool intern ein Manifest mit:

- relativem Dateipfad
- Dateigröße
- Dateianzahl
- Gesamtgröße

Nach dem Verschieben wird der Zielordner erneut geprüft. Der Vorgang gilt nur dann als erfolgreich, wenn:

- keine Datei fehlt
- keine Dateigröße abweicht
- Dateianzahl und Gesamtgröße mit der Quelle übereinstimmen

Schlägt diese Prüfung oder die anschließende Claude-Metadatenmigration fehl, versucht das Tool, das aktuell betroffene Projekt an seinen ursprünglichen Ort zurückzuschieben.

## Statusanzeige

| Status | Bedeutung |
| --- | --- |
| `NICHT GEPRÜFT` | Für dieses Projekt wurde noch keine Prüfung durchgeführt. |
| `OK` | Quelle, Claude-Metadaten und Projektdateien sind plausibel. |
| `WARNUNG` | Quelle ist verwendbar, aber es fehlen typische Projektmerkmale oder es gibt einen nicht kritischen Hinweis. |
| `FEHLER` | Das Projekt wird aus Sicherheitsgründen nicht verschoben. |

## Mehrere Projekte

Mehrere Projekte können gleichzeitig ausgewählt werden. Sie werden nacheinander unterhalb des gewählten gemeinsamen Zielordners abgelegt.

Beispiel:

```text
C:\Users\Peter\Code\Projekt-A
C:\Users\Peter\Code\Projekt-B
```

Zielordner:

```text
D:\Development
```

Ergebnis:

```text
D:\Development\Projekt-A
D:\Development\Projekt-B
```

Vor dem Start prüft das Tool zusätzlich, ob bereits gleichnamige Zielordner existieren und ob auf dem Ziellaufwerk genügend freier Speicher vorhanden ist.

## Nur Claude-Metadaten aktualisieren

Deaktiviere **Projektverzeichnisse physisch verschieben**, wenn die Projektordner bereits manuell an das Ziel verschoben wurden. Die erwarteten Zielordner müssen dann bereits existieren.

Direkter Start in diesem Modus:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1 -NoProjectMove
```

## Eigene Claude-Konfiguration

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1 -ClaudeConfigDirectory 'D:\ClaudeConfig'
```

## Einschränkungen

- Die Oberfläche benötigt Windows und Windows Forms.
- Alle ausgewählten Projekte werden unter einen gemeinsamen Zielordner verschoben.
- Bestehende Zielordner werden weder überschrieben noch zusammengeführt.
- Die Projekte werden nacheinander verarbeitet. Bereits erfolgreich abgeschlossene Projekte bleiben verschoben, wenn ein späteres Projekt fehlschlägt.
- Bei Netzlaufwerken kann die Ermittlung des freien Speicherplatzes technisch eingeschränkt sein.
- Die Dateiprüfung vergleicht Pfade, Anzahl und Dateigrößen. Sie berechnet bewusst nicht für jede Datei einen kryptografischen Hash, da dies bei großen Projekten den Ablauf erheblich verlangsamen würde.
