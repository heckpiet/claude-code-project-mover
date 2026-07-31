#requires -Version 5.1

<#
.SYNOPSIS
Interaktive Windows-Oberfläche zum sicheren Verschieben von Claude-Code-Projekten.

.START
Empfohlen: Start-ClaudeProjectMover.cmd per Doppelklick starten.
Alternativ:
  pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1

.NUTZUNG
1. Claude Code schließen.
2. Ein oder mehrere Projekte auswählen.
3. Auf "Quellen prüfen" klicken und das Prüfergebnis kontrollieren.
4. Einen gemeinsamen Zielordner auswählen.
5. Übertragungsart wählen, Backup, Herkunftsdokumentation und Session-Paket aktiviert lassen.
6. Sichere Session-Dateien prüfen und "Ausführen" anklicken.

.PRÜFUNG
Das Tool gleicht den Quellpfad mit Claude-Code-Sitzungsdaten ab, sucht typische
Projektdateien und Session-Artefakte, prüft Lesbarkeit, Dateianzahl und Größe,
sichert Claude-Hilfsdaten portabel und verifiziert das Ziel.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ClaudeConfigDirectory,

    [Parameter()]
    [switch]$NoProjectMove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.8.0'
if ($env:OS -ne 'Windows_NT') {
    throw 'Die native Oberfläche benötigt Windows. Auf anderen Plattformen bitte claude-project-mover.ps1 verwenden.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

$inventoryModulePath = Join-Path $PSScriptRoot 'ClaudeProjectInventory.psm1'
if (Test-Path -LiteralPath $inventoryModulePath -PathType Leaf) {
    Import-Module -Name $inventoryModulePath -Force
}

function Get-ClaudeConfigPath {
    if (-not [string]::IsNullOrWhiteSpace($ClaudeConfigDirectory)) {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ClaudeConfigDirectory))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($env:CLAUDE_CONFIG_DIR))
    }
    return Join-Path $HOME '.claude'
}

function ConvertTo-SafeProjectFolderName {
    param([Parameter(Mandatory)][string]$Name)
    $cleanName = $Name.Trim()
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $cleanName = $cleanName.Replace([string]$character, '-')
    }
    return (($cleanName -replace '\s+', '-').Trim('.', '-', ' '))
}

function Test-IsGeneralSourcePath {
    param([Parameter(Mandatory)][string]$Path)
    $normalized = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $candidates = @(
        $HOME,
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path $HOME 'Downloads'),
        $env:OneDrive,
        $env:OneDriveConsumer,
        $env:OneDriveCommercial
    )
    return @($candidates | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and [System.IO.Path]::GetFullPath($_).TrimEnd('\') -ieq $normalized
    }).Count -gt 0
}

function Get-SmartProjectFolderSuggestion {
    param(
        [Parameter()][AllowNull()][string]$Description,
        [Parameter(Mandatory)][datetime]$LastActivity,
        [Parameter()][AllowNull()][string]$SessionId
    )
    $candidate = Format-SessionDescription -Text $Description -MaximumLength 100
    if ($candidate -in @('(no description available)', '(keine Beschreibung verfügbar)')) { $candidate = '' }
    $candidate = [regex]::Replace($candidate, '^(bitte|kannst du|ich möchte|ich will|erstelle|baue|prüfe|schau(?:e)?(?: mal)?)\s+', '', 'IgnoreCase')
    $words = @([regex]::Matches($candidate, '[\p{L}\p{Nd}]+') | ForEach-Object { $_.Value } | Select-Object -First 8)
    $suggestion = ($words -join '-').ToLowerInvariant()
    if ($suggestion.Length -gt 56) { $suggestion = $suggestion.Substring(0, 56).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($suggestion)) {
        $shortSession = if ([string]::IsNullOrWhiteSpace($SessionId)) { 'session' } else { $SessionId.Substring(0, [Math]::Min(8, $SessionId.Length)) }
        $suggestion = 'claude-projekt-{0}-{1}' -f $LastActivity.ToString('yyyyMMdd-HHmm'), $shortSession
    }
    return $suggestion
}

function ConvertTo-SessionMessageText {
    param([Parameter()][AllowNull()]$Message)

    if ($null -eq $Message) { return $null }
    if ($Message -is [string]) { return $Message }
    if ($Message.PSObject.Properties.Name -notcontains 'content') { return $null }

    if ($Message.content -is [string]) { return [string]$Message.content }
    $textParts = foreach ($part in @($Message.content)) {
        if ($null -eq $part) { continue }
        if ($part -is [string]) { $part; continue }
        if ($part.PSObject.Properties.Name -contains 'type' -and [string]$part.type -ne 'text') { continue }
        if ($part.PSObject.Properties.Name -contains 'text') { [string]$part.text }
    }
    return ($textParts -join ' ')
}

function Format-SessionDescription {
    param(
        [Parameter()][AllowNull()][string]$Text,
        [Parameter()][int]$MaximumLength = 140
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '(keine Beschreibung verfügbar)' }
    $cleanText = [regex]::Replace($Text, '<system-reminder>.*?</system-reminder>', ' ', 'Singleline,IgnoreCase')
    $cleanText = [regex]::Replace($cleanText, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($cleanText)) { return '(keine Beschreibung verfügbar)' }
    if ($cleanText.Length -le $MaximumLength) { return $cleanText }
    return $cleanText.Substring(0, $MaximumLength - 1).TrimEnd() + [char]0x2026
}

