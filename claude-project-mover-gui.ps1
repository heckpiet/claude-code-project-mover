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
5. Backup aktiviert lassen und "Verschieben" anklicken.

.PRÜFUNG
Das Tool gleicht den Quellpfad mit Claude-Code-Sitzungsdaten ab, sucht typische
Projektdateien, prüft Lesbarkeit, Dateianzahl und Größe und verifiziert nach dem
Verschieben, dass alle erfassten Dateien vollständig am Ziel vorhanden sind.
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

if ($env:OS -ne 'Windows_NT') {
    throw 'Die native Oberfläche benötigt Windows. Auf anderen Plattformen bitte claude-project-mover.ps1 verwenden.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-ClaudeConfigPath {
    if (-not [string]::IsNullOrWhiteSpace($ClaudeConfigDirectory)) {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ClaudeConfigDirectory))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($env:CLAUDE_CONFIG_DIR))
    }
    return Join-Path $HOME '.claude'
}

function Get-CwdValuesFromJsonl {
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$Files)

    $values = New-Object System.Collections.Generic.List[string]
    $validRecords = 0
    $invalidRecords = 0
    foreach ($file in $Files) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $record = $line | ConvertFrom-Json -ErrorAction Stop
                $validRecords++
                if ($record.PSObject.Properties.Name -contains 'cwd' -and
                    -not [string]::IsNullOrWhiteSpace([string]$record.cwd)) {
                    [void]$values.Add([System.IO.Path]::GetFullPath([string]$record.cwd))
                }
            }
            catch { $invalidRecords++ }
        }
    }

    return [pscustomobject]@{
        Values = @($values | Select-Object -Unique)
        ValidRecords = $validRecords
        InvalidRecords = $invalidRecords
    }
}

function Get-ClaudeProjects {
    param([Parameter(Mandatory)][string]$ProjectsDirectory)

    $items = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory -ErrorAction Stop) {
        if ($directory.Name -match '^(BACKUP__|\.MIGRATION__|\.ROLLBACK__)') { continue }
        $jsonlFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue)
        if ($jsonlFiles.Count -eq 0) { continue }

        $sessionData = Get-CwdValuesFromJsonl -Files $jsonlFiles
        if ($sessionData.Values.Count -eq 0) { continue }
        $sourcePath = $sessionData.Values[0]

        [pscustomobject]@{
            DisplayName = $sourcePath
            SourcePath = $sourcePath
            MetadataPath = $directory.FullName
            JsonlFiles = $jsonlFiles
            SessionData = $sessionData
            Validation = $null
        }
    }
    return @($items | Sort-Object DisplayName)
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

$configPath = Get-ClaudeConfigPath
$projectsPath = Join-Path $configPath 'projects'
$coreScript = Join-Path $PSScriptRoot 'claude-project-mover.ps1'
if (-not (Test-Path -LiteralPath $projectsPath -PathType Container)) { throw "Claude-Code-Projektverzeichnis nicht gefunden: '$projectsPath'." }
if (-not (Test-Path -LiteralPath $coreScript -PathType Leaf)) { throw "Migrationsskript nicht gefunden: '$coreScript'." }
$projects = Get-ClaudeProjects -ProjectsDirectory $projectsPath
if ($projects.Count -eq 0) { throw 'Keine Claude-Code-Projekte mit lesbaren Sitzungsdaten gefunden.' }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Claude Code Project Mover'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1080, 760)
$form.MinimumSize = New-Object System.Drawing.Size(900, 650)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Claude Code Projekte sicher verschieben'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 16)
$form.Controls.Add($title)

$description = New-Object System.Windows.Forms.Label
$description.Text = 'Projekte auswählen, Quellen prüfen, Zielordner festlegen und erst danach verschieben.'
$description.AutoSize = $true
$description.Location = New-Object System.Drawing.Point(23, 50)
$form.Controls.Add($description)

