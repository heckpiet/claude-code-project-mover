#requires -Version 5.1

<#
.SYNOPSIS
Native Windows interface for moving one or more Claude Code projects.

.DESCRIPTION
Shows detected Claude Code projects in a Windows Forms checklist. One or more
projects can be selected and moved below a destination root chosen through the
native Windows folder picker. The command-line mover remains the metadata
migration engine.
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
    throw 'The native interface requires Windows. Use claude-project-mover.ps1 on other platforms.'
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

function Get-CwdFromJsonl {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    foreach ($line in [System.IO.File]::ReadLines($File.FullName)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.IndexOf('"cwd"', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($record.PSObject.Properties.Name -contains 'cwd' -and
                -not [string]::IsNullOrWhiteSpace([string]$record.cwd)) {
                return [string]$record.cwd
            }
        }
        catch { }
    }
    return $null
}

function Get-ClaudeProjects {
    param([Parameter(Mandatory)][string]$ProjectsDirectory)

    $items = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory -ErrorAction Stop) {
        if ($directory.Name -match '^(BACKUP__|\.MIGRATION__|\.ROLLBACK__)') { continue }

        $projectPath = $null
        foreach ($file in Get-ChildItem -LiteralPath $directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue) {
            $projectPath = Get-CwdFromJsonl -File $file
            if (-not [string]::IsNullOrWhiteSpace($projectPath)) { break }
        }
        if ([string]::IsNullOrWhiteSpace($projectPath)) { continue }

        [pscustomobject]@{
            DisplayName = $projectPath
            SourcePath = [System.IO.Path]::GetFullPath($projectPath)
            MetadataPath = $directory.FullName
        }
    }

    return @($items | Sort-Object DisplayName)
}

function Get-DirectoryBytes {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [long]0
    foreach ($file in Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop) {
        $bytes += $file.Length
    }
    return $bytes
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

if (-not (Test-Path -LiteralPath $projectsPath -PathType Container)) {
    throw "Claude Code projects directory not found at '$projectsPath'."
}
if (-not (Test-Path -LiteralPath $coreScript -PathType Leaf)) {
    throw "Migration engine not found at '$coreScript'."
}

$projects = Get-ClaudeProjects -ProjectsDirectory $projectsPath
if ($projects.Count -eq 0) { throw 'No Claude Code projects with readable session metadata were found.' }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Claude Code Project Mover'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(920, 680)
$form.MinimumSize = New-Object System.Drawing.Size(760, 560)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Claude Code Projekte verschieben'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($title)

$description = New-Object System.Windows.Forms.Label
$description.Text = 'Wähle ein oder mehrere Projekte und anschließend einen gemeinsamen Zielordner.'
$description.AutoSize = $true
$description.Location = New-Object System.Drawing.Point(23, 54)
$form.Controls.Add($description)

$projectLabel = New-Object System.Windows.Forms.Label
$projectLabel.Text = 'Quellprojekte'
$projectLabel.AutoSize = $true
$projectLabel.Location = New-Object System.Drawing.Point(22, 88)
$form.Controls.Add($projectLabel)

$projectList = New-Object System.Windows.Forms.CheckedListBox
$projectList.CheckOnClick = $true
$projectList.HorizontalScrollbar = $true
$projectList.Anchor = 'Top,Left,Right,Bottom'
$projectList.Location = New-Object System.Drawing.Point(24, 110)
$projectList.Size = New-Object System.Drawing.Size(854, 300)
foreach ($project in $projects) { [void]$projectList.Items.Add($project.DisplayName) }
$form.Controls.Add($projectList)

$selectAllButton = New-Object System.Windows.Forms.Button
$selectAllButton.Text = 'Alle auswählen'
$selectAllButton.Location = New-Object System.Drawing.Point(24, 420)
$selectAllButton.Size = New-Object System.Drawing.Size(110, 30)
$selectAllButton.Add_Click({ for ($i = 0; $i -lt $projectList.Items.Count; $i++) { $projectList.SetItemChecked($i, $true) } })
$form.Controls.Add($selectAllButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = 'Auswahl löschen'
$clearButton.Location = New-Object System.Drawing.Point(142, 420)
$clearButton.Size = New-Object System.Drawing.Size(120, 30)
$clearButton.Add_Click({ for ($i = 0; $i -lt $projectList.Items.Count; $i++) { $projectList.SetItemChecked($i, $false) } })
$form.Controls.Add($clearButton)

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = 'Gemeinsamer Zielordner'
$targetLabel.AutoSize = $true
$targetLabel.Location = New-Object System.Drawing.Point(24, 470)
$form.Controls.Add($targetLabel)

$targetText = New-Object System.Windows.Forms.TextBox
$targetText.Anchor = 'Left,Right,Bottom'
$targetText.Location = New-Object System.Drawing.Point(24, 492)
$targetText.Size = New-Object System.Drawing.Size(730, 25)
$form.Controls.Add($targetText)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Durchsuchen ...'
$browseButton.Anchor = 'Right,Bottom'
$browseButton.Location = New-Object System.Drawing.Point(765, 489)
$browseButton.Size = New-Object System.Drawing.Size(113, 30)
$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Gemeinsamen Zielordner für die ausgewählten Projekte wählen'
    $dialog.ShowNewFolderButton = $true
    if (-not [string]::IsNullOrWhiteSpace($targetText.Text) -and (Test-Path -LiteralPath $targetText.Text -PathType Container)) {
        $dialog.SelectedPath = $targetText.Text
    }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $targetText.Text = $dialog.SelectedPath }
    $dialog.Dispose()
})
$form.Controls.Add($browseButton)