function Get-CwdValuesFromJsonl {
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$Files)

    $values = New-Object System.Collections.Generic.List[string]
    $sessions = New-Object System.Collections.Generic.List[object]
    $validRecords = 0
    $invalidRecords = 0
    foreach ($file in $Files) {
        $latestTimestamp = $null
        $title = $null
        $firstUserMessage = $null

        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $record = $line | ConvertFrom-Json -ErrorAction Stop
                $validRecords++
                if ($record.PSObject.Properties.Name -contains 'cwd' -and
                    -not [string]::IsNullOrWhiteSpace([string]$record.cwd)) {
                    [void]$values.Add([System.IO.Path]::GetFullPath([string]$record.cwd))
                }

                if ($record.PSObject.Properties.Name -contains 'timestamp' -and
                    -not [string]::IsNullOrWhiteSpace([string]$record.timestamp)) {
                    $parsedTimestamp = [datetimeoffset]::MinValue
                    if ([datetimeoffset]::TryParse(
                            [string]$record.timestamp,
                            [Globalization.CultureInfo]::InvariantCulture,
                            [Globalization.DateTimeStyles]::AssumeUniversal,
                            [ref]$parsedTimestamp) -and
                        ($null -eq $latestTimestamp -or $parsedTimestamp -gt $latestTimestamp)) {
                        $latestTimestamp = $parsedTimestamp
                    }
                }

                if ([string]::IsNullOrWhiteSpace($title) -and
                    $record.PSObject.Properties.Name -contains 'aiTitle' -and
                    -not [string]::IsNullOrWhiteSpace([string]$record.aiTitle)) {
                    $title = [string]$record.aiTitle
                }

                $isMeta = $record.PSObject.Properties.Name -contains 'isMeta' -and [bool]$record.isMeta
                if ([string]::IsNullOrWhiteSpace($firstUserMessage) -and -not $isMeta -and
                    $record.PSObject.Properties.Name -contains 'type' -and
                    [string]$record.type -eq 'user' -and
                    $record.PSObject.Properties.Name -contains 'message') {
                    $candidate = ConvertTo-SessionMessageText -Message $record.message
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) { $firstUserMessage = $candidate }
                }
            }
            catch { $invalidRecords++ }
        }

        $activity = if ($null -ne $latestTimestamp) {
            $latestTimestamp.ToLocalTime().DateTime
        }
        else {
            $file.LastWriteTime
        }
        $description = if (-not [string]::IsNullOrWhiteSpace($title)) { $title } else { $firstUserMessage }
        [void]$sessions.Add([pscustomobject]@{
            LastActivity = $activity
            Description = Format-SessionDescription -Text $description
            SessionId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        })
    }

    return [pscustomobject]@{
        Values = @($values | Select-Object -Unique)
        ValidRecords = $validRecords
        InvalidRecords = $invalidRecords
        Sessions = @($sessions | Sort-Object LastActivity -Descending)
    }
}

function Get-ClaudeProjects {
    param([Parameter(Mandatory)][string]$ProjectsDirectory)

    if (Get-Command -Name Get-ClaudeProjectInventory -ErrorAction SilentlyContinue) {
        return @(Get-ClaudeProjectInventory -ProjectsDirectory $ProjectsDirectory)
    }

    $items = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory -ErrorAction Stop) {
        if ($directory.Name -match '^(BACKUP__|\.MIGRATION__|\.ROLLBACK__)') { continue }
        $jsonlFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue)
        if ($jsonlFiles.Count -eq 0) { continue }

        $sessionData = Get-CwdValuesFromJsonl -Files $jsonlFiles
        if ($sessionData.Values.Count -eq 0) { continue }
        $sourcePath = $sessionData.Values[0]
        $latestSession = $sessionData.Sessions | Select-Object -First 1

        [pscustomobject]@{
            DisplayName = $sourcePath
            SourcePath = $sourcePath
            MetadataPath = $directory.FullName
            JsonlFiles = $jsonlFiles
            SessionData = $sessionData
            SessionCount = $sessionData.Sessions.Count
            LastSession = $latestSession.LastActivity
            Description = $latestSession.Description
            Validation = $null
        }
    }
    return @($items | Sort-Object LastSession -Descending)
}

function Get-ProjectMarkers {
    param([Parameter(Mandatory)][string]$Path)

    $definitions = [ordered]@{
        'Git' = @('.git')
        'Claude' = @('CLAUDE.md', '.claude')
        'Node.js' = @('package.json', 'pnpm-lock.yaml', 'yarn.lock', 'package-lock.json')
        'Python' = @('pyproject.toml', 'requirements.txt', 'Pipfile', 'setup.py')
        '.NET' = @('*.sln', '*.csproj', '*.fsproj')
        'Java' = @('pom.xml', 'build.gradle', 'build.gradle.kts')
        'Go' = @('go.mod')
        'Rust' = @('Cargo.toml')
        'PHP' = @('composer.json')
        'Ruby' = @('Gemfile')
        'Docker' = @('Dockerfile', 'docker-compose.yml', 'compose.yml')
    }

    $types = New-Object System.Collections.Generic.List[string]
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($type in $definitions.Keys) {
        foreach ($pattern in $definitions[$type]) {
            $match = $null
            if ($pattern.Contains('*')) {
                $match = Get-ChildItem -LiteralPath $Path -File -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            else {
                $candidate = Join-Path $Path $pattern
                if (Test-Path -LiteralPath $candidate) { $match = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue }
            }
            if ($null -ne $match) {
                if (-not $types.Contains($type)) { [void]$types.Add($type) }
                [void]$files.Add($pattern)
            }
        }
    }

    return [pscustomobject]@{ Types = @($types); Files = @($files | Select-Object -Unique) }
}

function Get-SourceManifest {
    param([Parameter(Mandatory)][string]$Path)

    $entries = New-Object System.Collections.Generic.List[object]
    $bytes = [long]0
    $root = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\')
        $bytes += $file.Length
        [void]$entries.Add([pscustomobject]@{
            RelativePath = $relative
            Length = [long]$file.Length
            LastWriteTimeUtc = $file.LastWriteTimeUtc
        })
    }
    return [pscustomobject]@{ Entries = @($entries); FileCount = $entries.Count; Bytes = $bytes }
}

