# Native Windows-Oberfläche

`claude-project-mover-gui.ps1` ist die interaktive Windows-Oberfläche zum sicheren Verschieben eines oder mehrerer Claude-Code-Projekte.

Die Windows-Umsetzung ist der Schwerpunkt dieses Repositorys. Oberfläche, PowerShell-Engine, CMD-Starter, deutsche Dokumentation und CI-Prüfungen werden gemeinsam für Windows 10/11 sowie Windows PowerShell 5.1 und PowerShell 7 gepflegt.

Die Oberfläche verwendet UTF-8 mit BOM, damit deutsche Texte auch unter Windows PowerShell 5.1 korrekt dargestellt werden.

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
2. Zeitstempel, Sitzungsanzahl und Kurzbeschreibung der gefundenen Projekte prüfen.
3. Ein oder mehrere Quellprojekte über die Checkboxen an- oder abwählen.
4. Auf **Quellen prüfen** klicken.
5. Status, Projekttyp, Dateianzahl, Größe und Hinweise kontrollieren.
6. Einen gemeinsamen Zielordner auswählen.
7. **Verschieben**, **Kopieren** oder **Nur Metadaten** auswählen.
8. Das ZIP-Backup der Claude-Metadaten aktiviert lassen.
9. **Herkunft im Ziel dokumentieren** aktiviert lassen.
10. Auf **Ausführen** klicken und den geprüften Plan bestätigen.

Beim Klick auf **Ausführen** wird die Quellenprüfung automatisch noch einmal ausgeführt. Ein Projekt mit dem Status **FEHLER** wird nicht verarbeitet.

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

Mehrere Projekte können gleichzeitig über Checkboxen ausgewählt werden. Die Übersicht ist nach der letzten Claude-Code-Sitzung sortiert und zeigt:

- Datum und Uhrzeit der letzten Sitzung
- Anzahl der gespeicherten Sitzungen
- den von Claude erzeugten Titel oder ersatzweise die erste sinnvolle Benutzernachricht
- den vollständigen Projektpfad

Mit **Alle auswählen** und **Auswahl löschen** lässt sich die Auswahl schnell umschalten. Die ausgewählten Projekte werden nacheinander unterhalb des gewählten gemeinsamen Zielordners abgelegt.

Die GUI und die PowerShell-Kommandozeile verwenden dasselbe Inventarmodul. Zeitstempel, Sitzungsanzahl und Kurzbeschreibung werden daher in beiden Oberflächen nach denselben Regeln ermittelt.

Bei der Zielauswahl gibt es einen bewussten Unterschied: Die GUI erwartet einen gemeinsamen Sammelordner und erzeugt darin je Projekt einen Unterordner. Die direkte PowerShell-Kommandozeile erwartet bereits den vollständigen Ziel-Projektordner und führt bei unklaren Projektmerkmalen durch eine erneute Auswahl.

### Sitzungsgruppe ohne eigenen Projektordner

Fehlen im bisherigen Pfad typische Projektmerkmale, fragt die GUI, ob am Ziel ein eigener Projektordner angelegt werden soll. Nach Eingabe eines eindeutigen Namens wird ein leerer Zielordner erstellt und die komplette Claude-Sitzungsgruppe dorthin umgebunden. Der bisherige allgemeine Ordner wird nicht physisch verschoben. Die Nachprüfung kontrolliert den neuen Ordner, das neue Claude-Metadatenverzeichnis, alle JSON/JSONL-Datensätze und die aktualisierten `cwd`-Werte.

Die Projektliste zeigt dafür zusätzlich **Ordnerstatus** und **Zielordner-Vorschlag**. Der Namensdialog ist mit dem Vorschlag aus KI-Titel oder erstem sinnvollen Sitzungsinhalt vorausgefüllt. Zeitstempel, Sitzungsanzahl, Beschreibung, Pfad und Vorschlag bleiben gleichzeitig sichtbar, damit ähnliche Sitzungsgruppen leichter unterschieden werden können.

## Herkunftsdatei im Ziel

Die standardmäßig aktivierte Option **Herkunft im Ziel dokumentieren** erzeugt `.claude-project-origin.json`. Sie enthält Computer, Benutzer, Quellpfad, Zeitpunkt, Übertragungsart, Tool-Version, technische Projekt- und Sitzungszählwerte sowie das Ergebnis der Nachprüfung. Bei späteren Übertragungen wird die Historie ergänzt. Sitzungsinhalte, Zugangsdaten, IP-Adressen, Hardware-IDs und Windows-SIDs werden nicht gespeichert.

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