$list = New-Object System.Windows.Forms.ListView
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.GridLines = $true
$list.View = [System.Windows.Forms.View]::Details
$list.Anchor = 'Top,Left,Right,Bottom'
$list.Location = New-Object System.Drawing.Point(24, 82)
$list.Size = New-Object System.Drawing.Size(1015, 345)
[void]$list.Columns.Add('Status', 80)
[void]$list.Columns.Add('Quellprojekt', 500)
[void]$list.Columns.Add('Typ', 160)
[void]$list.Columns.Add('Dateien', 80)
[void]$list.Columns.Add('Größe', 100)
foreach ($project in $projects) {
    $item = New-Object System.Windows.Forms.ListViewItem('NICHT GEPRÜFT')
    [void]$item.SubItems.Add($project.SourcePath)
    [void]$item.SubItems.Add('-')
    [void]$item.SubItems.Add('-')
    [void]$item.SubItems.Add('-')
    $item.Tag = $project
    [void]$list.Items.Add($item)
}
$form.Controls.Add($list)

$selectAll = New-Object System.Windows.Forms.Button
$selectAll.Text = 'Alle auswählen'
$selectAll.Location = New-Object System.Drawing.Point(24, 438)
$selectAll.Size = New-Object System.Drawing.Size(110, 30)
$selectAll.Add_Click({ foreach ($item in $list.Items) { $item.Checked = $true } })
$form.Controls.Add($selectAll)

$clear = New-Object System.Windows.Forms.Button
$clear.Text = 'Auswahl löschen'
$clear.Location = New-Object System.Drawing.Point(142, 438)
$clear.Size = New-Object System.Drawing.Size(120, 30)
$clear.Add_Click({ foreach ($item in $list.Items) { $item.Checked = $false } })
$form.Controls.Add($clear)

$validate = New-Object System.Windows.Forms.Button
$validate.Text = 'Quellen prüfen'
$validate.Location = New-Object System.Drawing.Point(270, 438)
$validate.Size = New-Object System.Drawing.Size(125, 30)
$form.Controls.Add($validate)

$details = New-Object System.Windows.Forms.TextBox
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.Anchor = 'Left,Right,Bottom'
$details.Location = New-Object System.Drawing.Point(24, 478)
$details.Size = New-Object System.Drawing.Size(1015, 82)
$details.Text = 'Wähle Projekte aus und klicke auf "Quellen prüfen".'
$form.Controls.Add($details)

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = 'Gemeinsamer Zielordner'
$targetLabel.AutoSize = $true
$targetLabel.Location = New-Object System.Drawing.Point(24, 574)
$form.Controls.Add($targetLabel)

$targetText = New-Object System.Windows.Forms.TextBox
$targetText.Anchor = 'Left,Right,Bottom'
$targetText.Location = New-Object System.Drawing.Point(24, 596)
$targetText.Size = New-Object System.Drawing.Size(880, 25)
$form.Controls.Add($targetText)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Durchsuchen ...'
$browse.Anchor = 'Right,Bottom'
$browse.Location = New-Object System.Drawing.Point(914, 593)
$browse.Size = New-Object System.Drawing.Size(125, 30)
$browse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Gemeinsamen Zielordner auswählen'
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $targetText.Text = $dialog.SelectedPath }
    $dialog.Dispose()
})
$form.Controls.Add($browse)

$moveFiles = New-Object System.Windows.Forms.CheckBox
$moveFiles.Text = 'Projektverzeichnisse physisch verschieben'
$moveFiles.Checked = -not $NoProjectMove.IsPresent
$moveFiles.AutoSize = $true
$moveFiles.Location = New-Object System.Drawing.Point(24, 635)
$form.Controls.Add($moveFiles)