function Test-SourceProject {
    param([Parameter(Mandatory)][object]$Project)

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $manifest = $null
    $markers = [pscustomobject]@{ Types = @(); Files = @() }

    if (-not (Test-Path -LiteralPath $Project.SourcePath -PathType Container)) {
        [void]$errors.Add('Quellordner existiert nicht.')
    }
    else {
        try { $manifest = Get-SourceManifest -Path $Project.SourcePath }
        catch { [void]$errors.Add('Quellordner kann nicht vollständig gelesen werden: ' + $_.Exception.Message) }

        try { $markers = Get-ProjectMarkers -Path $Project.SourcePath }
        catch { [void]$warnings.Add('Projektmerkmale konnten nicht vollständig ermittelt werden.') }
    }

    if ($null -ne $manifest -and $manifest.FileCount -eq 0) {
        [void]$errors.Add('Der Quellordner enthält keine Dateien.')
    }
    if ($markers.Types.Count -eq 0) {
        [void]$warnings.Add('Keine typische Projektdatei gefunden. Bitte Quelle besonders sorgfältig prüfen.')
    }
    if ($Project.JsonlFiles.Count -eq 0 -or $Project.SessionData.ValidRecords -eq 0) {
        [void]$errors.Add('Keine gültigen Claude-Code-Sitzungsdaten vorhanden.')
    }
    if ($Project.SessionData.InvalidRecords -gt 0) {
        [void]$errors.Add("$($Project.SessionData.InvalidRecords) ungültige JSONL-Datensätze gefunden.")
    }

    $normalizedSource = $null
    try { $normalizedSource = [System.IO.Path]::GetFullPath($Project.SourcePath).TrimEnd('\') }
    catch { [void]$errors.Add('Quellpfad ist ungültig.') }

    $pathMatch = $false
    if ($null -ne $normalizedSource) {
        foreach ($cwd in $Project.SessionData.Values) {
            try {
                if ([System.IO.Path]::GetFullPath($cwd).TrimEnd('\') -ieq $normalizedSource) { $pathMatch = $true; break }
            }
            catch { }
        }
    }
    if (-not $pathMatch) {
        [void]$errors.Add('Claude-Code-Metadaten verweisen nicht eindeutig auf diesen Quellordner.')
    }

    $status = if ($errors.Count -gt 0) { 'FEHLER' } elseif ($warnings.Count -gt 0) { 'WARNUNG' } else { 'OK' }
    return [pscustomobject]@{
        Status = $status
        Errors = @($errors)
        Warnings = @($warnings)
        Manifest = $manifest
        Markers = $markers
        PathMatch = $pathMatch
    }
}

function Test-DestinationManifest {
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][string]$Destination
    )

    $missing = New-Object System.Collections.Generic.List[string]
    $different = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Manifest.Entries) {
        $target = Join-Path $Destination $entry.RelativePath
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            [void]$missing.Add($entry.RelativePath)
            continue
        }
        $targetFile = Get-Item -LiteralPath $target -ErrorAction Stop
        if ([long]$targetFile.Length -ne [long]$entry.Length) { [void]$different.Add($entry.RelativePath) }
    }

    $targetManifest = Get-SourceManifest -Path $Destination
    return [pscustomobject]@{
        Complete = ($missing.Count -eq 0 -and $different.Count -eq 0 -and $targetManifest.FileCount -eq $Manifest.FileCount -and $targetManifest.Bytes -eq $Manifest.Bytes)
        Missing = @($missing)
        Different = @($different)
        TargetManifest = $targetManifest
    }
}

function Find-PriorProjectTransfers {
    param(
        [Parameter(Mandatory)][string]$SearchRoot,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string[]]$SessionIds
    )
    $normalizedSource = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\', '/')
    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($file in Get-ChildItem -LiteralPath $SearchRoot -Filter '.claude-project-origin.json' -File -Recurse -ErrorAction SilentlyContinue) {
        try {
            $manifest = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json -ErrorAction Stop
            $found = @($manifest.transfers | Where-Object {
                $_.PSObject.Properties.Name -contains 'source' -and
                $_.source.PSObject.Properties.Name -contains 'path' -and
                [System.IO.Path]::GetFullPath([string]$_.source.path).TrimEnd('\', '/') -ieq $normalizedSource
            }).Count -gt 0
            if ($found) { [void]$matches.Add("$(Split-Path -Parent $file.FullName) – gleicher Quellpfad") }
        }
        catch { }
    }
    foreach ($file in Get-ChildItem -LiteralPath $SearchRoot -Filter 'manifest.json' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq '.claude-session-bundle' }) {
        try {
            $manifest = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json -ErrorAction Stop
            $count = @($SessionIds | Where-Object { $_ -in @($manifest.sessions) }).Count
            if ($count -gt 0) { [void]$matches.Add("$(Split-Path -Parent $file.Directory.FullName) – $count identische Session-ID(s)") }
        }
        catch { }
    }
    return @($matches | Sort-Object -Unique)
}