$moveFilesCheck = New-Object System.Windows.Forms.CheckBox
$moveFilesCheck.Text = 'Projektverzeichnisse physisch verschieben'
$moveFilesCheck.Checked = -not $NoProjectMove.IsPresent
$moveFilesCheck.AutoSize = $true
$moveFilesCheck.Location = New-Object System.Drawing.Point(24, 530)
$form.Controls.Add($moveFilesCheck)

$backupCheck = New-Object System.Windows.Forms.CheckBox
$backupCheck.Text = 'Claude-Metadaten als ZIP sichern'
$backupCheck.Checked = $true
$backupCheck.AutoSize = $true
$backupCheck.Location = New-Object System.Drawing.Point(310, 530)
$form.Controls.Add($backupCheck)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Bereit'
$statusLabel.AutoEllipsis = $true
$statusLabel.Anchor = 'Left,Right,Bottom'
$statusLabel.Location = New-Object System.Drawing.Point(24, 570)
$statusLabel.Size = New-Object System.Drawing.Size(620, 24)
$form.Controls.Add($statusLabel)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Abbrechen'
$cancelButton.Anchor = 'Right,Bottom'
$cancelButton.Location = New-Object System.Drawing.Point(650, 566)
$cancelButton.Size = New-Object System.Drawing.Size(105, 34)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)
$form.CancelButton = $cancelButton

$moveButton = New-Object System.Windows.Forms.Button
$moveButton.Text = 'Verschieben'
$moveButton.Anchor = 'Right,Bottom'
$moveButton.Location = New-Object System.Drawing.Point(765, 566)
$moveButton.Size = New-Object System.Drawing.Size(113, 34)
$form.Controls.Add($moveButton)
$form.AcceptButton = $moveButton

$moveButton.Add_Click({
    try {
        $selected = New-Object System.Collections.Generic.List[object]
        foreach ($index in $projectList.CheckedIndices) { [void]$selected.Add($projects[[int]$index]) }
        if ($selected.Count -eq 0) { throw 'Bitte mindestens ein Projekt auswählen.' }

        $targetRoot = $targetText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($targetRoot) -or -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
            throw 'Bitte einen vorhandenen Zielordner auswählen.'
        }
        $targetRoot = [System.IO.Path]::GetFullPath($targetRoot)

        $plan = New-Object System.Collections.Generic.List[object]
        $requiredBytes = [long]0
        foreach ($project in $selected) {
            if (-not (Test-Path -LiteralPath $project.SourcePath -PathType Container)) {
                throw "Quellordner nicht gefunden: $($project.SourcePath)"
            }
            $leafName = Split-Path -Path $project.SourcePath -Leaf
            if ([string]::IsNullOrWhiteSpace($leafName)) { throw "Ungültiger Quellpfad: $($project.SourcePath)" }
            $destination = Join-Path $targetRoot $leafName
            if (Test-Path -LiteralPath $destination) { throw "Ziel existiert bereits: $destination" }
            $size = Get-DirectoryBytes -Path $project.SourcePath
            $requiredBytes += $size
            [void]$plan.Add([pscustomobject]@{ Project = $project; Destination = $destination; Bytes = $size })
        }

        if ($moveFilesCheck.Checked) {
            $availableBytes = Get-AvailableBytes -Path $targetRoot
            if ($null -ne $availableBytes) {
                $requiredWithHeadroom = [long][Math]::Max(1GB, $requiredBytes * 1.1)
                if ($availableBytes -lt $requiredWithHeadroom) {
                    throw "Nicht genügend freier Speicher. Benötigt: $(Format-Bytes $requiredWithHeadroom), verfügbar: $(Format-Bytes $availableBytes)."
                }
            }
        }

        $summary = ($plan | ForEach-Object { "• $($_.Project.SourcePath)`r`n  → $($_.Destination)" }) -join "`r`n"
        $confirmation = [System.Windows.Forms.MessageBox]::Show($form, "Folgende Projekte werden verarbeitet:`r`n`r`n$summary`r`n`r`nFortfahren?", 'Migration bestätigen', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $form.UseWaitCursor = $true
        $moveButton.Enabled = $false
        $browseButton.Enabled = $false
        $completed = 0

        foreach ($item in $plan) {
            $source = $item.Project.SourcePath
            $destination = $item.Destination
            $statusLabel.Text = "Verarbeite $source"
            [System.Windows.Forms.Application]::DoEvents()
            $filesMoved = $false

            try {
                if ($moveFilesCheck.Checked) {
                    Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
                    $filesMoved = $true
                }
                elseif (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                    throw "Das Zielprojekt muss bereits existieren: $destination"
                }

                $arguments = @{ ProjectPath = $source; NewPath = $destination; Yes = $true }
                if ($backupCheck.Checked) { $arguments.Backup = $true }
                & $coreScript @arguments
                $completed++
            }
            catch {
                if ($filesMoved -and (Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $source)) {
                    try { Move-Item -LiteralPath $destination -Destination $source -ErrorAction Stop }
                    catch { Write-Warning "Rollback des Projektordners fehlgeschlagen: $($_.Exception.Message)" }
                }
                throw
            }
        }

        $statusLabel.Text = "$completed Projekt(e) erfolgreich verschoben."
        [void][System.Windows.Forms.MessageBox]::Show($form, "$completed Projekt(e) wurden erfolgreich verschoben und die Claude-Code-Metadaten aktualisiert.", 'Migration abgeschlossen', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    }
    catch {
        $statusLabel.Text = 'Fehler'
        [void][System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Migration fehlgeschlagen', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        $form.UseWaitCursor = $false
        $moveButton.Enabled = $true
        $browseButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
$form.Dispose()