$backup = New-Object System.Windows.Forms.CheckBox
$backup.Text = 'Claude-Metadaten als ZIP sichern'
$backup.Checked = $true
$backup.AutoSize = $true
$backup.Location = New-Object System.Drawing.Point(310, 635)
$form.Controls.Add($backup)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Bereit'
$status.Anchor = 'Left,Right,Bottom'
$status.Location = New-Object System.Drawing.Point(24, 677)
$status.Size = New-Object System.Drawing.Size(730, 25)
$form.Controls.Add($status)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Abbrechen'
$cancel.Anchor = 'Right,Bottom'
$cancel.Location = New-Object System.Drawing.Point(800, 670)
$cancel.Size = New-Object System.Drawing.Size(105, 34)
$cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancel)
$form.CancelButton = $cancel

$move = New-Object System.Windows.Forms.Button
$move.Text = 'Verschieben'
$move.Anchor = 'Right,Bottom'
$move.Location = New-Object System.Drawing.Point(914, 670)
$move.Size = New-Object System.Drawing.Size(125, 34)
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
        $item.SubItems[2].Text = if ($result.Markers.Types.Count -gt 0) { $result.Markers.Types -join ', ' } else { 'Unbekannt' }
        $item.SubItems[3].Text = if ($null -ne $result.Manifest) { [string]$result.Manifest.FileCount } else { '-' }
        $item.SubItems[4].Text = if ($null -ne $result.Manifest) { Format-Bytes $result.Manifest.Bytes } else { '-' }
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

        $plan = New-Object System.Collections.Generic.List[object]
        $requiredBytes = [long]0
        foreach ($item in $selectedItems) {
            $project = $item.Tag
            $leaf = Split-Path -Path $project.SourcePath -Leaf
            $destination = Join-Path $targetRoot $leaf
            if (Test-Path -LiteralPath $destination) { throw "Ziel existiert bereits: $destination" }
            $requiredBytes += $project.Validation.Manifest.Bytes
            [void]$plan.Add([pscustomobject]@{ Project = $project; Destination = $destination })
        }

        if ($moveFiles.Checked) {
            $available = Get-AvailableBytes -Path $targetRoot
            if ($null -ne $available) {
                $required = [long][Math]::Max(1GB, $requiredBytes * 1.1)
                if ($available -lt $required) { throw "Nicht genügend Speicher. Benötigt: $(Format-Bytes $required), verfügbar: $(Format-Bytes $available)." }
            }
        }

        $summary = ($plan | ForEach-Object { "$($_.Project.SourcePath)`r`n  -> $($_.Destination)`r`n  $($_.Project.Validation.Manifest.FileCount) Dateien, $(Format-Bytes $_.Project.Validation.Manifest.Bytes)" }) -join "`r`n`r`n"
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
            try {
                $status.Text = "Verschiebe $source"
                [System.Windows.Forms.Application]::DoEvents()
                if ($moveFiles.Checked) {
                    Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
                    $moved = $true
                    $verification = Test-DestinationManifest -Manifest $manifest -Destination $destination
                    if (-not $verification.Complete) {
                        throw "Dateiprüfung am Ziel fehlgeschlagen. Fehlend: $($verification.Missing.Count), abweichend: $($verification.Different.Count)."
                    }
                }
                elseif (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                    throw "Zielprojekt existiert nicht: $destination"
                }

                $arguments = @{ ProjectPath = $source; NewPath = $destination; Yes = $true }
                if ($backup.Checked) { $arguments.Backup = $true }
                & $coreScript @arguments
                $completed++
            }
            catch {
                if ($moved -and (Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $source)) {
                    try { Move-Item -LiteralPath $destination -Destination $source -ErrorAction Stop }
                    catch { Write-Warning "Rollback fehlgeschlagen: $($_.Exception.Message)" }
                }
                throw
            }
        }

        $status.Text = "$completed Projekt(e) erfolgreich geprüft und verschoben."
        [void][System.Windows.Forms.MessageBox]::Show($form, "$completed Projekt(e) wurden vollständig geprüft, verschoben und mit Claude Code verknüpft.", 'Abgeschlossen', 'OK', 'Information')
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