function Get-AvailableBytes {
    param([Parameter(Mandatory)][string]$Path)
    $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
    if ([string]::IsNullOrWhiteSpace($root) -or $root.StartsWith('\\')) { return $null }
    $drive = New-Object System.IO.DriveInfo($root)
    if (-not $drive.IsReady) { return $null }
    return [long]$drive.AvailableFreeSpace
}

function Format-Bytes {
    param([Parameter(Mandatory)][long]$Bytes)
    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}

function Set-ButtonStyle {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Button]$Button,
        [Parameter()][switch]$Primary
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 1
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Primary.IsPresent) {
        $Button.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
        $Button.ForeColor = [System.Drawing.Color]::White
        $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    }
    else {
        $Button.BackColor = [System.Drawing.Color]::White
        $Button.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 55)
        $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(209, 213, 219)
    }
}

$configPath = Get-ClaudeConfigPath
$projectsPath = Join-Path $configPath 'projects'
$coreScript = Join-Path $PSScriptRoot 'claude-project-mover.ps1'
$versionFile = Join-Path $PSScriptRoot 'VERSION'
$projectVersion = if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
    (Get-Content -LiteralPath $versionFile -Raw).Trim()
}
elseif (Test-Path -LiteralPath $coreScript -PathType Leaf) {
    $coreContent = [System.IO.File]::ReadAllText($coreScript)
    $coreVersionMatch = [regex]::Match($coreContent, "(?m)^\`$ScriptVersion = '([^']+)'\s*$")
    if ($coreVersionMatch.Success) { $coreVersionMatch.Groups[1].Value } else { $ScriptVersion }
}
else {
    $ScriptVersion
}
if (-not (Test-Path -LiteralPath $projectsPath -PathType Container)) { throw "Claude-Code-Projektverzeichnis nicht gefunden: '$projectsPath'." }
if (-not (Test-Path -LiteralPath $coreScript -PathType Leaf)) { throw "Migrationsskript nicht gefunden: '$coreScript'." }
$projects = @(Get-ClaudeProjects -ProjectsDirectory $projectsPath)
if ($projects.Count -eq 0) { throw 'Keine Claude-Code-Projekte mit lesbaren Sitzungsdaten gefunden.' }
foreach ($project in $projects) {
    if ($project.PSObject.Properties.Name -notcontains 'SuggestedFolderName') {
        $needsFolder = Test-IsGeneralSourcePath -Path $project.SourcePath
        $latestId = if ($project.SessionData.Sessions.Count -gt 0) { $project.SessionData.Sessions[0].SessionId } else { $null }
        $suggestion = Get-SmartProjectFolderSuggestion -Description $project.Description -LastActivity $project.LastSession -SessionId $latestId
        $project | Add-Member -NotePropertyName NeedsDedicatedFolder -NotePropertyValue $needsFolder
        $project | Add-Member -NotePropertyName FolderStatus -NotePropertyValue $(if ($needsFolder) { 'ORDNER FEHLT' } else { 'Eigener Ordner' })
        $project | Add-Member -NotePropertyName SuggestedFolderName -NotePropertyValue $suggestion
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Claude Code Project Mover v$projectVersion"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1420, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1100, 680)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 94
$header.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Claude Code Projekte sicher verschieben - v$projectVersion"
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$title.ForeColor = [System.Drawing.Color]::White
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(24, 15)
$header.Controls.Add($title)

$description = New-Object System.Windows.Forms.Label
$description.Text = 'Letzte Sitzungen prüfen, Projekte per Checkbox auswählen, Quellen validieren und anschließend verschieben.'
$description.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
$description.AutoSize = $true
$description.Location = New-Object System.Drawing.Point(27, 50)
$header.Controls.Add($description)

$projectLink = New-Object System.Windows.Forms.LinkLabel
$projectLink.Text = 'heckpiet | GitHub-Projekt'
$projectLink.LinkColor = [System.Drawing.Color]::FromArgb(147, 197, 253)
$projectLink.ActiveLinkColor = [System.Drawing.Color]::White
$projectLink.AutoSize = $true
$projectLink.Anchor = 'Top,Right'
$projectLink.Location = New-Object System.Drawing.Point(1235, 52)
$projectLink.Add_LinkClicked({ Start-Process 'https://github.com/heckpiet/claude-code-project-mover' })
$header.Controls.Add($projectLink)

$overviewLabel = New-Object System.Windows.Forms.Label
$overviewLabel.Text = "$($projects.Count) Projekte gefunden | nach letzter Sitzung sortiert"
$overviewLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$overviewLabel.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
$overviewLabel.AutoSize = $true
$overviewLabel.Location = New-Object System.Drawing.Point(24, 106)
$form.Controls.Add($overviewLabel)

$list = New-Object System.Windows.Forms.ListView
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.GridLines = $true
$list.View = [System.Windows.Forms.View]::Details
$list.Anchor = 'Top,Left,Right,Bottom'
$list.Location = New-Object System.Drawing.Point(24, 130)
$list.Size = New-Object System.Drawing.Size(1355, 305)
$list.ShowItemToolTips = $true
$list.HideSelection = $false
$list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$list.BackColor = [System.Drawing.Color]::White
$list.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
[void]$list.Columns.Add('Status', 90)
[void]$list.Columns.Add('Letzte Sitzung', 140)
[void]$list.Columns.Add('Sessions', 75)
[void]$list.Columns.Add('Ordnerstatus', 115)
[void]$list.Columns.Add('Zielordner-Vorschlag', 210)
[void]$list.Columns.Add('Beschreibung', 285)
[void]$list.Columns.Add('Quellprojekt', 300)
[void]$list.Columns.Add('Session-Dateien', 135)
[void]$list.Columns.Add('Typ', 120)
[void]$list.Columns.Add('Dateien', 70)
[void]$list.Columns.Add('Größe', 90)
foreach ($project in $projects) {
    $item = New-Object System.Windows.Forms.ListViewItem('NICHT GEPRÜFT')
    [void]$item.SubItems.Add($project.LastSession.ToString('dd.MM.yyyy HH:mm'))
    [void]$item.SubItems.Add([string]$project.SessionCount)
    [void]$item.SubItems.Add($project.FolderStatus)
    [void]$item.SubItems.Add($(if ($project.NeedsDedicatedFolder) { $project.SuggestedFolderName } else { '-' }))
    [void]$item.SubItems.Add($project.Description)
    [void]$item.SubItems.Add($project.SourcePath)
    [void]$item.SubItems.Add(('{0} sicher / {1} sensibel' -f $project.SafeArtifactCount, $project.SensitiveArtifactCount))
    [void]$item.SubItems.Add('-')
    [void]$item.SubItems.Add('-')
    [void]$item.SubItems.Add('-')
    $item.ToolTipText = "Beschreibung: $($project.Description)`r`nLetzte Sitzung: $($project.LastSession.ToString('dd.MM.yyyy HH:mm'))`r`nSessions: $($project.SessionCount)`r`nSichere Session-Bereiche: $($project.SafeArtifactCount)`r`nSensible Pfade: $($project.SensitiveArtifactCount)`r`nOrdnerstatus: $($project.FolderStatus)`r`nVorschlag: $($project.SuggestedFolderName)`r`nQuelle: $($project.SourcePath)"
    $item.Tag = $project
    [void]$list.Items.Add($item)
}
$form.Controls.Add($list)

$selectAll = New-Object System.Windows.Forms.Button
$selectAll.Text = 'Alle auswählen'
$selectAll.Location = New-Object System.Drawing.Point(24, 448)
$selectAll.Size = New-Object System.Drawing.Size(110, 30)
$selectAll.Add_Click({ foreach ($item in $list.Items) { $item.Checked = $true } })
Set-ButtonStyle -Button $selectAll
$form.Controls.Add($selectAll)

$clear = New-Object System.Windows.Forms.Button
$clear.Text = 'Auswahl löschen'
$clear.Location = New-Object System.Drawing.Point(142, 448)
$clear.Size = New-Object System.Drawing.Size(120, 30)
$clear.Add_Click({ foreach ($item in $list.Items) { $item.Checked = $false } })
Set-ButtonStyle -Button $clear
$form.Controls.Add($clear)

$validate = New-Object System.Windows.Forms.Button
$validate.Text = 'Quellen prüfen'
$validate.Location = New-Object System.Drawing.Point(270, 448)
$validate.Size = New-Object System.Drawing.Size(125, 30)
Set-ButtonStyle -Button $validate -Primary
$form.Controls.Add($validate)

$selectionLabel = New-Object System.Windows.Forms.Label
$selectionLabel.Text = '0 Projekte ausgewählt'
$selectionLabel.AutoSize = $true
$selectionLabel.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$selectionLabel.Location = New-Object System.Drawing.Point(414, 456)
$form.Controls.Add($selectionLabel)
$list.Add_ItemChecked({
    $checkedCount = $list.CheckedItems.Count
    if (-not $_.Item.Checked) { $checkedCount++ } else { $checkedCount-- }
    $selectionLabel.Text = "$checkedCount Projekte ausgewählt"
})

$details = New-Object System.Windows.Forms.TextBox
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.Anchor = 'Left,Right,Bottom'
$details.Location = New-Object System.Drawing.Point(24, 490)
$details.Size = New-Object System.Drawing.Size(1355, 82)
$details.Text = 'Wähle Projekte anhand von Zeitstempel und Beschreibung aus und klicke auf "Quellen prüfen".'
$details.BackColor = [System.Drawing.Color]::White
$details.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($details)

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = 'Gemeinsamer Zielordner'
$targetLabel.AutoSize = $true
$targetLabel.Location = New-Object System.Drawing.Point(24, 592)
$targetLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$form.Controls.Add($targetLabel)

$targetText = New-Object System.Windows.Forms.TextBox
$targetText.Anchor = 'Left,Right,Bottom'
$targetText.Location = New-Object System.Drawing.Point(24, 614)
$targetText.Size = New-Object System.Drawing.Size(1220, 25)
$form.Controls.Add($targetText)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Durchsuchen ...'
$browse.Anchor = 'Right,Bottom'
$browse.Location = New-Object System.Drawing.Point(1254, 611)
$browse.Size = New-Object System.Drawing.Size(125, 30)
$browse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Gemeinsamen Zielordner auswählen'
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $targetText.Text = $dialog.SelectedPath }
    $dialog.Dispose()
})
Set-ButtonStyle -Button $browse
$form.Controls.Add($browse)

