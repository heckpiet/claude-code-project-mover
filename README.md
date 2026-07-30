# Claude Code Project Mover

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Focus](https://img.shields.io/badge/focus-Windows-0078D4?logo=windows11&logoColor=white)](#projektfokus-windows)
[![Compatibility](https://img.shields.io/badge/compatibility-macOS%20%7C%20Linux-lightgrey)](#plattformen)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell validation](https://github.com/heckpiet/claude-code-project-mover/actions/workflows/powershell.yml/badge.svg)](https://github.com/heckpiet/claude-code-project-mover/actions/workflows/powershell.yml)

Verschiebt Claude-Code-Projekte an einen neuen Speicherort und aktualisiert die zugehörigen Sitzungs- und Projektmetadaten, damit vorhandene Unterhaltungen und Projektkontexte weiter genutzt werden können.

Aktuelle Version: **1.4.0**
## Projektfokus: Windows

Dieses Repository ist die **Windows-orientierte Weiterentwicklung** des Claude Code Project Movers. Entwicklung, Bedienkonzept, Dokumentation und Qualitätssicherung konzentrieren sich vorrangig auf Windows 10/11, Windows PowerShell 5.1, PowerShell 7 und die native Windows-Forms-Oberfläche.

Zum Windows-Schwerpunkt gehören insbesondere:

- komfortabler Start per CMD-Datei und native grafische Oberfläche
- vollständige PowerShell-Kommandozeile für manuelle und automatisierte Abläufe
- deutsche Windows-Dokumentation, verständliche Sicherheitsabfragen und korrekte UTF-8-Darstellung
- Mehrfachauswahl, Sitzungsübersicht, Quellenprüfung, Speicherplatzkontrolle, Backup und Rollback
- automatisierte Tests unter Windows PowerShell 5.1 und PowerShell 7

Das Bash-Skript für macOS und Linux bleibt als gepflegte Kompatibilitätsvariante enthalten. Neue Funktionen werden projektweit geprüft und dokumentiert; die umfassendste Oberfläche und der primäre Support gelten jedoch der Windows-Umsetzung.

## Schnellstart unter Windows

1. Über **Code → Download ZIP** den vollständigen Quellordner laden und entpacken oder das Repository mit Git klonen. Ein separates GitHub Release-Paket folgt nach Abschluss der Skriptarbeiten.
2. Claude Code und alle betroffenen Sitzungen schließen.
3. `Start-ClaudeProjectMover.cmd` doppelt anklicken.
4. Projekte auswählen und **Quellen prüfen** anklicken.
5. Zielordner auswählen, Backup aktiviert lassen und Verschiebung bestätigen.

```text
Start-ClaudeProjectMover.cmd
```

Der Starter verwendet PowerShell 7, sofern vorhanden, und ansonsten Windows PowerShell 5.1. `ExecutionPolicy Bypass` gilt nur für den gestarteten Prozess. Die globale PowerShell-Konfiguration wird nicht verändert.

Eine ausführliche deutschsprachige Anleitung steht in [START-HERE.md](START-HERE.md). Details zur Oberfläche stehen in [WINDOWS-GUI.md](WINDOWS-GUI.md).

## Funktionsumfang

### Interaktive Windows-Oberfläche

- native Windows-Forms-Oberfläche
- Auswahl eines oder mehrerer Claude-Code-Projekte
- nach letzter Aktivität sortierte Übersicht mit Zeitstempel, Sitzungsanzahl und Kurzbeschreibung
- sichtbarer Ordnerstatus und intelligenter Zielordner-Vorschlag aus Sitzungstitel oder Inhalt
- Projekte direkt per Checkbox an- und abwählen
- gemeinsamer Zielordner über den Windows-Ordnerdialog
- optionales physisches Verschieben der echten Projektordner
- eigener, frei benennbarer Ziel-Projektordner für Sitzungsgruppen, die bisher nur in einem allgemeinen Ordner lagen
- reiner Metadatenmodus für bereits manuell verschobene Projekte
- Statusanzeige mit Projekttyp, Dateianzahl und Größe
- sichtbare Warnungen und Fehler vor der Migration

### Quellenprüfung

Vor dem Verschieben kontrolliert das Tool für jedes Projekt:

- Quellordner existiert und ist vollständig lesbar
- Projekt enthält Dateien
- Claude-Code-Metadaten und JSONL-Sitzungen sind vorhanden
- JSON- und JSONL-Daten sind syntaktisch gültig
- gespeicherte `cwd`-Pfade passen zum ausgewählten Quellordner
- typische Projektmerkmale und Projekttypen werden erkannt
- Dateianzahl und Gesamtgröße werden ermittelt
- Zielpfad ist frei und kollidiert nicht mit vorhandenen Ordnern

Erkannte Merkmale umfassen unter anderem:

- Git und Claude: `.git`, `CLAUDE.md`, `.claude`
- Node.js: `package.json` und Lock-Dateien
- Python: `pyproject.toml`, `requirements.txt`, `Pipfile`
- .NET: `.sln`, `.csproj`, `.fsproj`
- Java: `pom.xml`, Gradle-Dateien
- Go, Rust, PHP und Ruby: `go.mod`, `Cargo.toml`, `composer.json`, `Gemfile`
- Docker: Dockerfile- und Compose-Dateien

Fehlende typische Projektmerkmale erzeugen nur eine Warnung, weil auch einfache Claude-Code-Projekte gültig sein können. Leere, nicht lesbare oder nicht zu den Claude-Sitzungen passende Ordner werden blockiert.

### Prüfung nach dem Verschieben

Vor der Bewegung erstellt die Oberfläche ein Manifest mit relativen Dateipfaden und Dateigrößen. Nach dem Verschieben wird kontrolliert:

- keine Datei fehlt
- keine Dateigröße weicht ab
- Dateianzahl stimmt überein
- Gesamtgröße stimmt überein

Die Dateiprüfung verwendet bewusst keine kryptografischen Hashes für jede Datei, damit auch große Projekte praktikabel verarbeitet werden können.

### Claude-Code-Metadaten

Die PowerShell-Engine:

- erkennt das Standardverzeichnis `~/.claude/projects`
- berücksichtigt `CLAUDE_CONFIG_DIR`
- zeigt die zuletzt verwendeten Claude-Code-Sitzungen mit lokalem Datum und Uhrzeit
- verwendet den von Claude erzeugten Sitzungstitel oder ersatzweise die erste Benutzernachricht als Kurzbeschreibung
- liest den bisherigen Projektpfad aus den Sitzungsdaten
- prüft JSON- und JSONL-Dateien vor der Änderung
- aktualisiert normale, JSON-escapte und mit `/` gespeicherte Pfadvarianten
- bearbeitet die Metadaten zunächst in einer Arbeitskopie
- validiert die aktualisierten Daten vor der Aktivierung
- verwendet beim finalen Austausch einen Rollback-Ordner
- kann ein ZIP-Backup der Claude-Metadaten erstellen

## Statusanzeige

| Status | Bedeutung |
| --- | --- |
| `NICHT GEPRÜFT` | Für das Projekt wurde noch keine Prüfung durchgeführt. |
| `OK` | Quelle, Projektdateien und Claude-Metadaten sind plausibel. |
| `WARNUNG` | Das Projekt ist verwendbar, enthält aber einen nicht kritischen Hinweis. |
| `FEHLER` | Das Projekt wird aus Sicherheitsgründen nicht verschoben. |

## Mehrere Projekte verschieben

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

Vor dem Start prüft das Tool die Gesamtgröße, den verfügbaren Speicherplatz und mögliche Namenskollisionen.

## Startmöglichkeiten

### Empfohlener Windows-Start

```powershell
.\Start-ClaudeProjectMover.cmd
```

### Direkter Start mit PowerShell 7

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1
```

### Nur Metadaten aktualisieren

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1 -NoProjectMove
```

### Eigene Claude-Konfiguration

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1 -ClaudeConfigDirectory 'D:\ClaudeConfig'
```

## PowerShell-Kommandozeile

Die grafische Oberfläche verwendet `claude-project-mover.ps1` als sichere Migrationsengine. Das Skript kann auch direkt für Automatisierung oder einzelne Projekte verwendet werden.

Beim Start zeigt das Skript einen kompakten Kopfbereich mit Zweck, Autor, Projektlink und der Version des tatsächlich ausgeführten Skripts.

### Letzte Claude-Code-Sitzungen anzeigen

```powershell
.\claude-project-mover.ps1 -ListSessions -LastSessions 20
```

Dieser reine Lesemodus durchsucht das konfigurierte Claude-Verzeichnis (`CLAUDE_CONFIG_DIR` oder standardmäßig `~/.claude/projects`). Die Ausgabe wird nach der letzten Aktivität sortiert und enthält Projektpfad, lokalen Zeitstempel, Kurzbeschreibung und Sitzungs-ID. Wenn Claude keinen KI-generierten Titel gespeichert hat, wird die erste sinnvolle Benutzernachricht gekürzt als Beschreibung verwendet.

Wird das CLI ohne `-ProjectPath` gestartet, verwendet die Projektauswahl dieselben Inventardaten wie die GUI: letzte Sitzung, Sitzungsanzahl, Kurzbeschreibung und vollständiger Pfad. Damit lässt sich ein unbekannter Ordner vor der Auswahl einordnen.

Beim Zielpfad muss der **vollständige neue Projektordner** angegeben werden, nicht nur ein übergeordneter Sammelordner. Kann das interaktive CLI dort keine typische Projektdatei erkennen, erklärt es die Warnung und lässt unmittelbar einen anderen Pfad eingeben oder die Auswahl bewusst bestätigen. Automatisierte Aufrufe bleiben streng und benötigen in diesem Fall weiterhin `-Force`.

Erkennt das interaktive CLI, dass eine Sitzungsgruppe bisher keinen eigenen Projektordner besitzt, fragt es standardmäßig nach der Anlage eines neuen Ordners. In diesem Modus wird ein vorhandener Ziel-Sammelordner plus ein neuer Projektname eingegeben. Der allgemeine Quellordner wird nicht verschoben. Das Skript legt den neuen Ordner an, aktualisiert sämtliche gespeicherten Pfadvarianten in den Claude-Metadaten und prüft anschließend Ordner, Metadatenverzeichnis, JSON/JSONL-Daten und `cwd`-Verweise.

### Intelligente Ordnernamenvorschläge

Projektübersicht und Auswahldialog zeigen letzte Sitzung, Sitzungsanzahl, KI-Titel oder Sitzungsinhalt, bisherigen Pfad, Ordnerstatus und Zielordner-Vorschlag. Der Vorschlag verwendet bis zu acht aussagekräftige Wörter, entfernt einleitende Füllwörter sowie ungültige Dateinamenzeichen und begrenzt die Länge. Fehlt verwertbarer Inhalt, werden Zeitstempel und ein gekürzter Sitzungsbezeichner verwendet. Vor der Anlage kann der Name immer bearbeitet werden.

### Projektübersicht ohne Migration

```powershell
.\claude-project-mover.ps1 -ListProjects
```

Dieser reine Lesemodus zeigt alle erkannten Projekte nach letzter Aktivität sortiert an und beendet das Skript anschließend. Die Übersicht funktioniert auch dann, wenn nur die einzelne `claude-project-mover.ps1` kopiert wurde; mit dem mitgelieferten Inventarmodul verwenden GUI und CLI vollständig dieselbe Erkennungslogik.

### Reiner Prüfmodus

```powershell
.\claude-project-mover.ps1 `
  -ProjectPath 'C:\Code\AltesProjekt' `
  -NewPath 'D:\Projekte\AltesProjekt' `
  -CheckOnly
```

### Migration mit Backup

```powershell
.\claude-project-mover.ps1 `
  -ProjectPath 'C:\Code\AltesProjekt' `
  -NewPath 'D:\Projekte\AltesProjekt' `
  -Backup `
  -Yes
```

### Parameter

| Parameter | Beschreibung |
| --- | --- |
| `-ProjectPath` | Bisheriger absoluter Projektpfad |
| `-NewPath` | Neuer absoluter Projektpfad |
| `-CreateProjectFolder` | Behandelt `-NewPath` als Ziel-Sammelordner und legt einen eigenen Projektordner an |
| `-ProjectFolderName` | Name des mit `-CreateProjectFolder` anzulegenden Projektordners |
| `-Backup` | Erstellt vor der Änderung ein ZIP-Backup |
| `-Yes` | Überspringt Rückfragen für automatisierte Aufrufe |
| `-CheckOnly` | Führt alle Vorprüfungen ohne Änderungen durch |
| `-MinimumFreeSpaceGB` | Mindestfreiraum am Ziel, Standard `1` GB |
| `-SkipSpaceCheck` | Überspringt die Speicherplatzprüfung, etwa bei problematischen UNC-Pfaden |
| `-Force` | Erlaubt das Fortsetzen bei nicht kritischen Projektwarnungen |
| `-ListSessions` | Zeigt die zuletzt verwendeten Claude-Code-Sitzungen an und beendet das Skript ohne Änderungen |
| `-ListProjects` | Zeigt alle erkannten Projekte mit Zeitstempel, Sitzungsanzahl, Beschreibung und Pfad an |
| `-LastSessions` | Begrenzt die Sitzungsliste; Standard `10`, Maximum `1000` |
| `-WhatIf` | Zeigt die geplante Änderung ohne Ausführung |

## Speicherplatzprüfung

Es werden zwei Bereiche betrachtet:

1. Das Ziellaufwerk des echten Projektordners muss ausreichend freien Speicher und Sicherheitsreserve besitzen.
2. Das Laufwerk mit `.claude/projects` muss genügend Platz für Arbeitskopie, temporäre Daten und optionales ZIP-Backup bieten.

Bei UNC-Pfaden oder bestimmten Netzlaufwerken kann die .NET-basierte Abfrage technisch eingeschränkt sein.

## Sicherer Migrationsablauf

1. Quelle und Claude-Code-Metadaten prüfen
2. Zielpfad und freien Speicher kontrollieren
3. optionales ZIP-Backup erstellen
4. Claude-Metadaten in eine Arbeitskopie kopieren
5. Pfade nur in der Arbeitskopie aktualisieren
6. aktualisierte JSON- und JSONL-Daten validieren
7. ursprüngliche Metadaten als Rollback-Version umbenennen
8. geprüfte Arbeitskopie aktivieren
9. Ergebnis erneut validieren
10. Rollback-Version nach erfolgreichem Abschluss entfernen

Schlägt die Aktivierung fehl, versucht das Skript den vorherigen Metadatenzustand wiederherzustellen. Die GUI versucht zusätzlich, den aktuell betroffenen Projektordner zurück an die Quelle zu verschieben.

## Plattformen

| Plattform | Datei | Umfang |
| --- | --- | --- |
| **Windows 10/11 (Primärplattform)** | `Start-ClaudeProjectMover.cmd` | empfohlener Start für GUI, CLI und Projektübersicht |
| **Windows 10/11 (Primärplattform)** | `claude-project-mover-gui.ps1` | native Oberfläche und Mehrfachauswahl |
| **Windows 10/11 (Primärplattform)** | `claude-project-mover.ps1` | vollständige Kommandozeile und Migrationsengine |
| macOS (Kompatibilität) | `claude-project-mover.sh` | Bash-Ablauf mit Sitzungsübersicht |
| Linux (Kompatibilität) | `claude-project-mover.sh` | Bash-Ablauf mit Sitzungsübersicht |

## Versionierung und Releases

Das Projekt verwendet [Semantic Versioning](https://semver.org/lang/de/) im Format `MAJOR.MINOR.PATCH`:

- `MAJOR`: inkompatible Änderungen am Verhalten oder an Parametern
- `MINOR`: neue, abwärtskompatible Funktionen
- `PATCH`: abwärtskompatible Fehlerbehebungen

Die Datei `VERSION` ist die zentrale Projektversion. Dieselbe Version ist in `claude-project-mover.ps1`, `claude-project-mover.sh` und `Start-ClaudeProjectMover.cmd` eingebettet, damit sie auch bei einem direkten Aufruf korrekt angezeigt wird. Die GitHub-Actions-Prüfung schlägt fehl, sobald ein Einstiegspunkt oder die README davon abweicht.

GUI und CLI beziehen ihre Projekt- und Sitzungsübersicht gemeinsam aus `ClaudeProjectInventory.psm1`. Änderungen an Erkennung, Zeitstempeln oder Beschreibungen gelten dadurch für beide Oberflächen.

Bei jeder Änderung:

1. Änderung unter `Unreleased` in `CHANGELOG.md` dokumentieren.
2. Vor einem Release die Version mit `.\scripts\Update-Version.ps1 -Part Major|Minor|Patch` erhöhen.
3. Die Release-Einträge unter eine datierte Versionsüberschrift verschieben.
4. Nach dem Merge einen Git-Tag `vMAJOR.MINOR.PATCH` und ein gleichnamiges GitHub Release erstellen.

Beispiele:

```powershell
# Neues abwärtskompatibles Feature: 1.0.0 -> 1.1.0
.\scripts\Update-Version.ps1 -Part Minor

# Abwärtskompatibler Bugfix: 1.1.0 -> 1.1.1
.\scripts\Update-Version.ps1 -Part Patch
```

## Bash-Version des Originalprojekts

```bash
chmod +x claude-project-mover.sh
./claude-project-mover.sh
./claude-project-mover.sh --list-projects
```

Die Bash-Übersicht zeigt den letzten Sitzungszeitpunkt, die Sitzungsanzahl, eine bestmögliche Kurzbeschreibung und den Projektpfad. Mit installiertem `python3` werden Beschreibungen robuster aus JSONL gelesen; ohne Python bleibt die Übersicht vollständig nutzbar und verwendet einen neutralen Beschreibungstext.

Ist `fzf` installiert, wird eine Fuzzy-Auswahl verwendet. Andernfalls zeigt das Skript eine nummerierte Liste an.

## Voraussetzungen

### Windows

- Windows PowerShell 5.1 oder PowerShell 7+
- Claude Code mit mindestens einem gespeicherten Projekt
- Lesezugriff auf die Quellprojekte
- Schreibzugriff auf Ziel und Claude-Konfigurationsverzeichnis
- Windows Forms für die grafische Oberfläche

### macOS und Linux

- Bash
- Claude Code und `~/.claude/projects`
- optional `fzf`

## Wichtige Hinweise und Grenzen

- Claude Code vor der Migration vollständig schließen.
- Für wichtige Sitzungsverläufe das Backup aktiviert lassen.
- Bestehende Zielordner werden nicht überschrieben oder zusammengeführt.
- Mehrere Projekte werden nacheinander und nicht als eine gemeinsame Transaktion verarbeitet.
- Bereits erfolgreich abgeschlossene Projekte bleiben verschoben, wenn ein späteres Projekt fehlschlägt.
- Die Metadatenstruktur von Claude Code ist nicht vollständig dokumentiert und kann sich künftig ändern.
- Bei Netzlaufwerken kann die Speicherplatzprüfung eingeschränkt sein.
- Vor unersetzbaren Migrationen zuerst ein entbehrliches Testprojekt verwenden.

## Projektstruktur

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/
│   ├── workflows/bash.yml
│   ├── workflows/powershell.yml
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   └── pull_request_template.md
├── Start-ClaudeProjectMover.cmd
├── START-HERE.md
├── WINDOWS-GUI.md
├── claude-project-mover-gui.ps1
├── claude-project-mover.ps1
├── claude-project-mover.sh
├── tests/
│   ├── Test-FolderSuggestions.ps1
│   └── Test-FolderlessMigration.ps1
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── README.md
```

## Originalprojekt und Attribution

Dieses Repository ist ein Fork von [`skydiver/claude-code-project-mover`](https://github.com/skydiver/claude-code-project-mover).

Das Originalprojekt von Martin führte den Bash-basierten Ansatz ein, um Claude-Code-Projektreferenzen nach einer Verzeichnisverschiebung zu reparieren. Das ursprüngliche Skript, die zugehörigen Informationen und die MIT-Lizenz bleiben erhalten. Die PowerShell-Version, die Windows-Oberfläche sowie die zusätzlichen Prüf-, Backup- und Rollback-Funktionen werden in diesem Fork ergänzt.

## Sicherheit

Claude-Code-Sitzungsdateien können lokale Pfade, Prompts, Antworten, Quellcode und Tool-Ausgaben enthalten. Solche Dateien oder vollständige `.claude`-Ordner nicht ungefiltert in öffentliche Issues hochladen. Weitere Hinweise stehen in [SECURITY.md](SECURITY.md).

## Mitwirken

Fehlerberichte und Pull Requests sind willkommen. Bitte Betriebssystem, PowerShell-Version, Claude-Code-Version, alte und neue Pfade sowie bereinigte Diagnoseausgaben angeben. Weitere Informationen stehen in [CONTRIBUTING.md](CONTRIBUTING.md).

## Lizenz

MIT. Der ursprüngliche Copyright- und Lizenzhinweis bleibt in [LICENSE](LICENSE) erhalten.