$fileOperationLabel = New-Object System.Windows.Forms.Label
$fileOperationLabel.Text = 'Projektdateien:'
$fileOperationLabel.AutoSize = $true
$fileOperationLabel.Location = New-Object System.Drawing.Point(24, 657)
$form.Controls.Add($fileOperationLabel)

$fileOperation = New-Object System.Windows.Forms.ComboBox
$fileOperation.DropDownStyle = 'DropDownList'
[void]$fileOperation.Items.AddRange(@('Verschieben', 'Kopieren', 'Nur Metadaten'))
$fileOperation.SelectedItem = if ($NoProjectMove.IsPresent) { 'Nur Metadaten' } else { 'Verschieben' }
$fileOperation.Location = New-Object System.Drawing.Point(120, 651)
$fileOperation.Size = New-Object System.Drawing.Size(150, 28)
$form.Controls.Add($fileOperation)

$backup = New-Object System.Windows.Forms.CheckBox
$backup.Text = 'Claude-Metadaten als ZIP sichern'
$backup.Checked = $true
$backup.AutoSize = $true
$backup.Location = New-Object System.Drawing.Point(300, 654)
$form.Controls.Add($backup)

$originMetadata = New-Object System.Windows.Forms.CheckBox
$originMetadata.Text = 'Herkunft im Ziel dokumentieren'
$originMetadata.Checked = $true
$originMetadata.AutoSize = $true
$originMetadata.Location = New-Object System.Drawing.Point(535, 654)
$form.Controls.Add($originMetadata)

$sessionBundle = New-Object System.Windows.Forms.CheckBox
$sessionBundle.Text = 'Session-Paket sichern'
$sessionBundle.Checked = $true
$sessionBundle.AutoSize = $true
$sessionBundle.Location = New-Object System.Drawing.Point(760, 654)
$form.Controls.Add($sessionBundle)

$sessionArtifacts = New-Object System.Windows.Forms.CheckBox
$sessionArtifacts.Text = 'Sichere Session-Dateien kopieren'
$sessionArtifacts.Checked = $true
$sessionArtifacts.AutoSize = $true
$sessionArtifacts.Location = New-Object System.Drawing.Point(930, 654)
$form.Controls.Add($sessionArtifacts)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Bereit'
$status.Anchor = 'Left,Right,Bottom'
$status.Location = New-Object System.Drawing.Point(24, 707)
$status.Size = New-Object System.Drawing.Size(730, 25)
$status.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$form.Controls.Add($status)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Abbrechen'
$cancel.Anchor = 'Right,Bottom'
$cancel.Location = New-Object System.Drawing.Point(1140, 700)
$cancel.Size = New-Object System.Drawing.Size(105, 34)
$cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
Set-ButtonStyle -Button $cancel
$form.Controls.Add($cancel)
$form.CancelButton = $cancel

$move = New-Object System.Windows.Forms.Button
$move.Text = 'Ausführen'
$move.Anchor = 'Right,Bottom'
$move.Location = New-Object System.Drawing.Point(1254, 700)
$move.Size = New-Object System.Drawing.Size(125, 34)
Set-ButtonStyle -Button $move -Primary
$form.Controls.Add($move)
$form.AcceptButton = $move

$validateAction = {
    $selectedItems = @($list.Items | Where-Object { $_.Checked })
    if ($selectedItems.Count -eq 0) { throw 'Bitte mindestens ein Projekt auswählen.' }
    $messages = New-Object System.Collections.Generic.List[string]
    foreach ($item in $selectedItems) {
        $status.Text = "Prüfe $($item.Tag.SourcePath)"
        [System.Windows.Forms.Application]::DoEvents()
        $result = Test-SourceProject -Project $item.Tag
        $item.Tag.Validation = $result
        $item.SubItems[0].Text = $result.Status
        $item.SubItems[8].Text = if ($result.Markers.Types.Count -gt 0) { $result.Markers.Types -join ', ' } else { 'Unbekannt' }
        $item.SubItems[9].Text = if ($null -ne $result.Manifest) { [string]$result.Manifest.FileCount } else { '-' }
        $item.SubItems[10].Text = if ($null -ne $result.Manifest) { Format-Bytes $result.Manifest.Bytes } else { '-' }
        if ($result.Status -eq 'FEHLER') { $item.ForeColor = [System.Drawing.Color]::DarkRed }
        elseif ($result.Status -eq 'WARNUNG') { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
        else { $item.ForeColor = [System.Drawing.Color]::DarkGreen }

        [void]$messages.Add("[$($result.Status)] $($item.Tag.SourcePath)")
        if ($result.Markers.Files.Count -gt 0) { [void]$messages.Add('  Projektdateien: ' + ($result.Markers.Files -join ', ')) }
        foreach ($error in $result.Errors) { [void]$messages.Add('  FEHLER: ' + $error) }
        foreach ($warning in $result.Warnings) { [void]$messages.Add('  Hinweis: ' + $warning) }
    }
    $details.Text = $messages -join "`r`n"
    $status.Text = 'Quellenprüfung abgeschlossen.'
}

$validate.Add_Click({
    try { & $validateAction }
    catch { [void][System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Prüfung nicht möglich', 'OK', 'Warning') }
})

$list.Add_SelectedIndexChanged({
    if ($list.SelectedItems.Count -eq 1) {
        $project = $list.SelectedItems[0].Tag
        if ($null -ne $project.Validation) {
            $lines = @("Status: $($project.Validation.Status)", "Quelle: $($project.SourcePath)")
            if ($project.Validation.Markers.Files.Count -gt 0) { $lines += 'Projektdateien: ' + ($project.Validation.Markers.Files -join ', ') }
            $lines += $project.Validation.Errors | ForEach-Object { 'FEHLER: ' + $_ }
            $lines += $project.Validation.Warnings | ForEach-Object { 'Hinweis: ' + $_ }
            $details.Text = $lines -join "`r`n"
        }
    }
})

$move.Add_Click({
    try {
        & $validateAction
        $selectedItems = @($list.Items | Where-Object { $_.Checked })
        $blocking = @($selectedItems | Where-Object { $_.Tag.Validation.Status -eq 'FEHLER' })
        if ($blocking.Count -gt 0) { throw 'Mindestens eine Quelle hat einen Fehler. Verschieben wurde aus Sicherheitsgründen blockiert.' }

        $targetRoot = $targetText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($targetRoot) -or -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
            throw 'Bitte einen vorhandenen Zielordner auswählen.'
        }
        $targetRoot = [System.IO.Path]::GetFullPath($targetRoot)
        $selectedOperation = [string]$fileOperation.SelectedItem

        $plan = New-Object System.Collections.Generic.List[object]
        $requiredBytes = [long]0
        foreach ($item in $selectedItems) {
            $project = $item.Tag
            $dedicatedFolder = $project.NeedsDedicatedFolder
            $adoptExistingFolder = $false
            $leaf = Split-Path -Path $project.SourcePath -Leaf
            if ($dedicatedFolder) {
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    $form,
                    "Für diese Sitzungsgruppe wurde kein eigener Projektordner erkannt:`r`n$($project.SourcePath)`r`n`r`nAm Ziel einen eigenen Projektordner anlegen?",
                    'Eigenen Projektordner anlegen',
                    'YesNo',
                    'Question'
                )
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                    throw 'Der Vorgang wurde abgebrochen. Für ordnerlose Sitzungsgruppen ist ein eigener Ziel-Projektordner erforderlich.'
                }
                $defaultName = $project.SuggestedFolderName
                while ($true) {
                    $leaf = [Microsoft.VisualBasic.Interaction]::InputBox(
                        'Name des neuen Projektordners:',
                        'Projektordner benennen',
                        $defaultName
                    )
                    $leaf = ConvertTo-SafeProjectFolderName -Name $leaf
                    if ([string]::IsNullOrWhiteSpace($leaf)) { throw 'Es wurde kein gültiger Projektordnername angegeben.' }
                    $destination = Join-Path $targetRoot $leaf
                    if (-not (Test-Path -LiteralPath $destination)) { break }
                    $conflict = [System.Windows.Forms.MessageBox]::Show(
                        $form,
                        "Der vorgeschlagene Projektordner existiert bereits:`r`n$destination`r`n`r`nJa: vorhandenen Ordner verwenden`r`nNein: anderen Namen wählen`r`nAbbrechen: Vorgang beenden",
                        'Projektordner bereits vorhanden',
                        'YesNoCancel',
                        'Question'
                    )
                    if ($conflict -eq [System.Windows.Forms.DialogResult]::Yes) {
                        $adoptExistingFolder = $true
                        break
                    }
                    if ($conflict -eq [System.Windows.Forms.DialogResult]::Cancel) {
                        throw 'Der Vorgang wurde abgebrochen.'
                    }
                    $defaultName = $leaf + '-2'
                }
            }
            $destination = Join-Path $targetRoot $leaf
            if (($dedicatedFolder -and -not $adoptExistingFolder) -or
                (-not $dedicatedFolder -and $selectedOperation -in @('Verschieben', 'Kopieren'))) {
                if (Test-Path -LiteralPath $destination) { throw "Ziel existiert bereits: $destination" }
            }
            elseif (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                throw "Zielprojekt existiert nicht: $destination"
            }
            if (-not $dedicatedFolder -and $selectedOperation -in @('Verschieben', 'Kopieren')) { $requiredBytes += $project.Validation.Manifest.Bytes }
            [void]$plan.Add([pscustomobject]@{
                Project = $project
                Destination = $destination
                TargetRoot = $targetRoot
                FolderName = $leaf
                CreateDedicatedFolder = ($dedicatedFolder -and -not $adoptExistingFolder)
                AdoptExistingFolder = $adoptExistingFolder
                FolderlessSession = $dedicatedFolder
            })
        }

        if ($selectedOperation -in @('Verschieben', 'Kopieren')) {
            $available = Get-AvailableBytes -Path $targetRoot
            if ($null -ne $available) {
                $required = [long][Math]::Max(1GB, $requiredBytes * 1.1)
                if ($available -lt $required) { throw "Nicht genügend Speicher. Benötigt: $(Format-Bytes $required), verfügbar: $(Format-Bytes $available)." }
            }
        }

        $repeatApproved = @{}
        foreach ($entry in $plan) {
            $sessionIds = @($entry.Project.JsonlFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
            $prior = @(Find-PriorProjectTransfers -SearchRoot $targetRoot -SourcePath $entry.Project.SourcePath -SessionIds $sessionIds)
            if ($prior.Count -eq 0) { continue }
            $answer = [System.Windows.Forms.MessageBox]::Show(
                $form,
                "Dieses Projekt oder eine seiner Sessions wurde im Ziel bereits gefunden:`r`n`r`n$($prior -join "`r`n")`r`n`r`nTrotzdem erneut übertragen?",
                'Frühere Übertragung erkannt',
                'YesNo',
                'Warning'
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                throw 'Der Vorgang wurde abgebrochen, weil das Projekt am Ziel bereits vorhanden ist.'
            }
            $repeatApproved[$entry.Project.SourcePath] = $true
        }

        $summary = ($plan | ForEach-Object {
            $mode = if ($_.CreateDedicatedFolder) {
                'neuer eigener Projektordner mit Session-Dateien und portablem Bundle'
            }
            elseif ($_.AdoptExistingFolder) {
                'vorhandener Projektordner wird verwendet und um Session-Dateien sowie Bundle ergänzt'
            }
            else {
                "$($_.Project.Validation.Manifest.FileCount) Dateien, $(Format-Bytes $_.Project.Validation.Manifest.Bytes)"
            }
            "$($_.Project.SourcePath)`r`n  -> $($_.Destination)`r`n  $mode"
        }) -join "`r`n`r`n"
        $answer = [System.Windows.Forms.MessageBox]::Show($form, "Geprüfter Verschiebeplan:`r`n`r`n$summary`r`n`r`nFortfahren?", 'Verschieben bestätigen', 'YesNo', 'Question')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $form.UseWaitCursor = $true
        $move.Enabled = $false
        $completed = 0
        foreach ($entry in $plan) {
            $source = $entry.Project.SourcePath
            $destination = $entry.Destination
            $manifest = $entry.Project.Validation.Manifest
            $moved = $false
            $copied = $false
            try {
                $status.Text = "$selectedOperation`: $source"
                [System.Windows.Forms.Application]::DoEvents()
                if ($entry.CreateDedicatedFolder -or $entry.AdoptExistingFolder) {
                    $status.Text = if ($entry.CreateDedicatedFolder) {
                        "Lege eigenen Projektordner für $source an"
                    }
                    else {
                        "Übernehme vorhandenen Projektordner für $source"
                    }
                }
                elseif ($selectedOperation -eq 'Verschieben') {
                    Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
                    $moved = $true
                    $verification = Test-DestinationManifest -Manifest $manifest -Destination $destination
                    if (-not $verification.Complete) {
                        throw "Dateiprüfung am Ziel fehlgeschlagen. Fehlend: $($verification.Missing.Count), abweichend: $($verification.Different.Count)."
                    }
                }
                elseif ($selectedOperation -eq 'Kopieren') {
                    Copy-Item -LiteralPath $source -Destination $destination -Recurse -ErrorAction Stop
                    $copied = $true
                    $verification = Test-DestinationManifest -Manifest $manifest -Destination $destination
                    if (-not $verification.Complete) {
                        throw "Dateiprüfung der Kopie fehlgeschlagen. Fehlend: $($verification.Missing.Count), abweichend: $($verification.Different.Count)."
                    }
                }
                elseif (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                    throw "Zielprojekt existiert nicht: $destination"
                }

                $arguments = @{ ProjectPath = $source; NewPath = $destination; Yes = $true }
                $arguments.TransferMode = if ($entry.CreateDedicatedFolder) {
                    'CreateFolder'
                }
                elseif ($entry.AdoptExistingFolder) {
                    'MetadataOnly'
                }
                elseif ($selectedOperation -eq 'Verschieben') {
                    'Move'
                }
                elseif ($selectedOperation -eq 'Kopieren') {
                    'Copy'
                }
                else {
                    'MetadataOnly'
                }
                if ($entry.CreateDedicatedFolder) {
                    $arguments.NewPath = $entry.TargetRoot
                    $arguments.CreateProjectFolder = $true
                    $arguments.ProjectFolderName = $entry.FolderName
                }
                elseif ($entry.AdoptExistingFolder) {
                    $arguments.AdoptExistingProjectFolder = $true
                }
                if ($repeatApproved.ContainsKey($entry.Project.SourcePath)) {
                    $arguments.AllowRepeatedTransfer = $true
                }
                if ($backup.Checked) { $arguments.Backup = $true }
                if (-not $originMetadata.Checked) { $arguments.NoOriginMetadata = $true }
                if (-not $sessionBundle.Checked) { $arguments.NoSessionBundle = $true }
                if (-not $sessionArtifacts.Checked) { $arguments.NoArtifactCopy = $true }
                & $coreScript @arguments
                $completed++
            }
            catch {
                if ($moved -and (Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $source)) {
                    try { Move-Item -LiteralPath $destination -Destination $source -ErrorAction Stop }
                    catch { Write-Warning "Rollback fehlgeschlagen: $($_.Exception.Message)" }
                }
                elseif ($copied -and (Test-Path -LiteralPath $destination -PathType Container)) {
                    try { Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop }
                    catch { Write-Warning "Kopier-Rollback fehlgeschlagen: $($_.Exception.Message)" }
                }
                throw
            }
        }

        $status.Text = "$completed Projekt(e) erfolgreich geprüft und verarbeitet."
        [void][System.Windows.Forms.MessageBox]::Show($form, "$completed Projekt(e) wurden vollständig geprüft, verarbeitet und mit Claude Code verknüpft.", 'Abgeschlossen', 'OK', 'Information')
        $form.Close()
    }
    catch {
        $status.Text = 'Fehler'
        [void][System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Vorgang abgebrochen', 'OK', 'Error')
    }
    finally {
        $form.UseWaitCursor = $false
        $move.Enabled = $true
    }
})

[void]$form.ShowDialog()
$form.Dispose()
